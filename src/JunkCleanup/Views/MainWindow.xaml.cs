using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;
using JunkCleanup.Controls;
using JunkCleanup.ViewModels;
using Microsoft.Win32;

namespace JunkCleanup.Views;

public partial class MainWindow : Window, IDialogService
{
    private readonly DashboardView _dashboard = new();
    private readonly TargetsView _targets = new();
    private readonly DiskView _disk = new();
    private readonly SettingsView _settings = new();
    private readonly AboutView _about = new();

    private MainViewModel? _vm;
    private bool _navigating;
    private AppPage _lastPage = AppPage.Dashboard;

    public MainWindow()
    {
        InitializeComponent();
        DataContextChanged += OnDataContextChanged;
        SourceInitialized += (_, _) =>
        {
            WindowBackdrop.HideSystemCaptionButtons(this);
            ApplyBackdrop();
        };
        StateChanged += (_, _) => UpdateMaximizedLayout();
        Loaded += OnLoaded;
        Closing += OnClosing;
        ThemeManager.Changed += ApplyBackdrop;
    }

    private void OnDataContextChanged(object sender, DependencyPropertyChangedEventArgs e)
    {
        if (_vm is not null)
        {
            _vm.PropertyChanged -= OnVmPropertyChanged;
            _vm.Settings.ThemeChanged -= OnThemeChanged;
            _vm.Settings.BackdropChanged -= ApplyBackdrop;
        }

        _vm = e.NewValue as MainViewModel;
        if (_vm is null) return;

        _vm.PropertyChanged += OnVmPropertyChanged;
        _disk.DataContext = _vm.Disk;
        _vm.Settings.ThemeChanged += OnThemeChanged;
        _vm.Settings.BackdropChanged += ApplyBackdrop;
        _vm.ToastRequested += ShowToast;

        RestoreWindowSize();
        ShowPage(_vm.CurrentPage);
    }

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        StartAmbientAnimation();
        UpdateMaximizedLayout();
        MoveNavIndicator(animate: false);

