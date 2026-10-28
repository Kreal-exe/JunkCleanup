using System.Collections.ObjectModel;
using System.Diagnostics;
using Avalonia.Threading;
using JunkCleanup.Core;
using JunkCleanup.Localization;
using JunkCleanup.Settings;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;

namespace JunkCleanup.ViewModels;

public enum AppPage { Dashboard, Targets, Disk, Settings, About }

public sealed record CleanLogItem(string Name, string Glyph, long Bytes, int Failed)
{
    public bool HasFailed => Failed > 0;
    public string FailedText => ByteFormatter.FormatCount(Failed);
}

public sealed partial class MainViewModel : ObservableObject
{
    private static LocalizationManager Loc => LocalizationManager.Instance;

    private readonly ScanEngine _scanner = new();
    private readonly CleanEngine _cleaner = new();
    private readonly IDialogService _dialogs;
    private readonly AppSettings _settings;

    private CancellationTokenSource? _scanCts;
    private CancellationTokenSource? _cleanCts;
    private DispatcherTimer? _confirmTimer;

    /// <summary>Bytes found so far per target while scanning, so the counter only adds up selected targets.</summary>
    private readonly Dictionary<string, long> _targetLiveBytes = new(StringComparer.Ordinal);
    private Func<string> _status = () => string.Empty;
    private bool _suppressSelectionSave;

    public MainViewModel(AppSettings settings, IDialogService dialogs)
    {
        _settings = settings;
        _dialogs = dialogs;

        Settings = new SettingsViewModel(settings, SaveSettings);
        Disk = new DiskViewModel(() => _settings.UseRecycleBin, () => Targets.Where(t => t.IsPresent).Select(t => t.Target).ToList(), dialogs);
        Disk.CleanRequested += () => CurrentPage = AppPage.Dashboard;
        Disk.Removed += (icon, message, freed) =>
        {
            ToastRequested?.Invoke(icon, message);
            if (freed <= 0) return;
            _settings.LifetimeBytesFreed += freed;
            LifetimeFreed = _settings.LifetimeBytesFreed;
            SaveSettings();
            RefreshDisk();
        };
        Settings.CustomFolderAdded += OnCustomFolderAdded;
        Settings.CustomFolderRemoved += OnCustomFolderRemoved;
        Settings.ResetRequested += OnResetRequested;

        foreach (var target in TargetCatalog.All)
            Targets.Add(CreateVm(target));
        foreach (var folder in settings.CustomFolders)
            Targets.Add(CreateVm(TargetCatalog.CreateCustom(folder)));

        foreach (var category in Enum.GetValues<TargetCategory>())
        {
            var inCategory = Targets.Where(t => t.Category == category).ToList();
            Categories.Add(new CategoryVm(category, inCategory, SetCategory));
        }

        RefreshTargetsView();
        RefreshDisk();
        SetStatus(() => Loc["dash.notScanned"]);
        Loc.LanguageChanged += (_, _) => OnLanguageChanged();
        Settings.PropertyChanged += (_, args) =>
        {
            if (args.PropertyName == nameof(SettingsViewModel.UseRecycleBin))
            {
                OnPropertyChanged(nameof(DeleteModeText));
                OnPropertyChanged(nameof(DeleteModeGlyph));
                OnPropertyChanged(nameof(UseRecycleBin));
            }
        };

        LifetimeFreed = settings.LifetimeBytesFreed;
        Recalc();

        Controls.ThemeManager.Changed += () => OnPropertyChanged(nameof(IsDarkTheme));
        _ = RefreshInsightsAsync();
    }

    private async Task RefreshInsightsAsync()
    {
        List<InsightVm> found;
        try
        {
            found = await Task.Run(InsightScanner.Scan);
        }
        catch
        {
            return;
        }

        Insights.Clear();
        foreach (var insight in found) Insights.Add(insight);
        OnPropertyChanged(nameof(HasInsights));
    }

