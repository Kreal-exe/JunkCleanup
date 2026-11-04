using System.Collections.ObjectModel;
using System.Windows.Media;
using JunkCleanup.Core;
using JunkCleanup.Localization;
using CommunityToolkit.Mvvm.ComponentModel;

namespace JunkCleanup.ViewModels;

public enum TargetState { Idle, Scanning, Done, Denied, Error }

public sealed partial class EntryVm : ObservableObject
{
    // What an entry most likely is, by extension: glyph and colour for its tile.
    private static readonly (string[] Extensions, string Glyph, Color Color)[] Kinds =
    [
        (["safetensors", "gguf", "ggml", "bin", "pt", "pth", "onnx", "ckpt", "h5", "tflite", "npz"], "\uE9D2", Color.FromRgb(0xA7, 0x8B, 0xFA)),
        (["zip", "tar", "gz", "tgz", "xz", "zst", "7z", "rar", "msi", "cab", "whl", "jar", "nupkg", "crate", "exe"], "\uE7B8", Color.FromRgb(0xF5, 0x9E, 0x0B)),
        (["png", "jpg", "jpeg", "gif", "webp", "heic", "svg", "tiff", "bmp", "ico"], "\uE91B", Color.FromRgb(0x34, 0xD3, 0x99)),
        (["mp4", "mov", "mkv", "webm", "avi", "m4v"], "\uE714", Color.FromRgb(0xF4, 0x72, 0xB6)),
        (["mp3", "wav", "m4a", "flac", "ogg", "aac"], "\uE8D6", Color.FromRgb(0x22, 0xD3, 0xEE)),
        (["js", "ts", "py", "pyc", "json", "map", "wasm", "dll", "node", "pdb", "class", "obj", "lib"], "\uE943", Color.FromRgb(0x60, 0xA5, 0xFA)),
        (["db", "sqlite", "sqlite3", "ldb", "idx", "pack", "dat"], "\uF158", Color.FromRgb(0xFB, 0xBF, 0x24)),
        (["log", "txt", "md", "csv", "xml", "etl"], "\uE8A5", Color.FromRgb(0x8E, 0x96, 0xAB)),
    ];

    public EntryVm(EntrySummary summary, long parentBytes)
    {
        Summary = summary;
        Path = summary.Path;
        Name = summary.Name;
        IsDirectory = summary.IsDirectory;
        Bytes = summary.Bytes;
        Files = summary.Files;
        Share = parentBytes > 0 ? (double)summary.Bytes / parentBytes : 0;

        var (glyph, color) = Look(summary);
        Glyph = glyph;
        KindBrush = Frozen(color, 1);
        KindSoftBrush = Frozen(color, 0.16);
    }

    public EntrySummary Summary { get; }
    public string Path { get; }
    public string Name { get; }
    public bool IsDirectory { get; }
    public long Bytes { get; }
    public int Files { get; }
    public double Share { get; }
    public string Glyph { get; }
    public Brush KindBrush { get; }
    public Brush KindSoftBrush { get; }

    /// <summary>The first click on delete asks; the second one deletes.</summary>
    [ObservableProperty] private bool _isConfirming;
    [ObservableProperty] private bool _isBusy;

    private static (string Glyph, Color Color) Look(EntrySummary e)
    {
        var name = e.Name.ToLowerInvariant();
        if (e.IsDirectory)
        {
            var model = name.StartsWith("models--") || name.StartsWith("datasets--") || name.StartsWith("spaces--");
            return model ? ("\uE9D2", Color.FromRgb(0xA7, 0x8B, 0xFA)) : ("\uE8B7", Color.FromRgb(0x7C, 0x6C, 0xFF));
        }
        var ext = System.IO.Path.GetExtension(name).TrimStart('.');
        foreach (var (extensions, glyph, color) in Kinds)
            if (extensions.Contains(ext)) return (glyph, color);
        return ("\uE8A5", Color.FromRgb(0x8E, 0x96, 0xAB));
    }

    private static Brush Frozen(Color color, double opacity)
    {
        var brush = new SolidColorBrush(color) { Opacity = opacity };
        brush.Freeze();
        return brush;
    }
}

public sealed partial class TargetVm : ObservableObject
{
    private static LocalizationManager Loc => LocalizationManager.Instance;

    private readonly Action<TargetVm> _onSelectionChanged;

    public TargetVm(CleanupTarget target, bool enabled, Action<TargetVm> onSelectionChanged)
    {
        Target = target;
        _onSelectionChanged = onSelectionChanged;
        Roots = target.Kind == TargetKind.Files ? target.ResolveRoots() : [];
        IsPresent = target.Kind == TargetKind.RecycleBin || Roots.Count > 0;
        _isEnabled = enabled && IsPresent;

        Loc.LanguageChanged += OnLanguageChanged;
    }