        if (Motion.Enabled)
        {
            Root.Opacity = 0;
            RootScale.ScaleX = RootScale.ScaleY = 0.985;
            Root.BeginAnimation(OpacityProperty, Motion.Double(0, 1, 380));
            RootScale.BeginAnimation(ScaleTransform.ScaleXProperty, Motion.Double(0.985, 1, 650, Motion.EaseOutStrong));
            RootScale.BeginAnimation(ScaleTransform.ScaleYProperty, Motion.Double(0.985, 1, 650, Motion.EaseOutStrong));
        }
    }

    private void MoveNavIndicator(bool animate)
    {
        var radio = NavDashboard.IsChecked == true ? NavDashboard
            : NavTargets.IsChecked == true ? NavTargets
            : NavDisk.IsChecked == true ? NavDisk
            : NavSettings.IsChecked == true ? NavSettings
            : NavAbout;

        if (!radio.IsLoaded) return;
        var y = radio.TranslatePoint(new Point(0, 0), NavGrid).Y;

        if (!animate || !Motion.Enabled)
        {
            NavIndicatorT.BeginAnimation(TranslateTransform.YProperty, null);
            NavIndicatorT.Y = y;
            return;
        }

        NavIndicatorT.BeginAnimation(TranslateTransform.YProperty, Motion.Double(null, y, 420, Motion.Spring));
    }

    private System.Windows.Threading.DispatcherTimer? _toastTimer;

    private void ShowToast(string glyph, string text)
    {
        ToastGlyph.Text = glyph;
        ToastText.Text = text;
        Toast.Visibility = Visibility.Visible;

        if (Motion.Enabled)
        {
            Toast.BeginAnimation(OpacityProperty, Motion.Double(0, 1, 220));
            ToastT.BeginAnimation(TranslateTransform.YProperty, Motion.Double(-16, 0, 480, Motion.Spring));
        }
        else
        {
            Toast.Opacity = 1;
        }

        _toastTimer?.Stop();
        _toastTimer = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromSeconds(3.2) };
        _toastTimer.Tick += (_, _) =>
        {
            _toastTimer!.Stop();
            var fade = Motion.Double(null, 0, 240, Motion.EaseIn);
            fade.Completed += (_, _) => Toast.Visibility = Visibility.Collapsed;
            Toast.BeginAnimation(OpacityProperty, fade);
            ToastT.BeginAnimation(TranslateTransform.YProperty, Motion.Double(null, -10, 240, Motion.EaseIn));
        };
        _toastTimer.Start();
    }

    private void OnVmPropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (_vm is null) return;
        switch (e.PropertyName)
        {
            case nameof(MainViewModel.CurrentPage):
                ShowPage(_vm.CurrentPage);
                break;
            case nameof(MainViewModel.IsCleanOverlayVisible):
                if (_vm.IsCleanOverlayVisible) CleanOverlay.Show();
                else CleanOverlay.Hide();
                break;
            case nameof(MainViewModel.DetailsTarget):
                if (_vm.DetailsTarget is not null) Details.Show();
                else Details.Hide();
                break;
            case nameof(MainViewModel.CleanDone):
                if (_vm.CleanDone && _vm.CleanFreed > 0) CleanOverlay.Celebrate();
                break;
        }
    }

    // ───────────── navigation ─────────────

    private void ShowPage(AppPage page)
    {
        _navigating = true;
        var (view, radio) = page switch
        {
            AppPage.Targets => ((UIElement)_targets, NavTargets),
            AppPage.Disk => (_disk, NavDisk),
            AppPage.Settings => (_settings, NavSettings),
            AppPage.About => (_about, NavAbout),
            _ => (_dashboard, NavDashboard),
        };
        radio.IsChecked = true;
        _navigating = false;

        var forward = (int)page >= (int)_lastPage;
        _lastPage = page;
        Pages.Navigate(view, forward);
        MoveNavIndicator(animate: true);
    }

    private void OnNavChecked(object sender, RoutedEventArgs e)
    {
        if (_navigating || _vm is null) return;
        _vm.CurrentPage = ReferenceEquals(sender, NavTargets) ? AppPage.Targets
            : ReferenceEquals(sender, NavDisk) ? AppPage.Disk
            : ReferenceEquals(sender, NavSettings) ? AppPage.Settings
            : ReferenceEquals(sender, NavAbout) ? AppPage.About
            : AppPage.Dashboard;
    }

    // ───────────── chrome ─────────────

    private void OnMinimize(object sender, RoutedEventArgs e) => WindowState = WindowState.Minimized;

    private void OnMaximize(object sender, RoutedEventArgs e)
        => WindowState = WindowState == WindowState.Maximized ? WindowState.Normal : WindowState.Maximized;

    private void OnClose(object sender, RoutedEventArgs e) => Close();

    private void UpdateMaximizedLayout()
    {
        // With a custom chrome a maximized window overshoots the screen by the resize border.
        Root.Margin = WindowState == WindowState.Maximized ? new Thickness(7) : new Thickness(0);
        MaxButton.Content = WindowState == WindowState.Maximized ? "" : "";
    }

    private void OnThemeChanged()
    {
        ThemeManager.Apply(App.Settings.Theme);
        ApplyBackdrop();
        MoveNavIndicator(animate: false);
    }

    private void ApplyBackdrop()
    {
        var mica = WindowBackdrop.Apply(this, ThemeManager.IsDark, App.Settings.Backdrop);
        Root.Background = (Brush)FindResource(mica ? "Brush.BgTranslucent" : "Brush.Bg");
    }

    private void StartAmbientAnimation()
    {
        if (!Motion.Enabled) return;
        Drift(Blob1T, 70, 40, 26);
        Drift(Blob2T, -60, 50, 31);
        Drift(Blob3T, 40, -60, 37);
    }

    private static void Drift(System.Windows.Media.TranslateTransform t, double dx, double dy, int seconds)
    {
        var x = new DoubleAnimation(0, dx, TimeSpan.FromSeconds(seconds)) { AutoReverse = true, RepeatBehavior = RepeatBehavior.Forever, EasingFunction = new SineEase { EasingMode = EasingMode.EaseInOut } };
        var y = new DoubleAnimation(0, dy, TimeSpan.FromSeconds(seconds * 1.3)) { AutoReverse = true, RepeatBehavior = RepeatBehavior.Forever, EasingFunction = new SineEase { EasingMode = EasingMode.EaseInOut } };
        t.BeginAnimation(System.Windows.Media.TranslateTransform.XProperty, x);
        t.BeginAnimation(System.Windows.Media.TranslateTransform.YProperty, y);
    }

    // ───────────── window size persistence ─────────────

    private void RestoreWindowSize()
    {
        var s = App.Settings;
        if (s.WindowWidth >= MinWidth && s.WindowHeight >= MinHeight)
        {
            Width = s.WindowWidth;
            Height = s.WindowHeight;
        }

        // Never exceed the work area (a 1240×800 default is taller than a 1080p screen at 150 % scaling)
        // and centre inside it, so the custom title bar can never start off-screen.
        var area = SystemParameters.WorkArea;
        Width = Math.Max(MinWidth, Math.Min(Width, area.Width - 16));
        Height = Math.Max(Math.Min(MinHeight, area.Height - 16), Math.Min(Height, area.Height - 16));
        Left = area.Left + Math.Max(0, (area.Width - Width) / 2);
        Top = area.Top + Math.Max(0, (area.Height - Height) / 2);

        if (s.WindowMaximized) WindowState = WindowState.Maximized;
    }

    private void OnClosing(object? sender, CancelEventArgs e)
    {
        var s = App.Settings;
        s.WindowMaximized = WindowState == WindowState.Maximized;
        if (WindowState == WindowState.Normal)
        {
            s.WindowWidth = Width;
            s.WindowHeight = Height;
        }
        Settings.SettingsStore.Save(s);
    }

    // ───────────── IDialogService ─────────────

    public Task<bool> ConfirmAsync(string title, string body, string okText, bool danger)
        => Confirm.ShowAsync(title, body, okText, danger);

    public string? PickFolder()
    {
        var dialog = new OpenFolderDialog { Multiselect = false };
        return dialog.ShowDialog(this) == true ? dialog.FolderName : null;
    }
}