    [RelayCommand]
    private void ToggleTheme() => Settings.Theme = Controls.ThemeManager.IsDark ? "light" : "dark";

    [RelayCommand]
    private async Task RunInsightAction(InsightVm insight)
    {
        switch (insight.Action)
        {
            case InsightAction.CopyCommand when insight.Payload is { } command:
                try
                {
                    await _dialogs.CopyTextAsync(command);
                    insight.Copied = true;
                    ToastRequested?.Invoke("ContentCopy", Loc.Format("insight.copied", command));
                }
                catch
                {
                    // no clipboard available; nothing to do
                }
                break;
            case InsightAction.OpenUrl when insight.Payload is { } url:
                OpenUrl(url);
                break;
        }
    }

    public SettingsViewModel Settings { get; }
    public DiskViewModel Disk { get; }
    public ObservableCollection<TargetVm> Targets { get; } = [];
    public ObservableCollection<CategoryVm> Categories { get; } = [];
    public ObservableCollection<TargetVm> TopTargets { get; } = [];
    /// <summary>The Targets page: Targets filtered by category chip and search text.</summary>
    public ObservableCollection<TargetVm> VisibleTargets { get; } = [];
    public ObservableCollection<CleanLogItem> CleanLog { get; } = [];
    public ObservableCollection<InsightVm> Insights { get; } = [];
    public bool HasInsights => Insights.Count > 0;
    public bool IsDarkTheme => Controls.ThemeManager.IsDark;

    /// <summary>Raised when a short, non-blocking confirmation should appear (icon, text).</summary>
    public event Action<string, string>? ToastRequested;

    /// <summary>Running as root: every location is reachable, and the app says so.</summary>
    public bool IsElevated => Native.IsRoot;
    public string Version => typeof(MainViewModel).Assembly.GetName().Version?.ToString(3) ?? "1.0.0";

    // ── navigation / filtering ──
    [ObservableProperty] private AppPage _currentPage = AppPage.Dashboard;
    [ObservableProperty] private string _searchText = string.Empty;
    [ObservableProperty] private string _filterName = "All";

    // ── scan state ──
    [ObservableProperty] private bool _isScanning;
    [ObservableProperty] private bool _hasResults;
    [ObservableProperty] private bool _nothingFound;
    [ObservableProperty] private string _statusText = string.Empty;
    [ObservableProperty] private long _liveBytes;
    [ObservableProperty] private long _displayBytes;
    [ObservableProperty] private long _selectedBytes;
    [ObservableProperty] private long _foundBytes;
    [ObservableProperty] private long _foundFiles;
    [ObservableProperty] private long _selectedFiles;
    [ObservableProperty] private int _selectedCount;
    [ObservableProperty] private int _presentCount;
    [ObservableProperty] private double _ringAngle;
    [ObservableProperty] private int _scanCompleted;
    [ObservableProperty] private int _scanTotal;
    [ObservableProperty] private string _currentTargetName = string.Empty;
    [ObservableProperty] private long _lifetimeFreed;

    // ── disk ──
    [ObservableProperty] private long _diskUsed;
    [ObservableProperty] private long _diskTotal;
    [ObservableProperty] private long _diskFree;
    [ObservableProperty] private double _diskShare;
    [ObservableProperty] private string _diskName = "/";

    // ── clean overlay ──
    [ObservableProperty] private bool _isCleanOverlayVisible;
    [ObservableProperty] private bool _isCleaning;
    [ObservableProperty] private bool _cleanDone;
    [ObservableProperty] private bool _isStoppingClean;

    // ── details sheet ──
    [ObservableProperty] private TargetVm? _detailsTarget;
    [ObservableProperty] private long _cleanFreed;
    [ObservableProperty] private double _cleanProgress;
    [ObservableProperty] private string _cleanCurrent = string.Empty;
    [ObservableProperty] private int _cleanFiles;
    [ObservableProperty] private int _cleanFailed;
    [ObservableProperty] private string _cleanSummary = string.Empty;

