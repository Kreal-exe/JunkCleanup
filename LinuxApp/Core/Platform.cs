using System.Diagnostics;

namespace JunkCleanup.Core;

/// <summary>Desktop integration: opening folders and links, revealing a file in the file manager, the home disk.</summary>
public static class Platform
{
    /// <summary>Opens a folder, file or URL with the desktop's default handler.</summary>
    public static void Open(string target)
    {
        if (!Run("xdg-open", target)) Run("gio", "open", target);
    }

    /// <summary>Shows the item selected in the file manager (FileManager1 over D-Bus), or opens its folder.</summary>
    public static void Reveal(string path)
    {
        var uri = new Uri(path).AbsoluteUri;
        var shown = Run("gdbus", "call", "--session", "--dest", "org.freedesktop.FileManager1",
            "--object-path", "/org/freedesktop/FileManager1", "--method", "org.freedesktop.FileManager1.ShowItems",
            $"['{uri.Replace("'", "%27")}']", "");
        if (!shown) Open(Directory.Exists(path) ? path : Path.GetDirectoryName(path) ?? path);
    }

    /// <summary>The file system holding the home folder: its mount point and sizes.</summary>
    public static (string Name, long Total, long Free, long Used) HomeDisk()
    {
        var home = PathResolver.Home;
        DriveInfo? best = null;
        foreach (var drive in DriveInfo.GetDrives())
        {
            string root;
            try
            {
                if (!drive.IsReady || drive.TotalSize <= 0) continue;
                root = drive.RootDirectory.FullName.TrimEnd('/');
            }
            catch
            {
                continue;
            }
            if (root.Length > 0 && home != root && !home.StartsWith(root + "/", StringComparison.Ordinal)) continue;
            if (best is null || root.Length > best.RootDirectory.FullName.TrimEnd('/').Length) best = drive;
        }

        if (best is null) return ("/", 0, 0, 0);
        return (best.RootDirectory.FullName, best.TotalSize, best.AvailableFreeSpace, best.TotalSize - best.TotalFreeSpace);
    }

    private static bool Run(string file, params string[] args)
    {
        try
        {
            var info = new ProcessStartInfo(file) { UseShellExecute = false, RedirectStandardOutput = true, RedirectStandardError = true };
            foreach (var arg in args) info.ArgumentList.Add(arg);
            using var process = Process.Start(info);
            if (process is null) return false;
            // gdbus answers at once; xdg-open may stay alive with the app it started, so only wait briefly.
            if (!process.WaitForExit(3000)) return true;
            return process.ExitCode == 0;
        }
        catch
        {
            return false;
        }
    }
}
