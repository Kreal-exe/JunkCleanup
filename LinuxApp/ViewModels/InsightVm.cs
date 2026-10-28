using JunkCleanup.Core;
using JunkCleanup.Localization;
using CommunityToolkit.Mvvm.ComponentModel;

namespace JunkCleanup.ViewModels;

public enum InsightAction { None, CopyCommand, OpenUrl }

/// <summary>A non-destructive observation about the disk (the system journal, package caches…) with an optional hint.</summary>
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
    public string Detail => Loc.Format($"insight.{Id}.detail", ByteFormatter.Format(Bytes), Payload);
    public string ActionText => Action switch
    {
        InsightAction.CopyCommand => Loc["insight.copyCommand"],
        InsightAction.OpenUrl => Loc["insight.open"],
        _ => string.Empty,
    };
    public bool HasAction => Action != InsightAction.None;
    public string ActionGlyph => Action == InsightAction.CopyCommand ? "ContentCopy" : "OpenInNew";

    [ObservableProperty] private bool _copied;
}

public static class InsightScanner
{
    private const long Threshold = 256L * 1024 * 1024;

    /// <summary>Cheap checks only: folder sizes are bounded by a time budget.</summary>
    public static List<InsightVm> Scan()
    {
        var list = new List<InsightVm>();

        // The systemd journal belongs to root; journalctl trims it.
        var journal = DirectorySize("/var/log/journal", TimeSpan.FromSeconds(2));
        if (journal > Threshold)
            list.Add(new InsightVm("journal", "TextLong", journal, InsightAction.CopyCommand, "sudo journalctl --vacuum-size=200M"));

        // Downloaded packages the package manager keeps after installing them.
        foreach (var (folder, command) in new[]
                 {
                     ("/var/cache/apt/archives", "sudo apt clean"),
                     ("/var/cache/pacman/pkg", "sudo pacman -Sc"),
                     ("/var/cache/dnf", "sudo dnf clean packages"),
                     ("/var/cache/zypp/packages", "sudo zypper clean --all"),
                 })
        {
            var size = DirectorySize(folder, TimeSpan.FromSeconds(2));
            if (size > Threshold)
            {
                list.Add(new InsightVm("pkgcache", "PackageVariantClosed", size, InsightAction.CopyCommand, command));
                break;
            }
        }

        var (trashBytes, _) = RecycleBinNative.Query();
        if (trashBytes > Threshold)
            list.Add(new InsightVm("trash", "TrashCanOutline", trashBytes, InsightAction.None, null));

        return list;
    }

    private static long DirectorySize(string path, TimeSpan budget)
    {
        long total = 0;
        var started = DateTime.UtcNow;
        try
        {
            if (!Directory.Exists(path)) return 0;
            foreach (var file in new DirectoryInfo(path).EnumerateFiles("*", new EnumerationOptions
                     {
                         RecurseSubdirectories = true,
                         IgnoreInaccessible = true,
                         AttributesToSkip = FileAttributes.ReparsePoint,
                     }))
            {
                try { total += file.Length; } catch { /* vanished */ }
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