    public bool CanClean => HasResults && !IsScanning && !IsCleaning && SelectedBytes > 0;
    public bool CanStopClean => IsCleaning && !IsStoppingClean;
    public bool IsDetailsOpen => DetailsTarget is not null;
    public string DetailsSubtitle => DetailsTarget is { } t
        ? ByteFormatter.Format(t.Bytes) + " · " + Loc.Format("dash.filesCount", ByteFormatter.FormatCount(t.FileCount))
        : string.Empty;

    partial void OnDetailsTargetChanged(TargetVm? value)
    {
        OnPropertyChanged(nameof(DetailsSubtitle));
        OnPropertyChanged(nameof(IsDetailsOpen));
    }

    public string DiskText => Loc.Format("disk.used", ByteFormatter.Format(DiskUsed), ByteFormatter.Format(DiskTotal));
    public string DiskFreeText => Loc.Format("disk.free", ByteFormatter.Format(DiskFree));
    public string LifetimeText => Loc.Format("disk.lifetime", ByteFormatter.Format(LifetimeFreed));
    public bool HasLifetime => LifetimeFreed > 0;
    public bool UseRecycleBin => _settings.UseRecycleBin;

    public string ScanButtonText => IsScanning ? Loc["dash.stop"] : HasResults ? Loc["dash.rescan"] : Loc["dash.scan"];
    public string ScanButtonGlyph => IsScanning ? "Stop" : "Play";
    public string CleanButtonText => SelectedBytes > 0 ? Loc.Format("dash.clean", ByteFormatter.Format(SelectedBytes)) : Loc["dash.cleanEmpty"];
    public string DeleteModeText => _settings.UseRecycleBin ? Loc["dash.modeRecycle"] : Loc["dash.modePermanent"];
    public string DeleteModeGlyph => _settings.UseRecycleBin ? "TrashCanOutline" : "AlertCircleOutline";
    public string TargetsSubtitle => Loc.Format("targets.subtitle", PresentCount, SelectedCount, ByteFormatter.Format(SelectedBytes));
    public bool IsTargetsViewEmpty => VisibleTargets.Count == 0;
    public string SettingsFolder => SettingsStore.Directory;
    public string TargetCountText => Loc.Format("about.targets", TargetCatalog.All.Count);
    public string LanguagesText => Loc.Format("about.languages", LocalizationManager.Languages.Count);
    public string BuiltWithText => Loc.Format("about.builtWith", Environment.Version.Major);
    public string VersionText => Loc.Format("about.version", Version);

    public bool IsDashboardPage => CurrentPage == AppPage.Dashboard;
    public bool IsTargetsPage => CurrentPage == AppPage.Targets;
    public bool IsDiskPage => CurrentPage == AppPage.Disk;
    public bool IsSettingsPage => CurrentPage == AppPage.Settings;
    public bool IsAboutPage => CurrentPage == AppPage.About;

    partial void OnCurrentPageChanged(AppPage value)
    {
        OnPropertyChanged(nameof(IsDashboardPage));
        OnPropertyChanged(nameof(IsTargetsPage));
        OnPropertyChanged(nameof(IsDiskPage));
        // Normally measured with the scan; when nothing has run yet, the page measures it on first open.
        if (value == AppPage.Disk && !Disk.HasReport && !Disk.IsAnalyzing) _ = Disk.Analyze();
        OnPropertyChanged(nameof(IsSettingsPage));
        OnPropertyChanged(nameof(IsAboutPage));
    }

