using System.Text;

namespace JunkCleanup.Core;

/// <summary>
/// The freedesktop.org Trash (https://specifications.freedesktop.org/trash-spec/latest/), which file managers on GNOME,
/// KDE, Xfce and the rest show and restore from. Named like the Windows Recycle Bin wrapper so the shared clean engine
/// uses either one.
/// <para>
/// An item is renamed into Trash/files and described by Trash/info/NAME.trashinfo. A rename never copies: an item on
/// another file system goes to that volume's own $topdir/.Trash/$uid or $topdir/.Trash-$uid, and if neither can be used
/// the item is left where it is and reported as not moved. Nothing is ever deleted on the way to the Trash.
/// </para>
/// </summary>
internal static class RecycleBinNative
{
    /// <summary>The home trash: $XDG_DATA_HOME/Trash.</summary>
    public static string HomeTrash => Path.Combine(PathResolver.DataHome, "Trash");

    /// <summary>Moves the given paths to the Trash. Returns how many could not be moved (0 = success).</summary>
    public static int MoveToRecycleBin(IReadOnlyList<string> paths)
    {
        var failed = 0;
        foreach (var path in paths)
            if (!MoveToTrash(path)) failed++;
        return failed;
    }

    public static bool MoveToTrash(string path)
    {
        string full;
        try
        {
            full = PathGuard.Normalize(path);
            // A dangling symlink is still an item; anything else must exist.
            if (!File.Exists(full) && !Directory.Exists(full) && new FileInfo(full).LinkTarget is null) return false;
        }
        catch
        {
            return false;
        }

        var home = HomeTrash;
        // The trash itself is never trashed into itself.
        if (full == home || PathGuard.IsInside(full, [home])) return false;

        if (EnsureTrash(home))
        {
            var result = MoveInto(home, full, full);
            if (result == 0) return true;
            if (result != Native.EXDEV) return false;
        }

        // Another file system: that volume's trash, with paths relative to its top directory.
        var top = MountPointOf(full);
        if (top is null || top == "/") return false;
        var uid = Native.UserId;
        if (uid == uint.MaxValue) return false;
        var relative = Path.GetRelativePath(top, full);

        var shared = Path.Combine(top, ".Trash");
        if (IsValidSharedTrash(shared))
        {
            var own = Path.Combine(shared, uid.ToString());
            if (EnsureTrash(own) && MoveInto(own, full, relative) == 0) return true;
        }

        var personal = Path.Combine(top, ".Trash-" + uid);
        return EnsureTrash(personal) && MoveInto(personal, full, relative) == 0;
    }

    /// <summary>Size and item count of the home trash.</summary>
    public static (long Bytes, long Items) Query()
    {
        var files = Path.Combine(HomeTrash, "files");
        if (!Directory.Exists(files)) return (0, 0);

        long bytes = 0, items = 0;
        try
        {
            var options = new EnumerationOptions { RecurseSubdirectories = true, IgnoreInaccessible = true, AttributesToSkip = FileAttributes.ReparsePoint };
            foreach (var file in new DirectoryInfo(files).EnumerateFiles("*", options))
            {
                try { bytes += file.Length; } catch { /* vanished */ }
            }
            items = Directory.EnumerateFileSystemEntries(files).LongCount();
        }
        catch
        {
            // a partial size is still informative
        }
        return (bytes, items);
    }

    /// <summary>Empties the home trash permanently. Returns false when something could not be removed.</summary>
    public static bool Empty()
    {
        var trash = HomeTrash;
        if (!Directory.Exists(trash)) return true;

        var ok = true;
        foreach (var folder in new[] { "files", "info", "expunged" })
        {
            var dir = Path.Combine(trash, folder);
            if (!Directory.Exists(dir)) continue;
            IEnumerable<string> entries;
            try { entries = Directory.EnumerateFileSystemEntries(dir).ToList(); }
            catch { ok = false; continue; }
            foreach (var entry in entries) ok &= DeleteTree(entry);
        }

        try { File.Delete(Path.Combine(trash, "directorysizes")); } catch { /* optional cache file */ }
        return ok;
    }

    // ─────────────────────────── internals ───────────────────────────

    /// <summary>Writes the .trashinfo first (claiming a free name atomically), then renames the item. 0 or an errno.</summary>
    private static int MoveInto(string trash, string full, string recordedPath)
    {
        var filesDir = Path.Combine(trash, "files");
        var infoDir = Path.Combine(trash, "info");
        var name = Path.GetFileName(full);
        if (string.IsNullOrEmpty(name)) return -1;

        var info = Encoding.UTF8.GetBytes(
            "[Trash Info]\nPath=" + EncodePath(recordedPath) + "\nDeletionDate=" + DateTime.Now.ToString("yyyy-MM-ddTHH:mm:ss") + "\n");

        for (var attempt = 1; attempt < 10_000; attempt++)
        {
            var candidate = attempt == 1 ? name : UniqueName(name, attempt);
            var infoPath = Path.Combine(infoDir, candidate + ".trashinfo");
            var target = Path.Combine(filesDir, candidate);
            if (Exists(target)) continue;

            try
            {
                using (var stream = new FileStream(infoPath, FileMode.CreateNew, FileAccess.Write))
                    stream.Write(info);
            }
            catch (IOException) when (File.Exists(infoPath))
            {
                continue; // taken by another item
            }
            catch
            {
                return -1;
            }

            var error = Native.Rename(full, target);
            if (error == 0) return 0;
            TryDelete(infoPath);
            return error;
        }

        return -1;
    }

