namespace JunkCleanup.ViewModels;

public interface IDialogService
{
    Task<bool> ConfirmAsync(string title, string body, string okText, bool danger);
    Task<string?> PickFolderAsync();
    Task CopyTextAsync(string text);
}