    partial void OnSearchTextChanged(string value) => RefreshTargetsView();
    partial void OnFilterNameChanged(string value) => RefreshTargetsView();
    partial void OnHasResultsChanged(bool value) { OnPropertyChanged(nameof(CanClean)); OnPropertyChanged(nameof(ScanButtonText)); }
    partial void OnIsScanningChanged(bool value) { OnPropertyChanged(nameof(CanClean)); OnPropertyChanged(nameof(ScanButtonText)); OnPropertyChanged(nameof(ScanButtonGlyph)); }
    partial void OnIsCleaningChanged(bool value) { OnPropertyChanged(nameof(CanClean)); OnPropertyChanged(nameof(CanStopClean)); }
    partial void OnIsStoppingCleanChanged(bool value) => OnPropertyChanged(nameof(CanStopClean));
    partial void OnSelectedBytesChanged(long value) { OnPropertyChanged(nameof(CanClean)); OnPropertyChanged(nameof(CleanButtonText)); OnPropertyChanged(nameof(TargetsSubtitle)); }
    partial void OnSelectedCountChanged(int value) => OnPropertyChanged(nameof(TargetsSubtitle));
    partial void OnPresentCountChanged(int value) => OnPropertyChanged(nameof(TargetsSubtitle));
    partial void OnDiskUsedChanged(long value) => OnPropertyChanged(nameof(DiskText));
    partial void OnDiskFreeChanged(long value) => OnPropertyChanged(nameof(DiskFreeText));
    partial void OnLifetimeFreedChanged(long value) { OnPropertyChanged(nameof(LifetimeText)); OnPropertyChanged(nameof(HasLifetime)); }

    private void OnLanguageChanged()
    {
        StatusText = _status();
        RefreshTargetsView();
        foreach (var name in new[]
                 {
                     nameof(DiskText), nameof(DiskFreeText), nameof(LifetimeText), nameof(ScanButtonText), nameof(CleanButtonText), nameof(DeleteModeText),
                     nameof(TargetsSubtitle), nameof(TargetCountText), nameof(LanguagesText), nameof(BuiltWithText), nameof(VersionText),
                     nameof(DetailsSubtitle),
                 })
        {
            OnPropertyChanged(name);
        }
    }

    // ─────────────────────────── commands ───────────────────────────

    [RelayCommand]
    private void Navigate(AppPage page) => CurrentPage = page;

    [RelayCommand]
    private void SetFilter(string name) => FilterName = name;

    [RelayCommand]
    private void OpenCategory(CategoryVm category)
    {
        FilterName = category.Category.ToString();
        CurrentPage = AppPage.Targets;
    }

    [RelayCommand]
    private void ToggleScan()
    {
        if (IsScanning) CancelScan();
        else _ = ScanAsync();
    }

    [RelayCommand]
    private void CancelScan()
    {
        // Esc closes the details sheet, or stops whichever is running.
        if (DetailsTarget is not null) DetailsTarget = null;
        else if (IsCleaning) StopClean();
        else _scanCts?.Cancel();
    }

    [RelayCommand]
    public async Task ScanAsync()
    {
        if (IsScanning || IsCleaning) return;

        _scanCts = new CancellationTokenSource();
        IsScanning = true;
        // One scan: the disk map is measured alongside the caches.
        if (!Disk.IsAnalyzing) _ = Disk.Analyze();
        HasResults = false;
        NothingFound = false;
        LiveBytes = 0;
        DisplayBytes = 0;
        _targetLiveBytes.Clear();
        ScanCompleted = 0;
        ScanTotal = Targets.Count(t => t.IsPresent);
        CurrentTargetName = string.Empty;

        foreach (var t in Targets) t.ResetForScan();
        Recalc();
        SetStatus(() => Loc.Format("dash.scanningProgress", ScanCompleted, ScanTotal));

        var sw = Stopwatch.StartNew();
        var options = new ScanOptions { SkipNewerThan = TimeSpan.FromHours(_settings.SkipRecentHours) };
        var targets = Targets.Where(t => t.IsPresent).Select(t => t.Target).ToList();
        var progress = new Progress<ScanProgress>(OnScanProgress);
        var cancelled = false;

        try
        {
            await _scanner.ScanAsync(targets, options, progress, _scanCts.Token);
        }
        catch (OperationCanceledException)
        {
            cancelled = true;
        }
        finally
        {
            IsScanning = false;
            _scanCts.Dispose();
            _scanCts = null;
        }

        foreach (var t in Targets.Where(t => t.State == TargetState.Scanning))
            t.State = TargetState.Idle;

        Recalc();
        HasResults = !cancelled;
        NothingFound = !cancelled && FoundBytes == 0;

        if (cancelled)
        {
            SetStatus(() => Loc["dash.cancelled"]);
        }
        else
        {
            var seconds = sw.Elapsed.TotalSeconds.ToString("0.0");
            var scanned = targets.Count;
            SetStatus(() => Loc.Format("dash.lastScan", scanned, seconds, ByteFormatter.FormatCount(FoundFiles)));
        }
    }

