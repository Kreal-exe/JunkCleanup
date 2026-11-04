using System.Collections.ObjectModel;
using System.Diagnostics;
using System.Windows.Media;
using System.Windows.Threading;
using JunkCleanup.Core;
using JunkCleanup.Localization;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;

namespace JunkCleanup.ViewModels;

/// <summary>A band of the disk bar (or a legend entry): a share of the whole disk.</summary>
public sealed partial class SegmentVm : ObservableObject
{
    public SegmentVm(SpaceSegment segment, Brush brush)
    {
        Segment = segment;
        Key = "disk.seg." + segment;
        Brush = brush;
        DimBrush = brush.Clone();
        DimBrush.Opacity = 0.22;
        DimBrush.Freeze();
        LocalizationManager.Instance.LanguageChanged += (_, _) => OnPropertyChanged(nameof(Name));
    }

    public SpaceSegment Segment { get; }
    public string Key { get; }
    public string Name => LocalizationManager.Instance[Key];
    public Brush Brush { get; }
    private Brush DimBrush { get; }
    [ObservableProperty] private long _bytes;
    public bool HasBytes => Bytes > 0;
    partial void OnBytesChanged(long value) => OnPropertyChanged(nameof(HasBytes));

    /// <summary>Another band is picked: this one fades, in the bar and in the legend.</summary>
    [ObservableProperty] private bool _isDimmed;
    [ObservableProperty] private bool _isPicked;
    public Brush DisplayBrush => IsDimmed ? DimBrush : Brush;
    partial void OnIsDimmedChanged(bool value) => OnPropertyChanged(nameof(DisplayBrush));
}

public static class SpaceColors
{
    // The category palette of Styles.xaml, plus grey for the system and for Keep.
    public static Color Of(SpaceSegment segment) => segment switch
    {
        SpaceSegment.System => Rgb(0x8E96AB),
        SpaceSegment.Apps => Rgb(0x34D399),
        SpaceSegment.Caches => Rgb(0x22D3EE),
        SpaceSegment.Developer => Rgb(0xA78BFA),
        SpaceSegment.Models => Rgb(0xF472B6),
        SpaceSegment.VirtualMachines => Rgb(0xF59E0B),
        SpaceSegment.Files => Rgb(0x60A5FA),
        _ => Rgb(0xFB7185),
    };

    public static Brush Brush(SpaceSegment segment, bool soft = false) => Frozen(Of(segment), soft);

    public static Brush Risk(SpaceRisk risk, bool soft = false) => Frozen(risk switch
    {
        SpaceRisk.Safe => Rgb(0x2DBE8A),
        SpaceRisk.Moderate => Rgb(0xE0A315),
        SpaceRisk.Careful => Rgb(0xF05A75),
        _ => Rgb(0x8E96AB),
    }, soft);

    private static Color Rgb(int rgb) => Color.FromRgb((byte)(rgb >> 16), (byte)(rgb >> 8), (byte)rgb);

    private static Brush Frozen(Color color, bool soft)
    {
        var brush = new SolidColorBrush(color) { Opacity = soft ? 0.16 : 1 };
        brush.Freeze();
        return brush;
    }
}

public sealed partial class SpaceItemVm : ObservableObject
{
    private static LocalizationManager Loc => LocalizationManager.Instance;

    public SpaceItemVm(SpaceEntry entry, long used, int depth)
    {
        Entry = entry;
        Depth = depth;
        _bytes = entry.Bytes;
        Share = used > 0 ? (double)entry.Bytes / used : 0;
        foreach (var child in entry.Children) Children.Add(new SpaceItemVm(child, used, depth + 1));
        Loc.LanguageChanged += (_, _) =>
        {
            OnPropertyChanged(nameof(Name));
            OnPropertyChanged(nameof(Description));
            OnPropertyChanged(nameof(RiskText));
            OnPropertyChanged(nameof(RiskHint));
            OnPropertyChanged(nameof(SafeText));
        };
    }

    public SpaceEntry Entry { get; }
    public int Depth { get; }
    public bool IsChild => Depth > 0;
    public ObservableCollection<SpaceItemVm> Children { get; } = [];
    public bool HasChildren => Children.Count > 0;

