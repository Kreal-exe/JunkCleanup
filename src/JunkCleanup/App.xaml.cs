using System.Windows;
using System.Windows.Threading;
using JunkCleanup.Controls;
using JunkCleanup.Localization;
using JunkCleanup.Settings;
using JunkCleanup.ViewModels;
using JunkCleanup.Views;

namespace JunkCleanup;

public partial class App : Application
{
    public static AppSettings Settings { get; private set; } = new();

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        DispatcherUnhandledException += OnUnhandledException;
        AppDomain.CurrentDomain.UnhandledException += (_, args) =>
            MessageBox.Show(args.ExceptionObject.ToString(), "JunkCleanup", MessageBoxButton.OK, MessageBoxImage.Error);

        Settings = SettingsStore.Load();
        Motion.Enabled = Settings.Animations;
        LocalizationManager.Instance.Apply(Settings.Language);
        ThemeManager.Apply(Settings.Theme);

        var window = new MainWindow();
        var vm = new MainViewModel(Settings, window);
        window.DataContext = vm;
        MainWindow = window;

        // Hidden switches used by screenshots/tests: --page <name>, --scan, --drive <letter>
        var args = e.Args;
        for (var i = 0; i < args.Length; i++)
        {
            if (args[i].Equals("--drive", StringComparison.OrdinalIgnoreCase) && i + 1 < args.Length)
                vm.Disk.SelectDrive(args[i + 1]);
            if (args[i].Equals("--page", StringComparison.OrdinalIgnoreCase) && i + 1 < args.Length &&
                Enum.TryParse<AppPage>(args[i + 1], true, out var page))
            {
                vm.CurrentPage = page;
            }
        }

        window.Show();

        if (Settings.ScanOnStartup || args.Any(a => a.Equals("--scan", StringComparison.OrdinalIgnoreCase)))
            _ = vm.ScanAsync();
    }

    private void OnUnhandledException(object sender, DispatcherUnhandledExceptionEventArgs e)
    {
        MessageBox.Show(e.Exception.ToString(), "JunkCleanup", MessageBoxButton.OK, MessageBoxImage.Error);
        e.Handled = true;
    }
}
