namespace JunkCleanup.Core;

/// <summary>
/// Last line of defence: refuses to treat critical folders as cleanable roots and refuses to delete
/// anything that does not live underneath one of the roots that were scanned.
/// </summary>
public static class PathGuard
{
    private static readonly Lazy<HashSet<string>> Protected = new(BuildProtectedSet);

    /// <summary>How paths compare on this platform: Windows paths ignore case. (The Linux app has its own PathGuard.)</summary>
    public static StringComparison Comparison => StringComparison.OrdinalIgnoreCase;
    public static StringComparer Comparer => StringComparer.OrdinalIgnoreCase;

    public static bool IsAllowedRoot(string root)
    {
        if (string.IsNullOrWhiteSpace(root)) return false;

        string full;
        try
        {
            full = Normalize(root);
        }
        catch
        {
            return false;
        }

        // Drive roots ("C:\") and the protected set are never cleanable as a whole.
        if (Path.GetPathRoot(full) is { } driveRoot && Normalize(driveRoot).Equals(full, StringComparison.OrdinalIgnoreCase))
            return false;

        return !Protected.Value.Contains(full);
    }

    public static bool IsInside(string path, IEnumerable<string> roots)
    {
        string full;
        try
        {
            full = Normalize(path);
        }
        catch
        {
            return false;
        }

        foreach (var root in roots)
        {
            var r = Normalize(root);
            if (full.Length > r.Length + 1 &&
                full.StartsWith(r, StringComparison.OrdinalIgnoreCase) &&
                full[r.Length] == '\\')
            {
                return true;
            }
        }

        return false;
    }

    public static string Normalize(string path)
        => Path.TrimEndingDirectorySeparator(Path.GetFullPath(path));

    private static HashSet<string> BuildProtectedSet()
    {
        var set = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        void Add(string? p)
        {
            if (!string.IsNullOrWhiteSpace(p))
            {
                try { set.Add(Normalize(p)); } catch { /* ignore malformed */ }
            }
        }

        Add(Environment.GetFolderPath(Environment.SpecialFolder.Windows));
        Add(Environment.GetFolderPath(Environment.SpecialFolder.System));
        Add(Environment.GetFolderPath(Environment.SpecialFolder.SystemX86));
        Add(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles));
        Add(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86));
        Add(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData));
        Add(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData));
        Add(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData));
        Add(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile));
        Add(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments));
        Add(Environment.GetFolderPath(Environment.SpecialFolder.MyPictures));
        Add(Environment.GetFolderPath(Environment.SpecialFolder.MyVideos));
        Add(Environment.GetFolderPath(Environment.SpecialFolder.MyMusic));
        Add(Environment.GetFolderPath(Environment.SpecialFolder.Desktop));

        var profile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        if (!string.IsNullOrEmpty(profile))
        {
            Add(Path.GetDirectoryName(profile)); // C:\Users
            Add(Path.Combine(profile, "AppData"));
            Add(Path.Combine(profile, "AppData", "LocalLow"));
            Add(Path.Combine(profile, "Downloads"));
            Add(Path.Combine(profile, "OneDrive"));
        }

        return set;
    }
}
