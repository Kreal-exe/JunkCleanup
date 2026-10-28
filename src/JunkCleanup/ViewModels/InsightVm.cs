using JunkCleanup.Core;
using JunkCleanup.Localization;
using CommunityToolkit.Mvvm.ComponentModel;

namespace JunkCleanup.ViewModels;

public enum InsightAction { None, CopyCommand, OpenUrl }

/// <summary>A non-destructive observation about the disk (hibernation file, Windows.old …) with an optional hint action.</summary>
public sealed partial class InsightVm : ObservableObject
{
    private static LocalizationManager Loc => LocalizationManager.Instance;

    public InsightVm(string id, string glyph, long bytes, InsightAction action, string? payload)
    {
        Id = id;
        Glyph = glyph;
        Bytes = bytes;
        Action = action;
        Payload = payload;
        Loc.LanguageChanged += (_, _) =>
        {
            OnPropertyChanged(nameof(Title));
            OnPropertyChanged(nameof(Detail));
            OnPropertyChanged(nameof(ActionText));
        };
    }

    public string Id { get; }
    public string Glyph { get; }
    public long Bytes { get; }
    public InsightAction Action { get; }
    public string? Payload { get; }

    public string Title => Loc[$"insight.{Id}.title"];
    public string Detail => Loc.Format($"insight.{Id}.detail", ByteFormatter.Format(Bytes));
    public string ActionText => Action switch
    {
        InsightAction.CopyCommand => Loc["insight.copyCommand"],
        InsightAction.OpenUrl => Loc["insight.open"],
        _ => string.Empty,
    };
    public bool HasAction => Action != InsightAction.None;
    public string ActionGlyph => Action == InsightAction.CopyCommand ? "\uE8C8" : "\uE8A7";

    [ObservableProperty] private bool _copied;
}

public static class InsightScanner
{
    /// <summary>Cheap checks only; nothing here enumerates large trees except Windows.old (bounded by a timeout).</summary>
    public static List<InsightVm> Scan()
    {
        var list = new List<InsightVm>();
        var systemRoot = Path.GetPathRoot(Environment.GetFolderPath(Environment.SpecialFolder.Windows)) ?? "C:\\";

        var hiber = FileSize(Path.Combine(systemRoot, "hiberfil.sys"));
        if (hiber > 0)
            list.Add(new InsightVm("hiberfil", "\uE708", hiber, InsightAction.CopyCommand, "powercfg /h off"));

        var pagefile = FileSize(Path.Combine(systemRoot, "pagefile.sys"));
        if (pagefile > 0)
            list.Add(new InsightVm("pagefile", "\uE964", pagefile, InsightAction.OpenUrl, "ms-settings:about"));

        var windowsOld = Path.Combine(systemRoot, "Windows.old");
        if (Directory.Exists(windowsOld))
        {
            var size = DirectorySize(windowsOld, TimeSpan.FromSeconds(3));
            list.Add(new InsightVm("windowsold", "\uE7B8", size, InsightAction.OpenUrl, "ms-settings:storagesense"));
        }

        var (binBytes, _) = RecycleBinNative.Query();
        if (binBytes > 256L * 1024 * 1024)
            list.Add(new InsightVm("recyclebin", "\uE74D", binBytes, InsightAction.None, null));

        return list;
    }

    private static long FileSize(string path)
    {
        try
        {
            var info = new FileInfo(path);
            return info.Exists ? info.Length : 0;
        }
        catch
        {
            return 0;
        }
    }

    private static long DirectorySize(string path, TimeSpan budget)
    {
        long total = 0;
        var started = DateTime.UtcNow;
        try
        {
            foreach (var file in new DirectoryInfo(path).EnumerateFiles("*", new EnumerationOptions
                     {
                         RecurseSubdirectories = true,
                         IgnoreInaccessible = true,
                         AttributesToSkip = FileAttributes.ReparsePoint,
                     }))
            {
                total += file.Length;
                if (DateTime.UtcNow - started > budget) break;
            }
        }
        catch
        {
            // partial size is still informative
        }

        return total;
    }
}