    public CleanupTarget Target { get; }
    public string Id => Target.Id;
    public TargetCategory Category => Target.Category;
    public string Glyph => Target.Glyph;
    public RiskLevel Risk => Target.Risk;
    public bool RequiresAdmin => Target.RequiresAdmin;
    public bool ShowAdminBadge => Target.RequiresAdmin && !Elevation.IsElevated;
    public bool IsCustom => Target.Category == TargetCategory.Custom;
    public bool IsPresent { get; }
    public bool IsRecycleBin => Target.Kind == TargetKind.RecycleBin;

    public string Name => Target.DisplayName ?? Loc[Target.NameKey];
    public string Description => IsCustom ? Loc["target.custom.desc"] : Loc[Target.DescriptionKey];
    public string RiskText => Loc["risk." + Risk];
    public string RiskHint => Loc["risk." + Risk + ".desc"];

    public IReadOnlyList<string> Roots { get; private set; }
    public string RootsText => Roots.Count == 0 ? (IsRecycleBin ? string.Empty : Loc["targets.notPresent"]) : string.Join("   ·   ", Roots);
    public bool HasRoots => Roots.Count > 0;

    [ObservableProperty] private bool _isEnabled;
    [ObservableProperty] private long _bytes;
    [ObservableProperty] private int _fileCount;
    [ObservableProperty] private TargetState _state;
    [ObservableProperty] private string? _error;
    [ObservableProperty] private bool _isExpanded;
    [ObservableProperty] private double _share;

    public ObservableCollection<EntryVm> TopEntries { get; } = [];
    public TargetScanResult? LastResult { get; private set; }

    public bool IsScanning => State == TargetState.Scanning;
    public bool IsDenied => State == TargetState.Denied;
    public bool HasEntries => TopEntries.Count > 0;
    public bool HasBytes => Bytes > 0;

    public string StatusText => State switch
    {
        TargetState.Scanning => Loc["targets.scanning"],
        TargetState.Denied => Loc["targets.needsAdmin"],
        TargetState.Error => Loc.Format("targets.error", Error),
        TargetState.Done => Bytes == 0 ? Loc["targets.empty"] : string.Empty,
        _ => IsPresent ? Loc["targets.notScanned"] : Loc["targets.notPresent"],
    };

    partial void OnIsEnabledChanged(bool value) => _onSelectionChanged(this);

    partial void OnStateChanged(TargetState value)
    {
        OnPropertyChanged(nameof(StatusText));
        OnPropertyChanged(nameof(IsScanning));
        OnPropertyChanged(nameof(IsDenied));
    }

    partial void OnBytesChanged(long value)
    {
        OnPropertyChanged(nameof(HasBytes));
        OnPropertyChanged(nameof(StatusText));
    }

    public void ResetForScan()
    {
        if (!IsPresent) return;
        State = TargetState.Scanning;
        Bytes = 0;
        FileCount = 0;
        Error = null;
        TopEntries.Clear();
        OnPropertyChanged(nameof(HasEntries));
    }

    public void Apply(TargetScanResult result)
    {
        HasLeftovers = false;
        LastResult = result;
        Roots = result.Target.Kind == TargetKind.Files ? result.Roots : Roots;
        Bytes = result.TotalBytes;
        FileCount = result.FileCount;
        Error = result.Error;

        State = result.AccessDenied && result.TotalBytes == 0 ? TargetState.Denied
            : result.Error is not null && result.TotalBytes == 0 ? TargetState.Error
            : TargetState.Done;

        TopEntries.Clear();
        foreach (var entry in result.TopEntries.Take(100))
            TopEntries.Add(new EntryVm(entry, result.TotalBytes));

        OnPropertyChanged(nameof(RootsText));
        OnPropertyChanged(nameof(HasRoots));
        OnPropertyChanged(nameof(HasEntries));
    }

    /// <summary>One entry was removed from the details sheet.</summary>
    public void ApplyEntryRemoval(EntryVm entry, TargetCleanResult removal)
    {
        Bytes = removal.BytesRemaining;
        FileCount = removal.FilesRemaining;
        TopEntries.Remove(entry);
        OnPropertyChanged(nameof(HasEntries));
    }

    /// <summary>A clean left files behind (in use, or needing administrator): only a new scan offers them again.</summary>
    public bool HasLeftovers { get; private set; }

    public void ApplyClean(TargetCleanResult clean)
    {
        HasLeftovers = clean.BytesRemaining > 0;
        Bytes = clean.BytesRemaining;
        FileCount = clean.FilesRemaining;
        TopEntries.Clear();
        OnPropertyChanged(nameof(HasEntries));
        if (clean.Error is not null)
        {
            Error = clean.Error;
            State = TargetState.Error;
        }
    }

    private void OnLanguageChanged(object? sender, EventArgs e)
    {
        OnPropertyChanged(nameof(Name));
        OnPropertyChanged(nameof(Description));
        OnPropertyChanged(nameof(RiskText));
        OnPropertyChanged(nameof(RiskHint));
        OnPropertyChanged(nameof(StatusText));
        OnPropertyChanged(nameof(RootsText));
    }
}
