namespace JunkCleanup.Core;

/// <summary>
/// Last line of defence: refuses to treat system and personal folders (or anything that holds one) as cleanable roots,
/// and refuses to delete anything that does not live underneath one of the roots that were scanned.
/// </summary>
public static class PathGuard
{
    /// <summary>Linux paths are case-sensitive.</summary>
    public static StringComparison Comparison => StringComparison.Ordinal;
    public static StringComparer Comparer => StringComparer.Ordinal;

    private static readonly string[] SystemFolders =
    [
        "/", "/bin", "/boot", "/dev", "/etc", "/home", "/lib", "/lib32", "/lib64", "/libx32", "/media", "/mnt", "/opt",
        "/proc", "/root", "/run", "/sbin", "/snap", "/srv", "/sys", "/tmp", "/usr", "/usr/local", "/usr/share", "/var",
        "/var/cache", "/var/lib", "/var/log", "/var/tmp", "/nix", "/nix/store", "/flatpak",
    ];

    /// <summary>Under the home folder: the personal folders, and the parents of caches (never cleaned as a whole).</summary>
    private static readonly string[] PersonalFolders =
    [
        "", "/Desktop", "/Documents", "/Downloads", "/Pictures", "/Videos", "/Music", "/Public", "/Templates",
        "/.ssh", "/.gnupg", "/.pki", "/.password-store", "/.mozilla", "/.mozilla/firefox", "/.thunderbird",
        "/.config", "/.local", "/.local/share", "/.local/state", "/.local/bin", "/.local/lib", "/.local/share/Trash",
        "/.local/share/keyrings", "/.local/share/flatpak", "/.local/share/Steam", "/.local/share/TelegramDesktop",
        "/.cache", "/.var", "/.var/app", "/snap", "/.steam", "/.cargo", "/.rustup", "/.gradle", "/.m2", "/.npm", "/.nuget",
        "/.android", "/.conda", "/.docker", "/.kube", "/.aws", "/.azure", "/.vscode", "/.bun", "/.yarn", "/.java",
        "/.ollama", "/.lmstudio", "/.codex", "/.wine", "/go", "/miniconda3", "/anaconda3", "/miniforge3",
    ];

    private static readonly object Gate = new();
    private static string? _cachedFor;
    private static HashSet<string> _protected = new(StringComparer.Ordinal);

    /// <summary>
    /// Collapses "//", "." and ".." without touching the file system. The file itself may be a symlink, which is
    /// removed, never followed, so files are compared by this lexical form.
    /// </summary>
    public static string Normalize(string path)
        => Path.TrimEndingDirectorySeparator(Path.GetFullPath(path));

    /// <summary>The path with every symlink along it resolved (realpath). Parts that do not exist are kept as written.</summary>
    public static string RealPath(string path)
    {
        var pending = new List<string>(Normalize(path).Split('/', StringSplitOptions.RemoveEmptyEntries));
        var resolved = "/";
        var hops = 0;

        while (pending.Count > 0)
        {
            var part = pending[0];
            pending.RemoveAt(0);
            var next = resolved == "/" ? "/" + part : resolved + "/" + part;

            string? target;
            try
            {
                target = new FileInfo(next).LinkTarget;
            }
            catch
            {
                target = null;
            }

            if (target is null)
            {
                resolved = next;
                continue;
            }

            if (++hops > 40) throw new IOException("Too many levels of symbolic links: " + path);
            var absolute = Normalize(target.StartsWith('/') ? target : Path.Combine(resolved, target));
            pending.InsertRange(0, absolute.Split('/', StringSplitOptions.RemoveEmptyEntries));
            resolved = "/";
        }

        return resolved;
    }

    public static bool IsAllowedRoot(string root)
    {
        if (string.IsNullOrWhiteSpace(root) || !root.StartsWith('/')) return false;

        string real, lexical;
        try
        {
            lexical = Normalize(root);
            real = RealPath(root);
        }
        catch
        {
            return false;
        }

        if (real == "/" || lexical == "/") return false;
        var guarded = ProtectedPaths();
        if (guarded.Contains(real) || guarded.Contains(lexical)) return false;

        // Never a folder that holds the home folder or a protected one: cleaning it would take that folder along.
        foreach (var p in guarded)
            if (IsInside(p, [real]) || IsInside(p, [lexical])) return false;
        return true;
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
            string r;
            try { r = Normalize(root); } catch { continue; }
            if (r.Length <= 1) continue; // "/" is never a root
            if (full.Length > r.Length + 1 && full.StartsWith(r, StringComparison.Ordinal) && full[r.Length] == '/')
                return true;
        }

        return false;
    }

    /// <summary>Every protected folder, both as written and as its real path. Rebuilt when the home folder changes (tests).</summary>
    public static IReadOnlySet<string> ProtectedPaths()
    {
        var home = PathResolver.Home;
        lock (Gate)
        {
            if (_cachedFor == home) return _protected;

            var set = new HashSet<string>(StringComparer.Ordinal);
            void Add(string? p)
            {
                if (string.IsNullOrWhiteSpace(p) || !p.StartsWith('/')) return;
                try
                {
                    set.Add(Normalize(p));
                    set.Add(RealPath(p));
                }
                catch
                {
                    // malformed or a symlink loop: the written form is enough
                }
            }

            foreach (var p in SystemFolders) Add(p);
            foreach (var p in PersonalFolders) Add(home + p);
            Add(Path.GetDirectoryName(home));
            foreach (var xdg in new[] { "XDG_CACHE_HOME", "XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_STATE_HOME" })
                Add(PathResolver.Xdg(xdg));
            foreach (var dir in UserDirs(home)) Add(dir);

            _protected = set;
            _cachedFor = home;
            return set;
        }
    }

    /// <summary>
    /// The personal folders from ~/.config/user-dirs.dirs, which carry localized names ("~/Загрузки", "~/Bilder").
    /// </summary>
    internal static IEnumerable<string> UserDirs(string home)
    {
        var file = Path.Combine(PathResolver.ConfigHome, "user-dirs.dirs");
        string[] lines;
        try
        {
            if (!File.Exists(file)) return [];
            lines = File.ReadAllLines(file);
        }
        catch
        {
            return [];
        }

        var dirs = new List<string>();
        foreach (var raw in lines)
        {
            var line = raw.Trim();
            if (!line.StartsWith("XDG_", StringComparison.Ordinal)) continue;
            var eq = line.IndexOf('=');
            if (eq < 0) continue;
            var value = line[(eq + 1)..].Trim().Trim('"');
            if (value.StartsWith("$HOME", StringComparison.Ordinal)) value = home + value[5..];
            if (value.StartsWith('/')) dirs.Add(value);
        }
        return dirs;
    }
}