    /// <summary>A listed folder (a model, a VM) keeps its own name; parts and known items use their localized name.</summary>
    public string Name => Entry.Name
        ?? (Entry.Key is { } key
            // a known item's part: its kind and folder ("The app itself · installs"), so parts of one kind differ
            ? key.StartsWith("space.kind.", StringComparison.Ordinal) && Entry.Paths.Count == 1
                ? Loc[key + ".name"] + " · " + System.IO.Path.GetFileName(Entry.Path)
                : Loc[key + ".name"]
            : Entry.Path);
    public string Description => Entry.Key is { } key && Loc.Has(key + ".desc") ? Loc[key + ".desc"] : string.Empty;
    public bool HasDescription => Description.Length > 0;
    public string PathText => Entry.Paths.Count == 0 ? string.Empty : string.Join("   ·   ", Entry.Paths.Select(Shorten));
    public bool HasPath => Entry.Paths.Count > 0;
    public string Glyph => Entry.Glyph;
    public SpaceRisk Risk => Entry.Risk;
    public string RiskText => Loc["risk." + Risk];
    public string RiskHint => Loc["risk." + Risk + ".desc"];
    public Brush RiskBrush => SpaceColors.Risk(Risk);
    public Brush RiskSoftBrush => SpaceColors.Risk(Risk, soft: true);
    public Brush Brush => SpaceColors.Brush(Entry.Segment);
    public Brush SoftBrush => SpaceColors.Brush(Entry.Segment, soft: true);
    public double Share { get; private set; }

    public bool CanDelete => Entry.CanDelete && Bytes > 0;

    /// <summary>What can go without a second thought: this item when it is Safe, else its Safe parts.</summary>
    public IEnumerable<SpaceItemVm> SafeParts => Risk == SpaceRisk.Safe && CanDelete
        ? [this]
        : Children.Where(c => c.Risk == SpaceRisk.Safe && c.CanDelete);
    public long SafeBytes => SafeParts.Sum(p => p.Bytes);
    public bool HasSafe => Children.Count > 0 && SafeBytes > 0;
    public string SafeText => Loc.Format("disk.safe", ByteFormatter.Format(SafeBytes));
    public bool HasCommand => Entry.Command is not null && !IsRepairable;
    /// <summary>Lost clusters: one button runs the repair instead of a command to copy.</summary>
    public bool IsRepairable => Entry.Id == "lost";
    public bool IsCleanable => Entry.Id == "caches" || Entry.TargetId is not null;
    public bool CanReveal => Entry.Paths.Count > 0 && (Directory.Exists(Entry.Path) || File.Exists(Entry.Path));

    [ObservableProperty] private long _bytes;
    [ObservableProperty] private bool _isExpanded;
    [ObservableProperty] private bool _isConfirming;
    [ObservableProperty] private bool _isBusy;

    partial void OnBytesChanged(long value)
    {
        OnPropertyChanged(nameof(CanDelete));
        OnPropertyChanged(nameof(SafeBytes));
        OnPropertyChanged(nameof(HasSafe));
        OnPropertyChanged(nameof(SafeText));
    }

    /// <summary>A part was removed: the parent's safe total changes too.</summary>
    public void Refresh()
    {
        OnPropertyChanged(nameof(SafeBytes));
        OnPropertyChanged(nameof(HasSafe));
        OnPropertyChanged(nameof(SafeText));
    }

    private static string Shorten(string path) => path;
}

/// <summary>A drive the Disk page can map: its letter, label and free space.</summary>
public sealed class DriveOption
{
    public DriveOption(DriveInfo drive)
    {
        Root = drive.RootDirectory.FullName;
        var label = string.Empty;
        try { label = drive.VolumeLabel; } catch { /* no label */ }
        Label = label;
        try { Free = drive.AvailableFreeSpace; } catch { /* went away */ }
    }

    public string Root { get; }
    public string Letter => Root.TrimEnd('\\');
    public string Label { get; }
    public long Free { get; }
    public string Name => Label.Length > 0 ? Letter + "  " + Label : Letter;
    public string FreeText => LocalizationManager.Instance.Format("disk.free", ByteFormatter.Format(Free));

