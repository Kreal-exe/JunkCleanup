using Avalonia.Media;
using Avalonia.Media.Immutable;
using JunkCleanup.Core;
using JunkCleanup.Localization;
using CommunityToolkit.Mvvm.ComponentModel;

namespace JunkCleanup.ViewModels;

public sealed partial class CategoryVm : ObservableObject, ISegment
{
    private static LocalizationManager Loc => LocalizationManager.Instance;

    private readonly Action<CategoryVm, bool> _setAll;
    private bool _suppress;

    public CategoryVm(TargetCategory category, IReadOnlyList<TargetVm> targets, Action<CategoryVm, bool> setAll)
    {
        Category = category;
        Targets = targets;
        _setAll = setAll;
        Loc.LanguageChanged += (_, _) =>
        {
            OnPropertyChanged(nameof(Name));
            OnPropertyChanged(nameof(TargetsText));
            OnPropertyChanged(nameof(FilesText));
            OnPropertyChanged(nameof(SelectedText));
        };
    }

    public TargetCategory Category { get; }
    public IReadOnlyList<TargetVm> Targets { get; }
    public string Name => Loc["cat." + Category];
    public string TargetsText => Loc.Format("dash.targetsCount", PresentCount);
    public string FilesText => Loc.Format("dash.filesCount", ByteFormatter.FormatCount(FileCount));
    /// <summary>Shown when only part of what was found is selected (Careful targets are not ticked by the switch).</summary>
    public string SelectedText => Loc.Format("dash.selectedBytes", ByteFormatter.Format(SelectedBytes));
    public bool IsPartlySelected => SelectedBytes < Bytes;

    public string Glyph => Category switch
    {
        TargetCategory.System => "Linux",
        TargetCategory.Browsers => "Web",
        TargetCategory.Developer => "CodeBraces",
        TargetCategory.Apps => "FormatListBulleted",
        TargetCategory.Gaming => "GamepadVariantOutline",
        _ => "FolderOutline",
    };

    public IBrush Brush => CategoryColors.Brush(Category);
    public IBrush SoftBrush => CategoryColors.Brush(Category, soft: true);

    [ObservableProperty] private long _bytes;
    [ObservableProperty] private long _selectedBytes;
    [ObservableProperty] private long _fileCount;
    [ObservableProperty] private int _targetCount;
    [ObservableProperty] private int _presentCount;
    [ObservableProperty] private double _share;
    [ObservableProperty] private bool _isEnabled;

    partial void OnPresentCountChanged(int value) => OnPropertyChanged(nameof(TargetsText));
    partial void OnFileCountChanged(long value) => OnPropertyChanged(nameof(FilesText));
    partial void OnSelectedBytesChanged(long value) { OnPropertyChanged(nameof(SelectedText)); OnPropertyChanged(nameof(IsPartlySelected)); }
    partial void OnBytesChanged(long value) => OnPropertyChanged(nameof(IsPartlySelected));

    partial void OnIsEnabledChanged(bool value)
    {
        if (_suppress) return;
        _setAll(this, value);
    }

    public void Recalc(long grandTotal)
    {
        var present = Targets.Where(t => t.IsPresent).ToList();
        Bytes = present.Sum(t => t.Bytes);
        SelectedBytes = present.Where(t => t.IsEnabled).Sum(t => t.Bytes);
        FileCount = present.Sum(t => (long)t.FileCount);
        TargetCount = Targets.Count;
        PresentCount = present.Count;
        Share = grandTotal > 0 ? (double)Bytes / grandTotal : 0;

        _suppress = true;
        IsEnabled = present.Any(t => t.IsEnabled);
        _suppress = false;
    }
}

/// <summary>The theme-independent category and risk palette (the same colours as the Windows and macOS apps).</summary>
public static class CategoryColors
{
    public static Color Of(TargetCategory category) => category switch
    {
        TargetCategory.System => Color.Parse("#60A5FA"),
        TargetCategory.Browsers => Color.Parse("#F59E0B"),
        TargetCategory.Developer => Color.Parse("#A78BFA"),
        TargetCategory.Apps => Color.Parse("#34D399"),
        TargetCategory.Gaming => Color.Parse("#F472B6"),
        _ => Color.Parse("#22D3EE"),
    };

    public static Color Of(RiskLevel risk) => risk switch
    {
        RiskLevel.Safe => Color.Parse("#2DBE8A"),
        RiskLevel.Moderate => Color.Parse("#E0A315"),
        _ => Color.Parse("#F05A75"),
    };

    public static IBrush Brush(TargetCategory category, bool soft = false)
        => new ImmutableSolidColorBrush(Of(category), soft ? 0.16 : 1);

    public static IBrush Brush(RiskLevel risk, bool soft = false)
        => new ImmutableSolidColorBrush(Of(risk), soft ? 0.16 : 1);
}