    private void OnScanProgress(ScanProgress p)
    {
        LiveBytes = p.BytesFound;
        if (p.Phase != ScanPhase.Started) _targetLiveBytes[p.TargetId] = p.TargetBytes;
        DisplayBytes = SelectedLiveBytes();
        ScanCompleted = p.Completed;
        StatusText = _status();

        var vm = Targets.FirstOrDefault(t => t.Id == p.TargetId);
        if (vm is null) return;

        if (p.Phase == ScanPhase.Started) CurrentTargetName = vm.Name;
        if (p.Result is not null)
        {
            vm.Apply(p.Result);
            Recalc();
        }
    }

    [RelayCommand]
    private async Task CleanAsync()
    {
        if (IsScanning || IsCleaning) return;

        var selected = Targets.Where(t => t.IsEnabled && t.LastResult is not null && t.Bytes > 0).ToList();
        if (selected.Count == 0) return;

        var bytes = selected.Sum(t => t.Bytes);
        var files = selected.Sum(t => (long)t.FileCount);
        var recycle = _settings.UseRecycleBin;

        var ok = await _dialogs.ConfirmAsync(
            Loc.Format("clean.confirmTitle", ByteFormatter.Format(bytes)),
            Loc.Format(recycle ? "clean.confirmRecycle" : "clean.confirmPermanent", ByteFormatter.FormatCount(files), selected.Count),
            Loc["clean.confirm"],
            danger: !recycle);
        if (!ok) return;

        IsCleaning = true;
        CleanDone = false;
        IsStoppingClean = false;
        _cleanCts = new CancellationTokenSource();
        CleanFreed = 0;
        CleanProgress = 0;
        CleanFiles = 0;
        CleanFailed = 0;
        CleanCurrent = string.Empty;
        CleanSummary = string.Empty;
        CleanLog.Clear();
        IsCleanOverlayVisible = true;

        var progress = new Progress<CleanProgress>(p =>
        {
            CleanFreed = p.BytesFreed;
            CleanFiles = p.FilesDeleted;
            CleanFailed = p.Failed;
            CleanProgress = p.TargetsTotal > 0 ? (double)p.TargetsDone / p.TargetsTotal : 0;

            var vm = Targets.FirstOrDefault(t => t.Id == p.TargetId);
            if (vm is null) return;
            CleanCurrent = Loc.Format("clean.current", vm.Name);

            if (p.TargetDone && p.TargetResult is not null)
            {
                vm.ApplyClean(p.TargetResult);
                CleanLog.Insert(0, new CleanLogItem(vm.Name, vm.Glyph, p.TargetResult.BytesFreed, p.TargetResult.Failed));
            }
        });

        var sw = Stopwatch.StartNew();
        CleanReport report;
        try
        {
            report = await _cleaner.CleanAsync(
                selected.Select(t => t.LastResult!).ToList(),
                new CleanOptions { UseRecycleBin = recycle },
                progress,
                _cleanCts.Token);
        }
        catch (Exception ex)
        {
            report = new CleanReport();
            CleanSummary = ex.Message;
        }

        CleanProgress = 1;
        CleanFreed = report.BytesFreed;
        CleanFiles = report.FilesDeleted;
        CleanFailed = report.Failed;
        CleanCurrent = string.Empty;
        if (string.IsNullOrEmpty(CleanSummary))
        {
            CleanSummary = report.Cancelled
                ? Loc.Format("clean.stopped", ByteFormatter.FormatCount(report.FilesDeleted))
                : report.Failed > 0
                ? Loc.Format("clean.summary", ByteFormatter.FormatCount(report.FilesDeleted), ByteFormatter.FormatCount(report.Failed))
                : Loc.Format("clean.summaryOk", ByteFormatter.FormatCount(report.FilesDeleted), sw.Elapsed.TotalSeconds.ToString("0.0"));
        }

        _settings.LifetimeBytesFreed += report.BytesFreed;
        LifetimeFreed = _settings.LifetimeBytesFreed;
        SaveSettings();

        _cleanCts.Dispose();
        _cleanCts = null;
        IsCleaning = false;
        CleanDone = true;
        Recalc();
        RefreshDisk();
        var freed = report.BytesFreed;
        SetStatus(() => Loc.Format("dash.cleaned", ByteFormatter.Format(freed)));
        // The disk changed: measure it again in the background.
        if (!Disk.IsAnalyzing) _ = Disk.Analyze();
    }