    /// <summary>Local drives that are ready: fixed disks and USB drives, not optical or network ones.</summary>
    public static List<DriveOption> All()
    {
        var list = new List<DriveOption>();
        try
        {
            foreach (var drive in DriveInfo.GetDrives())
            {
                try
                {
                    if (drive.DriveType is DriveType.Fixed or DriveType.Removable && drive.IsReady && drive.TotalSize > 0)
                        list.Add(new DriveOption(drive));
                }
                catch
                {
                    // a drive that went away
                }
            }
        }
        catch
        {
            // no drive list; the home drive is mapped
        }
        return list;
    }
}

/// <summary>The Disk page: what fills the disk, band by band and folder by folder, and what can go.</summary>
public sealed partial class DiskViewModel : ObservableObject
{
    private static LocalizationManager Loc => LocalizationManager.Instance;

    private readonly DiskMapEngine _engine = new();
    private readonly Func<bool> _useRecycleBin;
    private readonly Func<IReadOnlyList<CleanupTarget>> _targets;
    private readonly IDialogService _dialogs;
    private readonly Action<string, string> _toast;
    private CancellationTokenSource? _cts;
    private SpaceReport? _report;
    private DispatcherTimer? _confirmTimer;
    private Func<string> _status;
    private bool _reanalyze;
    private bool _refreshingDrives;

    public DiskViewModel(Func<bool> useRecycleBin, Func<IReadOnlyList<CleanupTarget>> targets, IDialogService dialogs, Action<string, string> toast)
    {
        _toast = toast;
        _useRecycleBin = useRecycleBin;
        _targets = targets;
        _dialogs = dialogs;
        foreach (var segment in Enum.GetValues<SpaceSegment>())
            Segments.Add(new SegmentVm(segment, SpaceColors.Brush(segment)));
        ItemsView = System.Windows.Data.CollectionViewSource.GetDefaultView(Items);
        ItemsView.Filter = o => _filter is not { } f || ((SpaceItemVm)o).Entry.Segment == f;
        _status = () => Loc["disk.notAnalyzed"];
        _statusText = _status();
        Loc.LanguageChanged += (_, _) =>
        {
            StatusText = _status();
            OnPropertyChanged(nameof(SubtitleText));
            OnPropertyChanged(nameof(AnalyzeText));
            OnPropertyChanged(nameof(FreeText));
            RefreshDrives();   // the drive list's "… free" text
        };
        RefreshDrives();
    }

    /// <summary>The drives to choose from; the picker shows only when there is more than one.</summary>
    [ObservableProperty] private List<DriveOption> _drives = [];
    [ObservableProperty] private DriveOption? _selectedDrive;
    public bool HasDrives => Drives.Count > 1;

    partial void OnDrivesChanged(List<DriveOption> value) => OnPropertyChanged(nameof(HasDrives));

    /// <summary>Picks a drive by letter ("D", "D:", "D:\"); for the hidden --drive switch.</summary>
    public void SelectDrive(string letter)
    {
        var root = letter.TrimEnd('\\', ':') + ":\\";
        if (Drives.FirstOrDefault(d => d.Root.Equals(root, StringComparison.OrdinalIgnoreCase)) is { } drive) SelectedDrive = drive;
    }

    /// <summary>Reads the drives again, keeping the one picked if it is still there.</summary>
    public void RefreshDrives()
    {
        var root = SelectedDrive?.Root ?? SpaceCatalog.HomeDrive;
        var drives = DriveOption.All();
        // The same drive read again is not a new pick: the picker may clear and restore its selection meanwhile.
        _refreshingDrives = true;
        Drives = drives;
        SelectedDrive = drives.FirstOrDefault(d => d.Root.Equals(root, StringComparison.OrdinalIgnoreCase))
            ?? drives.FirstOrDefault(d => d.Root.Equals(SpaceCatalog.HomeDrive, StringComparison.OrdinalIgnoreCase))
            ?? drives.FirstOrDefault();
        _refreshingDrives = false;
    }

