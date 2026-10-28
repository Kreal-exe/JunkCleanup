using Avalonia;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Markup.Xaml;
using JunkCleanup.Controls;
using JunkCleanup.Localization;
using JunkCleanup.Settings;
using JunkCleanup.ViewModels;
using JunkCleanup.Views;

namespace JunkCleanup;

public sealed class App : Application
{
    public override void Initialize() => AvaloniaXamlLoader.Load(this);

    public override void OnFrameworkInitializationCompleted()
    {
        if (ApplicationLifetime is IClassicDesktopStyleApplicationLifetime desktop)
        {
            var settings = SettingsStore.Load();
            LocalizationManager.Instance.Apply(settings.Language);
            Motion.Enabled = settings.Animations;
            ThemeManager.Attach(this);
            ThemeManager.Apply(settings.Theme);

            var window = new MainWindow();
            var vm = new MainViewModel(settings, window);
            vm.Settings.ThemeChanged += () => ThemeManager.Apply(vm.Settings.Theme);
            window.Attach(vm, settings);
            desktop.MainWindow = window;

            if (settings.ScanOnStartup) _ = vm.ScanAsync();
        }

        base.OnFrameworkInitializationCompleted();
    }
}