    /// <summary>Stops a running clean; files already removed stay removed, the rest are left alone.</summary>
    [RelayCommand]
    private void StopClean()
    {
        if (!IsCleaning || IsStoppingClean) return;
        IsStoppingClean = true;
        _cleanCts?.Cancel();
    }

    [RelayCommand]
    private void CloseCleanOverlay()
    {
        IsCleanOverlayVisible = false;
        if (CleanDone && CleanFreed > 0)
            ToastRequested?.Invoke("CheckBold", Loc.Format("toast.freed", ByteFormatter.Format(CleanFreed)));
        _ = RefreshInsightsAsync();
    }

    // ─────────────────────────── details ───────────────────────────

    [RelayCommand]
    private void OpenDetails(TargetVm target) => DetailsTarget = target;

    [RelayCommand]
    private void CloseDetails() => DetailsTarget = null;

    [RelayCommand]
    private void RevealEntry(EntryVm entry) => _ = Task.Run(() => Platform.Reveal(entry.Path));

    [RelayCommand]
    private void RevealDetailsRoot()
    {
        if (DetailsTarget is { IsRecycleBin: true }) OpenFolder(Path.Combine(RecycleBinNative.HomeTrash, "files"));
        else if (DetailsTarget?.Roots.FirstOrDefault() is { } root) OpenFolder(root);
    }

