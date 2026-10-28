using Avalonia.Controls;
using Avalonia.Input;
using JunkCleanup.ViewModels;

namespace JunkCleanup.Views;

public sealed partial class DetailsSheet : UserControl
{
    public DetailsSheet()
    {
        InitializeComponent();
        // A click on the dimmed background closes the sheet; clicks on the card stay with it.
        Backdrop.PointerPressed += (_, e) =>
        {
            if (e.Source == Backdrop && DataContext is MainViewModel vm) vm.CloseDetailsCommand.Execute(null);
        };
        Card.PointerPressed += (_, e) => e.Handled = true;
    }
}