    partial void OnSelectedDriveChanged(DriveOption? oldValue, DriveOption? newValue)
    {
        if (_refreshingDrives || newValue is null || oldValue?.Root == newValue.Root) return;
        // Another drive: the old map goes, the new one is measured (after the running analysis stops).
        _report = null;
        HasReport = false;
        Items.Clear();
        Total = Free = 0;
        foreach (var vm in Segments) vm.Bytes = 0;
        FilterBy(null);
        OnPropertyChanged(nameof(SubtitleText));
        if (IsAnalyzing)
        {
            _reanalyze = true;
            _cts?.Cancel();
        }
        else
        {
            _ = Analyze();
        }
    }

    /// <summary>Raised after something was removed, with the bytes freed.</summary>
    public event Action<long>? Removed;

    /// <summary>The cache entry's "Clean" button: the cleaner owns those folders.</summary>
    public event Action? CleanRequested;

    public ObservableCollection<SegmentVm> Segments { get; } = [];
    public ObservableCollection<SpaceItemVm> Items { get; } = [];

    /// <summary>The list under the bar: every item, or only those of the band picked in the bar or the legend.</summary>
    public System.ComponentModel.ICollectionView ItemsView { get; }
    private SpaceSegment? _filter;
    public bool IsFiltered => _filter is not null;
    public string FilterText => _filter is { } f ? Loc.Format("disk.filter", Loc["disk.seg." + f]) : string.Empty;
    /// <summary>The picked band lists nothing: space in use that no folder accounts for.</summary>
    public bool IsFilterEmpty => _filter is not null && ItemsView.IsEmpty;

    /// <summary>A band of the bar or the legend: show only its items; the same band again shows all.</summary>
    [RelayCommand]
    private void PickSegment(SegmentVm? segment) => FilterBy(segment is null || segment.Segment == _filter ? null : segment.Segment);

    [RelayCommand]
    private void ClearFilter() => FilterBy(null);

    private void FilterBy(SpaceSegment? segment)
    {
        _filter = segment;
        foreach (var vm in Segments)
        {
            vm.IsPicked = vm.Segment == segment;
            vm.IsDimmed = segment is not null && vm.Segment != segment;
        }
        ItemsView.Refresh();
        OnPropertyChanged(nameof(IsFiltered));
        OnPropertyChanged(nameof(FilterText));
        OnPropertyChanged(nameof(IsFilterEmpty));
    }

    [ObservableProperty] private bool _isAnalyzing;
    [ObservableProperty] private bool _hasReport;
    [ObservableProperty] private string _statusText;
    [ObservableProperty] private long _total;
    [ObservableProperty] private long _free;

    public string SubtitleText => _report is null
        ? Loc["disk.subtitle.none"]
        : Loc.Format("disk.subtitle", _report.VolumeName, ByteFormatter.Format(Total - Free), ByteFormatter.Format(Total));
    public string FreeText => Loc.Format("disk.free", ByteFormatter.Format(Free));
    public string AnalyzeText => IsAnalyzing ? Loc["dash.stop"] : HasReport ? Loc["disk.reanalyze"] : Loc["disk.analyze"];
    public string AnalyzeGlyph => IsAnalyzing ? "\uE71A" : "\uEDA2";

    /// <summary>Every Safe part outside the cleaner's targets (those are cleaned from the Targets page).</summary>
    private IEnumerable<SpaceItemVm> AllSafe => Items.Where(i => !i.IsCleanable).SelectMany(i => i.SafeParts);
    public long SafeBytes => AllSafe.Sum(p => p.Bytes);
    public bool CanRemoveSafe => HasReport && !IsAnalyzing && SafeBytes > 0;
    public string SafeText => Loc.Format("disk.safe", ByteFormatter.Format(SafeBytes));

    partial void OnIsAnalyzingChanged(bool value) { OnPropertyChanged(nameof(AnalyzeText)); OnPropertyChanged(nameof(AnalyzeGlyph)); RefreshSafe(); }
    partial void OnHasReportChanged(bool value) { OnPropertyChanged(nameof(AnalyzeText)); RefreshSafe(); }

