using System.Windows;
using System.Windows.Controls;

namespace JunkCleanup.Controls;

/// <summary>Reveals its child by animating its height and opacity between 0 and the natural size.</summary>
public sealed class Collapsible : Decorator
{
    public static readonly DependencyProperty IsOpenProperty = DependencyProperty.Register(
        nameof(IsOpen), typeof(bool), typeof(Collapsible), new PropertyMetadata(false, OnIsOpenChanged));

    public static readonly DependencyProperty ProgressProperty = DependencyProperty.Register(
        nameof(Progress), typeof(double), typeof(Collapsible),
        new FrameworkPropertyMetadata(0.0, FrameworkPropertyMetadataOptions.AffectsMeasure, OnProgressChanged));

    public Collapsible() => ClipToBounds = true;

    public bool IsOpen { get => (bool)GetValue(IsOpenProperty); set => SetValue(IsOpenProperty, value); }
    public double Progress { get => (double)GetValue(ProgressProperty); set => SetValue(ProgressProperty, value); }

    private static void OnIsOpenChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        var c = (Collapsible)d;
        var to = (bool)e.NewValue ? 1.0 : 0.0;

        if (!Motion.Enabled || !c.IsLoaded)
        {
            c.BeginAnimation(ProgressProperty, null);
            c.Progress = to;
            return;
        }

        c.BeginAnimation(ProgressProperty, Motion.Double(null, to, to > 0 ? 420 : 260, to > 0 ? Motion.EaseOutStrong : Motion.EaseIn));
    }

    private static void OnProgressChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        var c = (Collapsible)d;
        if (c.Child is null) return;
        var p = (double)e.NewValue;
        c.Child.Opacity = p;
        c.Child.IsHitTestVisible = p > 0.95;
    }

    protected override Size MeasureOverride(Size constraint)
    {
        if (Child is null) return new Size(0, 0);
        var p = Math.Clamp(Progress, 0, 1);
        if (p <= 0) return new Size(0, 0);

        Child.Measure(new Size(constraint.Width, double.PositiveInfinity));
        return new Size(Child.DesiredSize.Width, Child.DesiredSize.Height * p);
    }

    protected override Size ArrangeOverride(Size arrangeSize)
    {
        if (Child is null) return arrangeSize;
        var p = Math.Clamp(Progress, 0, 1);
        var fullHeight = Child.DesiredSize.Height;
        // Slide the content up slightly as it reveals so it reads as unfolding, not just a clip.
        var offset = (1 - p) * -12;
        Child.Arrange(new Rect(0, offset, arrangeSize.Width, fullHeight));
        return arrangeSize;
    }
}