    /// <summary>"name.2.ext" style, so a restored file keeps its extension.</summary>
    private static string UniqueName(string name, int n)
    {
        var ext = Path.GetExtension(name);
        var stem = ext.Length > 0 && ext.Length < name.Length ? name[..^ext.Length] : name;
        return ext.Length > 0 && ext.Length < name.Length ? $"{stem}.{n}{ext}" : $"{name}.{n}";
    }

    /// <summary>The trash spec stores paths URL-escaped, keeping the slashes.</summary>
    internal static string EncodePath(string path)
        => string.Join('/', path.Split('/').Select(Uri.EscapeDataString));

    private static bool Exists(string path)
        => File.Exists(path) || Directory.Exists(path) || new FileInfo(path).LinkTarget is not null;

    private static bool EnsureTrash(string trash)
    {
        try
        {
            foreach (var dir in new[] { trash, Path.Combine(trash, "files"), Path.Combine(trash, "info") })
            {
                if (Directory.Exists(dir)) continue;
                Directory.CreateDirectory(dir, UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute);
            }
            // A trash folder that is really a symlink could send items anywhere.
            return new DirectoryInfo(trash).LinkTarget is null;
        }
        catch
        {
            return false;
        }
    }

    /// <summary>$topdir/.Trash is usable only as a real, sticky directory (the spec's guard against other users).</summary>
    private static bool IsValidSharedTrash(string shared)
    {
        try
        {
            var info = new DirectoryInfo(shared);
            return info.Exists && info.LinkTarget is null && info.UnixFileMode.HasFlag(UnixFileMode.StickyBit);
        }
        catch
        {
            return false;
        }
    }

    /// <summary>The mount point holding the path, from /proc/self/mountinfo (longest matching mount wins).</summary>
    internal static string? MountPointOf(string path)
    {
        string[] lines;
        try
        {
            lines = File.ReadAllLines("/proc/self/mountinfo");
        }
        catch
        {
            return null;
        }

        string? best = null;
        foreach (var line in lines)
        {
            var fields = line.Split(' ');
            if (fields.Length < 5) continue;
            var mount = UnescapeMount(fields[4]);
            if (mount != "/" && path != mount && !path.StartsWith(mount + "/", StringComparison.Ordinal)) continue;
            if (best is null || mount.Length > best.Length) best = mount;
        }
        return best;
    }

    /// <summary>mountinfo writes spaces, tabs, newlines and backslashes as octal escapes ("\040").</summary>
    internal static string UnescapeMount(string field)
    {
        if (!field.Contains('\\')) return field;
        var bytes = new List<byte>();
        for (var i = 0; i < field.Length; i++)
        {
            if (field[i] == '\\' && i + 3 < field.Length
                && IsOctal(field[i + 1]) && IsOctal(field[i + 2]) && IsOctal(field[i + 3]))
            {
                bytes.Add((byte)((field[i + 1] - '0') * 64 + (field[i + 2] - '0') * 8 + (field[i + 3] - '0')));
                i += 3;
            }
            else
            {
                bytes.AddRange(Encoding.UTF8.GetBytes(field[i].ToString()));
            }
        }
        return Encoding.UTF8.GetString(bytes.ToArray());

        static bool IsOctal(char c) => c is >= '0' and <= '7';
    }

    /// <summary>Removes a file, a symlink (never followed) or a whole folder, making read-only folders writable first.</summary>
    internal static bool DeleteTree(string path)
    {
        try
        {
            var info = new FileInfo(path);
            if (info.LinkTarget is not null || !Directory.Exists(path))
            {
                File.Delete(path);
                return !Exists(path);
            }

            try
            {
                Directory.Delete(path, recursive: true);
                return true;
            }
            catch (UnauthorizedAccessException)
            {
                // Read-only folders (Go's module cache, extracted archives) refuse to give up their files.
                MakeWritable(path);
                Directory.Delete(path, recursive: true);
                return true;
            }
        }
        catch
        {
            return false;
        }
    }

    private static void MakeWritable(string root)
    {
        var options = new EnumerationOptions { RecurseSubdirectories = true, IgnoreInaccessible = true, AttributesToSkip = FileAttributes.ReparsePoint };
        foreach (var dir in new[] { root }.Concat(Directory.EnumerateDirectories(root, "*", options)))
        {
            try
            {
                var mode = File.GetUnixFileMode(dir);
                File.SetUnixFileMode(dir, mode | UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute);
            }
            catch
            {
                // not ours; the delete reports it
            }
        }
    }

    private static void TryDelete(string path)
    {
        try { File.Delete(path); } catch { /* best effort */ }
    }
}
