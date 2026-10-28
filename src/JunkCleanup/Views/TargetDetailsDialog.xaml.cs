using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using JunkCleanup.Controls;
using JunkCleanup.ViewModels;

namespace JunkCleanup.Views;

public partial class TargetDetailsDialog : UserControl
{
    public TargetDetailsDialog()
    {
        InitializeComponent();
        PreviewKeyDown += OnKeyDown;
    }

    private MainViewModel? Vm => DataContext as MainViewModel;

    public void Show()
    {
        Visibility = Visibility.Visible;
        Focus();
        if (!Motion.Enabled)
        {
            Root.Opacity = 1;
            return;
        }

        Root.Opacity = 0;
        CardScale.ScaleX = CardScale.ScaleY = 0.94;
        CardT.Y = 18;
        Root.BeginAnimation(OpacityProperty, Motion.Double(0, 1, 200));
        CardScale.BeginAnimation(ScaleTransform.ScaleXProperty, Motion.Double(0.94, 1, 420, Motion.Spring));
        CardScale.BeginAnimation(ScaleTransform.ScaleYProperty, Motion.Double(0.94, 1, 420, Motion.Spring));
        CardT.BeginAnimation(TranslateTransform.YProperty, Motion.Double(18, 0, 420, Motion.EaseOutStrong));
    }

    public void Hide()
    {
        if (!Motion.Enabled)
        {
            Visibility = Visibility.Collapsed;
            return;
        }

        var fade = Motion.Double(null, 0, 160, Motion.EaseIn);
        fade.Completed += (_, _) =>
        {
            if (Vm?.DetailsTarget is null) Visibility = Visibility.Collapsed;
        };
        Root.BeginAnimation(OpacityProperty, fade);
        CardScale.BeginAnimation(ScaleTransform.ScaleXProperty, Motion.Double(null, 0.96, 160, Motion.EaseIn));
        CardScale.BeginAnimation(ScaleTransform.ScaleYProperty, Motion.Double(null, 0.96, 160, Motion.EaseIn));
    }

    private void OnBackgroundClick(object sender, MouseButtonEventArgs e) => Vm?.CloseDetailsCommand.Execute(null);
    private void OnCardClick(object sender, MouseButtonEventArgs e) => e.Handled = true;

    private void OnKeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key != Key.Escape || Vm?.DetailsTarget is null) return;
        Vm.CloseDetailsCommand.Execute(null);
        e.Handled = true;
    }
}
