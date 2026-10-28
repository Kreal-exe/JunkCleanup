using System.Text.RegularExpressions;

namespace JunkCleanup.Core;

/// <summary>
/// Expands "~", XDG base directories ($XDG_CACHE_HOME and friends, with their spec defaults), other environment
/// variables and wildcard directory segments into existing folders. Results are real paths: symlinks are resolved, so a
/// link elsewhere is judged by where it points and two routes to one folder count once.
/// </summary>
public static partial class PathResolver
{
    /// <summary>Environment lookup. Tests point it at a fake home.</summary>
    internal static Func<string, string?> GetEnv { get; set; } = Environment.GetEnvironmentVariable;

    /// <summary>XDG base directories and the default each one has when its variable is unset or not absolute.</summary>
    private static readonly Dictionary<string, string> XdgDefaults = new(StringComparer.Ordinal)
    {
        ["XDG_CACHE_HOME"] = ".cache",
        ["XDG_CONFIG_HOME"] = ".config",
        ["XDG_DATA_HOME"] = ".local/share",
        ["XDG_STATE_HOME"] = ".local/state",
    };

    public static string Home
    {
        get
        {
            var home = GetEnv("HOME");
            if (string.IsNullOrEmpty(home) || !home.StartsWith('/'))
                home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            return home.Length > 1 ? home.TrimEnd('/') : home;
        }
    }

    public static string CacheHome => Xdg("XDG_CACHE_HOME");
    public static string ConfigHome => Xdg("XDG_CONFIG_HOME");
    public static string DataHome => Xdg("XDG_DATA_HOME");
    public static string StateHome => Xdg("XDG_STATE_HOME");

    public static string Xdg(string variable)
    {
        var value = GetEnv(variable);
        if (!string.IsNullOrEmpty(value) && value.StartsWith('/')) return value.Length > 1 ? value.TrimEnd('/') : value;
        return Home + "/" + XdgDefaults[variable];
    }

    [GeneratedRegex(@"\$(?:\{(?<n>[A-Za-z_][A-Za-z0-9_]*)\}|(?<n>[A-Za-z_][A-Za-z0-9_]*))")]
    private static partial Regex VariablePattern();

    /// <summary>"~/x", "$XDG_CACHE_HOME/x" or "${NAME}/x" as an absolute path, or null when a variable is not set.</summary>
    public static string? ExpandVariables(string pattern)
    {
        var text = pattern == "~" ? Home : pattern.StartsWith("~/", StringComparison.Ordinal) ? Home + pattern[1..] : pattern;
        var missing = false;
        text = VariablePattern().Replace(text, m =>
        {
            var name = m.Groups["n"].Value;
            if (XdgDefaults.ContainsKey(name)) return Xdg(name);
            if (name == "HOME") return Home;
            var value = GetEnv(name);
            if (string.IsNullOrEmpty(value)) missing = true;
            return value ?? string.Empty;
        });
        return missing || !text.StartsWith('/') ? null : text;
    }

    public static IEnumerable<string> Expand(string pattern)
    {
        var expanded = ExpandVariables(pattern);
        if (expanded is null) return [];

        List<string> current = ["/"];
        foreach (var segment in expanded.Split('/', StringSplitOptions.RemoveEmptyEntries))
        {
            if (segment.Contains('*') || segment.Contains('?'))
                current = current.SelectMany(dir => EnumerateDirectories(dir, segment)).ToList();
            else
                current = current.Select(dir => Path.Combine(dir, segment)).ToList();

            if (current.Count == 0) return [];
        }

        return current
            .Where(Directory.Exists)
            .Select(PathGuard.RealPath)
            .Distinct(StringComparer.Ordinal)
            .ToList();
    }

    private static IEnumerable<string> EnumerateDirectories(string dir, string pattern)
    {
        try
        {
            if (!Directory.Exists(dir)) return [];
            // A wildcard never walks through a symlink (snap's "current", a profile linked from elsewhere): only real folders.
            return Directory.EnumerateDirectories(dir, pattern, new EnumerationOptions
            {
                IgnoreInaccessible = true,
                AttributesToSkip = FileAttributes.ReparsePoint,
                MatchCasing = MatchCasing.CaseSensitive,
            }).ToList();
        }
        catch
        {
            return [];
        }
    }
}
