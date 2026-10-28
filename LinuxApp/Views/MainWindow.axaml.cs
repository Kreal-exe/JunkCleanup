using Avalonia;
using Avalonia.Controls;
using Avalonia.Media.Transformation;
using Avalonia.Platform.Storage;
using Avalonia.Threading;
using JunkCleanup.Controls;
using JunkCleanup.Settings;
using JunkCleanup.ViewModels;

namespace JunkCleanup.Views;

public sealed partial class MainWindow : Window, IDialogService
{
    private AppSettings? _settings;
    private DispatcherTimer? _toastTimer;

    public MainWindow() => InitializeComponent();

    public void Attach(MainViewModel vm, AppSettings settings)
    {
        _settings = settings;
        DataContext = vm;
        vm.ToastRequested += ShowToast;

        if (settings.WindowWidth >= MinWidth && settings.WindowHeight >= MinHeight)
        {
            Width = settings.WindowWidth;
            Height = settings.WindowHeight;
        }
        if (settings.WindowMaximized) WindowState = WindowState.Maximized;
    }

    protected override void OnClosing(WindowClosingEventArgs e)
    {
        base.OnClosing(e);
        if (_settings is null) return;
        _settings.WindowMaximized = WindowState == WindowState.Maximized;
        if (WindowState == WindowState.Normal)
        {
            _settings.WindowWidth = Bounds.Width;
            _settings.WindowHeight = Bounds.Height;
        }
        SettingsStore.Save(_settings);
    }

    // ─────────────────────────── IDialogService ───────────────────────────

    public Task<bool> ConfirmAsync(string title, string body, string okText, bool danger) => Confirm.ShowAsync(title, body, okText, danger);

    public async Task<string?> PickFolderAsync()
    {
        var folders = await StorageProvider.OpenFolderPickerAsync(new FolderPickerOpenOptions { AllowMultiple = false });
        return folders.Count > 0 ? folders[0].TryGetLocalPath() : null;
    }

    public async Task CopyTextAsync(string text)
    {
        if (Clipboard is { } clipboard) await clipboard.SetTextAsync(text);
    }

    // ─────────────────────────── toast ───────────────────────────

    private void ShowToast(string icon, string text)
    {
        ToastIcon.Kind = IconConverter.Parse(icon);
        ToastText.Text = text;
        Toast.Opacity = 1;
        Toast.RenderTransform = TransformOperations.Parse("translateY(0px)");

        _toastTimer?.Stop();
        _toastTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(3.2) };
        _toastTimer.Tick += (_, _) =>
        {
            _toastTimer.Stop();
            Toast.Opacity = 0;
            Toast.RenderTransform = TransformOperations.Parse("translateY(-12px)");
        };
        _toastTimer.Start();
    }
}
