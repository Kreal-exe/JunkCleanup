using System.Collections.ObjectModel;
using Avalonia.Media;
using Avalonia.Media.Immutable;
using Avalonia.Threading;
using JunkCleanup.Core;
using JunkCleanup.Localization;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;

namespace JunkCleanup.ViewModels;

/// <summary>A band of the disk bar (or a legend entry): a share of the whole disk.</summary>
public interface ISegment
{
    long Bytes { get; }
    IBrush Brush { get; }
}

public sealed partial class SegmentVm : ObservableObject, ISegment
{
    public SegmentVm(string key, IBrush brush)
    {
        Key = key;
        Brush = brush;
        LocalizationManager.Instance.LanguageChanged += (_, _) => OnPropertyChanged(nameof(Name));
    }

    public string Key { get; }
    public string Name => LocalizationManager.Instance[Key];
    public IBrush Brush { get; }
    [ObservableProperty] private long _bytes;
}

public static class SpaceColors
{
    public static Color Of(SpaceSegment segment) => segment switch
    {
        SpaceSegment.System => Color.Parse("#8E96AB"),
        SpaceSegment.Apps => Color.Parse("#34D399"),
        SpaceSegment.Caches => Color.Parse("#22D3EE"),
        SpaceSegment.Developer => Color.Parse("#A78BFA"),
        SpaceSegment.Models => Color.Parse("#F472B6"),
        SpaceSegment.VirtualMachines => Color.Parse("#F59E0B"),
        SpaceSegment.Files => Color.Parse("#60A5FA"),
        _ => Color.Parse("#FB7185"),
    };

    public static IBrush Brush(SpaceSegment segment, bool soft = false) => new ImmutableSolidColorBrush(Of(segment), soft ? 0.16 : 1);

    public static IBrush Risk(SpaceRisk risk, bool soft = false) => risk == SpaceRisk.Keep
        ? new ImmutableSolidColorBrush(Color.Parse("#8E96AB"), soft ? 0.16 : 1)
        : CategoryColors.Brush((RiskLevel)(int)risk, soft);
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
    public string PathText => Entry.Paths.Count == 0 ? string.Empty : string.Join("   ·   ", Entry.Paths.Select(Shorten));
    public bool HasPath => Entry.Paths.Count > 0;
    public string Glyph => Entry.Glyph;
    public SpaceRisk Risk => Entry.Risk;
    public string RiskText => Loc["risk." + Risk];
    public string RiskHint => Loc["risk." + Risk + ".desc"];
    public IBrush RiskBrush => SpaceColors.Risk(Risk);
    public IBrush RiskSoftBrush => SpaceColors.Risk(Risk, soft: true);
    public IBrush Brush => SpaceColors.Brush(Entry.Segment);
    public IBrush SoftBrush => SpaceColors.Brush(Entry.Segment, soft: true);
    public double Share { get; private set; }

    public bool CanDelete => Entry.CanDelete && Bytes > 0;

    /// <summary>What can go without a second thought: this item when it is Safe, else its Safe parts.</summary>
    public IEnumerable<SpaceItemVm> SafeParts => Risk == SpaceRisk.Safe && CanDelete
        ? [this]
        : Children.Where(c => c.Risk == SpaceRisk.Safe && c.CanDelete);
    public long SafeBytes => SafeParts.Sum(p => p.Bytes);
    public bool HasSafe => Children.Count > 0 && SafeBytes > 0;
    public string SafeText => Loc.Format("disk.safe", ByteFormatter.Format(SafeBytes));
    public bool HasCommand => Entry.Command is not null;
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

    private static string Shorten(string path)
    {
        var home = PathResolver.Home;
        return path == home ? "~" : path.StartsWith(home + "/", StringComparison.Ordinal) ? "~" + path[home.Length..] : path;
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
    private CancellationTokenSource? _cts;
    private SpaceReport? _report;
    private DispatcherTimer? _confirmTimer;
    private Func<string> _status;

    public DiskViewModel(Func<bool> useRecycleBin, Func<IReadOnlyList<CleanupTarget>> targets, IDialogService dialogs)
    {
        _useRecycleBin = useRecycleBin;
        _targets = targets;
        _dialogs = dialogs;
        foreach (var segment in Enum.GetValues<SpaceSegment>())
            Segments.Add(new SegmentVm("disk.seg." + segment, SpaceColors.Brush(segment)));
        _status = () => Loc["disk.notAnalyzed"];
        _statusText = _status();
        Loc.LanguageChanged += (_, _) =>
        {
            StatusText = _status();
            OnPropertyChanged(nameof(SubtitleText));
            OnPropertyChanged(nameof(AnalyzeText));
            OnPropertyChanged(nameof(FreeText));
        };
    }

    /// <summary>Raised after something was removed: (icon, message, bytes freed).</summary>
    public event Action<string, string, long>? Removed;

    /// <summary>The cache entry's "Clean" button: the cleaner owns those folders.</summary>
    public event Action? CleanRequested;

    public ObservableCollection<SegmentVm> Segments { get; } = [];
    public ObservableCollection<SpaceItemVm> Items { get; } = [];

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
    public string AnalyzeGlyph => IsAnalyzing ? "Stop" : "ChartDonut";

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
            var scope = SpaceCatalog.Scope();
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
        }
    }

    private void Show(SpaceReport report)
    {
        _report = report;
        Total = report.Total;
        Free = report.Free;
        Items.Clear();
        foreach (var entry in report.Items) Items.Add(new SpaceItemVm(entry, report.Used, 0));
        UpdateSegments();
        HasReport = true;
        RefreshSafe();
        OnPropertyChanged(nameof(SubtitleText));
    }

    private void UpdateSegments()
    {
        if (_report is null) return;
        foreach (var vm in Segments)
        {
            var segment = Enum.Parse<SpaceSegment>(vm.Key["disk.seg.".Length..]);
            vm.Bytes = _report.Segments.GetValueOrDefault(segment);
        }
    }

    [RelayCommand]
    private void ToggleExpand(SpaceItemVm item) => item.IsExpanded = !item.IsExpanded;

    [RelayCommand]
    private void Reveal(SpaceItemVm item)
    {
        var path = item.Entry.Path;
        _ = Task.Run(() =>
        {
            if (Directory.Exists(path)) Platform.Open(path);
            else Platform.Reveal(path);
        });
    }

    [RelayCommand]
    private async Task CopyCommand(SpaceItemVm item)
    {
        if (item.Entry.Command is not { } command) return;
        try
        {
            await _dialogs.CopyTextAsync(command);
            Removed?.Invoke("ContentCopy", Loc.Format("insight.copied", command), 0);
        }
        catch
        {
            // no clipboard
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
            // Still on the disk until the Trash is emptied: it moves to the Trash's row.
            _report.Segments[SpaceSegment.Other] = _report.Segments.GetValueOrDefault(SpaceSegment.Other) + freed;
            if (Items.FirstOrDefault(i => i.Entry.Id == "trash") is { } trash)
            {
                trash.Entry.Bytes += freed;
                trash.Bytes = trash.Entry.Bytes;
            }
        }
        else
        {
            var (_, total, free, _) = Platform.HomeDisk();
            if (total > 0) Free = free;
        }
        UpdateSegments();
        RefreshSafe();
        Removed?.Invoke("CheckBold", Loc.Format(recycle ? "details.trashed" : "details.deleted", item.Name, ByteFormatter.Format(freed)), freed);
    }

    private void SetStatus(Func<string> status)
    {
        _status = status;
        StatusText = status();
    }
}