    [RelayCommand]
    private void AskDeleteEntry(EntryVm entry)
    {
        if (DetailsTarget is not null)
            foreach (var e in DetailsTarget.TopEntries) e.IsConfirming = false;
        entry.IsConfirming = true;
        _confirmTimer?.Stop();
        _confirmTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(3.5) };
        _confirmTimer.Tick += (_, _) =>
        {
            _confirmTimer!.Stop();
            if (!entry.IsBusy) entry.IsConfirming = false;
        };
        _confirmTimer.Start();
    }

    [RelayCommand]
    private async Task DeleteEntry(EntryVm entry)
    {
        var target = DetailsTarget;
        if (target?.LastResult is not { } scan || IsScanning || IsCleaning || entry.IsBusy) return;

        entry.IsBusy = true;
        var recycle = _settings.UseRecycleBin;
        var result = await Task.Run(() => _cleaner.RemoveEntry(scan, entry.Summary, new CleanOptions { UseRecycleBin = recycle }));
        entry.IsBusy = false;
        entry.IsConfirming = false;
        if (result is null) return;

        target.ApplyEntryRemoval(entry, result);
        _settings.LifetimeBytesFreed += result.BytesFreed;
        LifetimeFreed = _settings.LifetimeBytesFreed;
        SaveSettings();
        Recalc();
        RefreshDisk();
        OnPropertyChanged(nameof(DetailsSubtitle));
        ToastRequested?.Invoke("CheckBold", Loc.Format(recycle ? "details.trashed" : "details.deleted", entry.Name, ByteFormatter.Format(result.BytesFreed)));
    }

    [RelayCommand]
    private void SelectSafe() => BulkSelect(t => t.IsPresent && t.Risk == RiskLevel.Safe && !t.IsRecycleBin);

    [RelayCommand]
    private void SelectAll() => BulkSelect(t => t.IsPresent);

    [RelayCommand]
    private void SelectNone() => BulkSelect(_ => false);

    [RelayCommand]
    private void ToggleExpand(TargetVm target) => target.IsExpanded = !target.IsExpanded;

    [RelayCommand]
    private void OpenFolder(string? path)
    {
        if (string.IsNullOrEmpty(path)) return;
        if (Directory.Exists(path)) _ = Task.Run(() => Platform.Open(path));
        else if (File.Exists(path)) _ = Task.Run(() => Platform.Reveal(path));
    }

    [RelayCommand]
    private void OpenUrl(string url) => _ = Task.Run(() => Platform.Open(url));

    [RelayCommand]
    private async Task AddCustomFolder()
    {
        var folder = await _dialogs.PickFolderAsync();
        if (string.IsNullOrEmpty(folder)) return;
        if (!Settings.TryAddCustomFolder(folder))
            await _dialogs.ConfirmAsync(Loc["settings.customFolders"], Loc["settings.customFolders.refused"], Loc["common.ok"], false);
    }

    // ─────────────────────────── internals ───────────────────────────

    private TargetVm CreateVm(CleanupTarget target)
    {
        var enabled = _settings.TargetStates.TryGetValue(target.Id, out var saved) ? saved : target.EnabledByDefault;
        return new TargetVm(target, enabled, OnTargetSelectionChanged);
    }

    private void OnTargetSelectionChanged(TargetVm target)
    {
        _settings.TargetStates[target.Id] = target.IsEnabled;
        if (_suppressSelectionSave) return;
        SaveSettings();
        Recalc();
    }

    private void SetCategory(CategoryVm category, bool enabled)
    {
        // Switching a category on never picks up its Careful targets (model caches, browser binaries…); those are ticked one by one.
        BulkSelect(t => t.Category == category.Category
            ? enabled && t.IsPresent && (t.Risk != RiskLevel.Careful || t.IsEnabled)
            : t.IsEnabled);
    }

    private void BulkSelect(Func<TargetVm, bool> predicate)
    {
        _suppressSelectionSave = true;
        foreach (var t in Targets) t.IsEnabled = predicate(t);
        _suppressSelectionSave = false;
        SaveSettings();
        Recalc();
    }

    private void Recalc()
    {
        var present = Targets.Where(t => t.IsPresent).ToList();
        FoundBytes = present.Sum(t => t.Bytes);
        FoundFiles = present.Sum(t => (long)t.FileCount);
        var selected = present.Where(t => t.IsEnabled).ToList();
        SelectedBytes = selected.Sum(t => t.Bytes);
        SelectedFiles = selected.Sum(t => (long)t.FileCount);
        SelectedCount = selected.Count;
        PresentCount = present.Count;

        foreach (var c in Categories) c.Recalc(FoundBytes);

        DisplayBytes = IsScanning ? SelectedLiveBytes() : SelectedBytes;
        RingAngle = FoundBytes > 0 ? 360.0 * SelectedBytes / FoundBytes : 0;

        var max = present.Count > 0 ? present.Max(t => t.Bytes) : 0;
        foreach (var t in present) t.Share = max > 0 ? (double)t.Bytes / max : 0;

        var top = present.Where(t => t.Bytes > 0).OrderByDescending(t => t.Bytes).Take(6).ToList();
        if (!top.SequenceEqual(TopTargets))
        {
            TopTargets.Clear();
            foreach (var t in top) TopTargets.Add(t);
        }
    }

    private long SelectedLiveBytes()
        => Targets.Where(t => t.IsEnabled).Sum(t => _targetLiveBytes.GetValueOrDefault(t.Id));

    private bool FilterTarget(TargetVm t)
    {
        if (FilterName != "All" && t.Category.ToString() != FilterName) return false;
        if (string.IsNullOrWhiteSpace(SearchText)) return true;

        var q = SearchText.Trim();
        return t.Name.Contains(q, StringComparison.CurrentCultureIgnoreCase)
            || t.Description.Contains(q, StringComparison.CurrentCultureIgnoreCase)
            || t.RootsText.Contains(q, StringComparison.OrdinalIgnoreCase);
    }

    private void RefreshTargetsView()
    {
        var visible = Targets.Where(FilterTarget).ToList();
        if (!visible.SequenceEqual(VisibleTargets))
        {
            VisibleTargets.Clear();
            foreach (var t in visible) VisibleTargets.Add(t);
        }
        OnPropertyChanged(nameof(IsTargetsViewEmpty));
    }

    private void SetStatus(Func<string> status)
    {
        _status = status;
        StatusText = status();
    }

    private void RefreshDisk()
    {
        try
        {
            var (name, total, free, used) = Platform.HomeDisk();
            DiskTotal = total;
            DiskFree = free;
            DiskUsed = used;
            DiskShare = total > 0 ? (double)used / total : 0;
            DiskName = name;
        }
        catch
        {
            // no drive info; leave zeros
        }
    }

    private void OnCustomFolderAdded(string folder)
    {
        var target = TargetCatalog.CreateCustom(folder);
        if (Targets.Any(t => t.Id == target.Id)) return;

        var vm = CreateVm(target);
        vm.IsEnabled = true;
        Targets.Add(vm);

        var custom = Categories.First(c => c.Category == TargetCategory.Custom);
        var replacement = new CategoryVm(TargetCategory.Custom, Targets.Where(t => t.Category == TargetCategory.Custom).ToList(), SetCategory);
        Categories[Categories.IndexOf(custom)] = replacement;
        RefreshTargetsView();
        Recalc();
    }

    private void OnCustomFolderRemoved(string folder)
    {
        var id = TargetCatalog.CreateCustom(folder).Id;
        var vm = Targets.FirstOrDefault(t => t.Id == id);
        if (vm is null) return;
        Targets.Remove(vm);
        _settings.TargetStates.Remove(id);

        var custom = Categories.First(c => c.Category == TargetCategory.Custom);
        var replacement = new CategoryVm(TargetCategory.Custom, Targets.Where(t => t.Category == TargetCategory.Custom).ToList(), SetCategory);
        Categories[Categories.IndexOf(custom)] = replacement;
        RefreshTargetsView();
        SaveSettings();
        Recalc();
    }

    private void OnResetRequested()
    {
        _settings.TargetStates.Clear();
        foreach (var folder in _settings.CustomFolders.ToList())
            Settings.RemoveCustomFolderCommand.Execute(folder);

        _suppressSelectionSave = true;
        foreach (var t in Targets) t.IsEnabled = t.Target.EnabledByDefault && t.IsPresent;
        _suppressSelectionSave = false;

        Settings.UseRecycleBin = true;
        Settings.Animations = true;
        Settings.ScanOnStartup = true;
        Settings.SkipRecentHours = 24;
        Settings.Theme = "dark";
        Settings.SelectedLanguage = Settings.Languages[0];

        SaveSettings();
        Recalc();
    }

    private void SaveSettings() => SettingsStore.Save(_settings);
}