    private void RefreshSafe()
    {
        OnPropertyChanged(nameof(SafeBytes));
        OnPropertyChanged(nameof(CanRemoveSafe));
        OnPropertyChanged(nameof(SafeText));
    }

    [RelayCommand]
    private async Task RemoveSafe()
    {
        var parts = AllSafe.ToList();
        if (parts.Count == 0) return;
        var bytes = parts.Sum(p => p.Bytes);
        var ok = await _dialogs.ConfirmAsync(
            Loc.Format("disk.removeSafe.title", ByteFormatter.Format(bytes)),
            Loc.Format("disk.removeSafe.body", parts.Count),
            Loc["disk.removeSafe"],
            danger: false);
        if (!ok) return;
        foreach (var part in parts) await Delete(part);
    }
    partial void OnFreeChanged(long value) { OnPropertyChanged(nameof(FreeText)); OnPropertyChanged(nameof(SubtitleText)); }

    [RelayCommand]
    public async Task Analyze()
    {
        if (IsAnalyzing)
        {
            _cts?.Cancel();
            return;
        }

        IsAnalyzing = true;
        _cts = new CancellationTokenSource();
        SetStatus(() => Loc["disk.analyzing"]);
        var progress = new Progress<string>(path => StatusText = Loc.Format("disk.measuring", path));
        try
        {
            var scope = SpaceCatalog.Scope(SelectedDrive?.Root);
            var targets = _targets();
            var report = await Task.Run(() => _engine.AnalyzeAsync(scope, targets, progress, _cts.Token));
            Show(report);
            var seconds = report.Elapsed.TotalSeconds.ToString("0.0");
            SetStatus(() => Loc.Format("disk.analyzed", ByteFormatter.Format(report.Measured), seconds));
        }
        catch (OperationCanceledException)
        {
            SetStatus(() => Loc["dash.cancelled"]);
        }
        finally
        {
            IsAnalyzing = false;
            _cts.Dispose();
            _cts = null;
            if (_reanalyze)
            {
                _reanalyze = false;
                _ = Analyze();
            }
        }
    }

    private void Show(SpaceReport report)
    {
        _report = report;
        Total = report.Total;
        Free = report.Free;
        Items.Clear();
        foreach (var entry in report.Items) Items.Add(new SpaceItemVm(entry, report.Used, 0));
        if (LostSpace(report) is { } lost) Items.Insert(Items.TakeWhile(i => i.Bytes >= lost.Bytes).Count(), new SpaceItemVm(lost, report.Used, 0));
        UpdateSegments();
        FilterBy(_filter);
        HasReport = true;
        RefreshSafe();
        OnPropertyChanged(nameof(SubtitleText));
    }

    private void UpdateSegments()
    {
        if (_report is null) return;
        foreach (var vm in Segments) vm.Bytes = _report.Segments.GetValueOrDefault(vm.Segment);
    }

    /// <summary>
    /// On exFAT and FAT there is no journal, shadow copy or index to hold space: what is in use beyond every file
    /// (counted by whole clusters) is lost clusters, left by an interrupted copy or a drive pulled out unsafely. Only
    /// chkdsk gives them back. Null when there is none to speak of or the drive keeps space of its own (NTFS).
    /// </summary>
    private SpaceEntry? LostSpace(SpaceReport report)
    {
        var root = SelectedDrive?.Root ?? SpaceCatalog.HomeDrive;
        string format;
        try { format = new DriveInfo(root).DriveFormat; } catch { return null; }
        if (!format.Contains("FAT", StringComparison.OrdinalIgnoreCase)) return null;
        var lost = report.Used - report.Measured;
        if (lost < 1L << 30) return null;
        var letter = root.TrimEnd('\\');
        return new SpaceEntry
        {
            Id = "lost", Segment = SpaceSegment.System, Risk = SpaceRisk.Moderate, Glyph = "\uE90F", Key = "space.lost",
            Bytes = lost, Command = $"chkdsk {letter} /f /x",
        };
    }

