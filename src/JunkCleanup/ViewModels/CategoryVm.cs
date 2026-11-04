using System.Windows;
using System.Windows.Media;
using JunkCleanup.Core;
using JunkCleanup.Localization;
using CommunityToolkit.Mvvm.ComponentModel;

namespace JunkCleanup.ViewModels;

public sealed partial class CategoryVm : ObservableObject
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
            OnPropertyChanged(nameof(SelectedText));
        };
    }

    public TargetCategory Category { get; }
    public IReadOnlyList<TargetVm> Targets { get; }
    public string Name => Loc["cat." + Category];

    /// <summary>Shown when only part of what was found is selected (Careful targets are not ticked by the switch).</summary>
    public string SelectedText => Loc.Format("dash.selectedBytes", ByteFormatter.Format(SelectedBytes));
    public bool IsPartlySelected => SelectedBytes < Bytes;

    partial void OnSelectedBytesChanged(long value) { OnPropertyChanged(nameof(SelectedText)); OnPropertyChanged(nameof(IsPartlySelected)); }
    partial void OnBytesChanged(long value) => OnPropertyChanged(nameof(IsPartlySelected));

    public string Glyph => Category switch
    {
        TargetCategory.System => "",
        TargetCategory.Browsers => "",
        TargetCategory.Developer => "",
        TargetCategory.Apps => "",
        TargetCategory.Gaming => "",
        _ => "",
    };

    public Brush Brush => Application.Current?.TryFindResource("Brush.Cat." + Category) as Brush ?? Brushes.Gray;

    [ObservableProperty] private long _bytes;
    [ObservableProperty] private long _selectedBytes;
    [ObservableProperty] private long _fileCount;
    [ObservableProperty] private int _targetCount;
    [ObservableProperty] private int _presentCount;
    [ObservableProperty] private double _share;
    [ObservableProperty] private bool _isEnabled;

    partial void OnIsEnabledChanged(bool value)
    {
        if (_suppress) return;
        _setAll(this, value);
    }

    public void Recalc(long grandTotal)
    {
        // The Recycle Bin is shown on its own line of the dashboard, not as junk of its category.
        var present = Targets.Where(t => t.IsPresent && !t.IsRecycleBin).ToList();
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
