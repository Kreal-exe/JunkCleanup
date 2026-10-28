using System.Collections.ObjectModel;
using JunkCleanup.Localization;
using JunkCleanup.Settings;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;

namespace JunkCleanup.ViewModels;

public sealed record LanguageOption(string Code, string Label)
{
    public override string ToString() => Label;
}

public sealed partial class SettingsViewModel : ObservableObject
{
    private static LocalizationManager Loc => LocalizationManager.Instance;

    private readonly AppSettings _settings;
    private readonly Action _save;

    public event Action? ThemeChanged;
    public event Action<string>? CustomFolderAdded;
    public event Action<string>? CustomFolderRemoved;
    public event Action? ResetRequested;

    public SettingsViewModel(AppSettings settings, Action save)
    {
        _settings = settings;
        _save = save;

        _useRecycleBin = settings.UseRecycleBin;
        _animations = settings.Animations;
        _scanOnStartup = settings.ScanOnStartup;
        _skipRecentHours = settings.SkipRecentHours;
        _theme = settings.Theme;

        RebuildLanguages();
        _selectedLanguage = Languages.FirstOrDefault(l => l.Code == settings.Language) ?? Languages[0];
        CustomFolders = new ObservableCollection<string>(settings.CustomFolders);

        CustomFolders.CollectionChanged += (_, _) => OnPropertyChanged(nameof(HasCustomFolders));

        Loc.LanguageChanged += (_, _) =>
        {
            var code = SelectedLanguage?.Code ?? "auto";
            RebuildLanguages();
            _selectedLanguage = Languages.FirstOrDefault(l => l.Code == code) ?? Languages[0];
            OnPropertyChanged(nameof(SelectedLanguage));
            OnPropertyChanged(nameof(DeleteModeLabel));
            OnPropertyChanged(nameof(DeleteModeDescription));
            OnPropertyChanged(nameof(Hours6));
            OnPropertyChanged(nameof(Hours24));
            OnPropertyChanged(nameof(Days3));
            OnPropertyChanged(nameof(Days7));
        };
    }

    public ObservableCollection<LanguageOption> Languages { get; } = [];
    public ObservableCollection<string> CustomFolders { get; }

    public bool HasCustomFolders => CustomFolders.Count > 0;

    public string DeleteModeLabel => Loc[UseRecycleBin ? "settings.deleteMode.recycle" : "settings.deleteMode.permanent"];
    public string DeleteModeDescription => Loc[UseRecycleBin ? "settings.deleteMode.recycle.desc" : "settings.deleteMode.permanent.desc"];
    public string Hours6 => Loc.Format("settings.hours", 6);
    public string Hours24 => Loc.Format("settings.hours", 24);
    public string Days3 => Loc.Format("settings.days", 3);
    public string Days7 => Loc.Format("settings.days", 7);

    [ObservableProperty] private LanguageOption? _selectedLanguage;
    [ObservableProperty] private string _theme;
    [ObservableProperty] private bool _useRecycleBin;
    [ObservableProperty] private bool _animations;
    [ObservableProperty] private bool _scanOnStartup;
    [ObservableProperty] private int _skipRecentHours;

    partial void OnSelectedLanguageChanged(LanguageOption? value)
    {
        if (value is null) return;
        _settings.Language = value.Code;
        _save();
        Loc.Apply(value.Code);
    }

    partial void OnThemeChanged(string value)
    {
        _settings.Theme = value;
        _save();
        ThemeChanged?.Invoke();
    }

    partial void OnUseRecycleBinChanged(bool value)
    {
        _settings.UseRecycleBin = value;
        _save();
        OnPropertyChanged(nameof(DeleteModeLabel));
        OnPropertyChanged(nameof(DeleteModeDescription));
    }

    partial void OnAnimationsChanged(bool value)
    {
        _settings.Animations = value;
        Controls.Motion.Enabled = value;
        _save();
    }

    partial void OnScanOnStartupChanged(bool value)
    {
        _settings.ScanOnStartup = value;
        _save();
    }

    partial void OnSkipRecentHoursChanged(int value)
    {
        _settings.SkipRecentHours = value;
        _save();
    }

    [RelayCommand]
    private void SetTheme(string theme) => Theme = theme;

    [RelayCommand]
    private void SetSkipHours(string hours)
    {
        if (int.TryParse(hours, out var h)) SkipRecentHours = h;
    }

    [RelayCommand]
    private void RemoveCustomFolder(string folder)
    {
        if (!CustomFolders.Remove(folder)) return;
        _settings.CustomFolders.Remove(folder);
        _save();
        CustomFolderRemoved?.Invoke(folder);
    }

    public bool TryAddCustomFolder(string folder)
    {
        var normalized = Core.PathGuard.Normalize(folder);
        // "$" and wildcards mean something in target paths; such a folder would not be scanned as written.
        if (normalized.IndexOfAny(['$', '*', '?']) >= 0) return false;
        if (!Core.PathGuard.IsAllowedRoot(normalized)) return false;
        if (CustomFolders.Any(f => f.Equals(normalized, StringComparison.Ordinal))) return true;

        CustomFolders.Add(normalized);
        _settings.CustomFolders.Add(normalized);
        _save();
        CustomFolderAdded?.Invoke(normalized);
        return true;
    }

    [RelayCommand]
    private void Reset() => ResetRequested?.Invoke();

    private void RebuildLanguages()
    {
        Languages.Clear();
        var detected = LocalizationManager.Languages.First(l => l.Code == LocalizationManager.DetectSystemLanguage());
        Languages.Add(new LanguageOption("auto", Loc.Format("settings.language.auto", detected.NativeName)));
        foreach (var l in LocalizationManager.Languages)
            Languages.Add(new LanguageOption(l.Code, l.NativeName));
    }
}