    /// <summary>Lost space: chkdsk /f as administrator in a console window, then the drive is measured again.</summary>
    [RelayCommand]
    private async Task Repair(SpaceItemVm item)
    {
        if (item.Entry.Command is not { } command) return;
        var ok = await _dialogs.ConfirmAsync(
            Loc.Format("disk.repair.title", ByteFormatter.Format(item.Bytes)),
            Loc.Format("disk.repair.body", command.Split(' ')[1]),
            Loc["disk.repair"],
            danger: false);
        if (!ok) return;
        item.IsBusy = true;
        try
        {
            using var p = Process.Start(new ProcessStartInfo("cmd.exe", "/c " + command + " & pause") { UseShellExecute = true, Verb = "runas" });
            if (p is not null) await p.WaitForExitAsync();
        }
        catch
        {
            // the UAC prompt was declined
        }
        item.IsBusy = false;
        await Analyze();
    }

    [RelayCommand]
    private void ToggleExpand(SpaceItemVm item) => item.IsExpanded = !item.IsExpanded;

    [RelayCommand]
    private void Reveal(SpaceItemVm item)
    {
        var path = item.Entry.Path;
        try
        {
            var args = Directory.Exists(path) ? "\"" + path + "\"" : "/select,\"" + path + "\"";
            Process.Start(new ProcessStartInfo("explorer.exe", args) { UseShellExecute = true });
        }
        catch
        {
            // explorer missing or blocked; nothing sensible to do
        }
    }

    [RelayCommand]
    private void CopyCommand(SpaceItemVm item)
    {
        if (item.Entry.Command is not { } command) return;
        try
        {
            System.Windows.Clipboard.SetText(command);
            _toast("\uE8C8", Loc.Format("insight.copied", command));
        }
        catch
        {
            // clipboard can be locked by another app; nothing to do
        }
    }

    [RelayCommand]
    private void Clean() => CleanRequested?.Invoke();

    [RelayCommand]
    private void AskDelete(SpaceItemVm item)
    {
        foreach (var other in Items.SelectMany(i => i.Children.Prepend(i))) other.IsConfirming = false;
        item.IsConfirming = true;
        _confirmTimer?.Stop();
        _confirmTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(3.5) };
        _confirmTimer.Tick += (_, _) =>
        {
            _confirmTimer!.Stop();
            if (!item.IsBusy) item.IsConfirming = false;
        };
        _confirmTimer.Start();
    }

    [RelayCommand]
    private async Task Delete(SpaceItemVm item)
    {
        if (_report is null || item.IsBusy || !item.CanDelete) return;
        item.IsBusy = true;
        var recycle = _useRecycleBin();
        var freed = await Task.Run(() => _engine.Remove(item.Entry, recycle));
        item.IsBusy = false;
        item.IsConfirming = false;
        if (freed <= 0) return;

        // Take it out of its parent, its band and the totals.
        item.Entry.Bytes = Math.Max(0, item.Entry.Bytes - freed);
        item.Bytes = item.Entry.Bytes;
        var parent = Items.FirstOrDefault(i => i.Children.Contains(item));
        if (parent is not null)
        {
            parent.Entry.Bytes = Math.Max(0, parent.Entry.Bytes - freed);
            parent.Bytes = parent.Entry.Bytes;
            if (item.Bytes == 0) parent.Children.Remove(item);
            parent.Refresh();
        }
        else if (item.Bytes == 0)
        {
            Items.Remove(item);
        }
        var segment = item.Entry.Segment;
        _report.Segments[segment] = Math.Max(0, _report.Segments.GetValueOrDefault(segment) - freed);
        if (recycle)
        {
            // Still on the disk until the Recycle Bin is emptied.
            _report.Segments[SpaceSegment.System] = _report.Segments.GetValueOrDefault(SpaceSegment.System) + freed;
        }
        else
        {
            try { Free = new DriveInfo(Path.GetPathRoot(item.Entry.Path) ?? "C:\\").AvailableFreeSpace; } catch { /* keep the old figure */ }
        }
        UpdateSegments();
        RefreshSafe();
        _toast("\uE73E", Loc.Format(recycle ? "details.trashed" : "details.deleted", item.Name, ByteFormatter.Format(freed)));
        Removed?.Invoke(freed);
    }

    private void SetStatus(Func<string> status)
    {
        _status = status;
        StatusText = status();
    }
}
