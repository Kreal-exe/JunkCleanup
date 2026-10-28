using Microsoft.Win32;

namespace JunkCleanup.Core;

/// <summary>Expands environment variables, custom tokens and wildcard directory segments into existing folders.</summary>
public static class PathResolver
{
    private static readonly char[] Separators = ['\\', '/'];

    public static string? SteamPath
    {
        get
        {
            try
            {
                using var key = Registry.CurrentUser.OpenSubKey(@"Software\Valve\Steam");
                var value = key?.GetValue("SteamPath") as string;
                if (string.IsNullOrWhiteSpace(value)) return null;
                var full = Path.GetFullPath(value.Replace('/', '\\'));
                return Directory.Exists(full) ? full : null;
            }
            catch
            {
                return null;
            }
        }
    }

    public static IEnumerable<string> Expand(string pattern)
    {
        var expanded = Environment.ExpandEnvironmentVariables(pattern);

        if (expanded.Contains("{steam}", StringComparison.OrdinalIgnoreCase))
        {
            var steam = SteamPath;
            if (steam is null) return [];
            expanded = expanded.Replace("{steam}", steam, StringComparison.OrdinalIgnoreCase);
        }

        // Unresolved %VAR% means the variable does not exist on this machine.
        if (expanded.Contains('%')) return [];

        var parts = expanded.Split(Separators, StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length == 0 || !parts[0].EndsWith(':')) return [];

        List<string> current = [parts[0] + "\\"];
        for (var i = 1; i < parts.Length; i++)
        {
            var segment = parts[i];
            if (segment.Contains('*') || segment.Contains('?'))
            {
                current = current.SelectMany(dir => EnumerateDirectories(dir, segment)).ToList();
            }
            else
            {
                current = current.Select(dir => Path.Combine(dir, segment)).ToList();
            }

            if (current.Count == 0) return [];
        }

        return current.Where(Directory.Exists).Select(p => Path.TrimEndingDirectorySeparator(p));
    }

    private static IEnumerable<string> EnumerateDirectories(string dir, string pattern)
    {
        try
        {
            if (!Directory.Exists(dir)) return [];
            return Directory.EnumerateDirectories(dir, pattern, new EnumerationOptions
            {
                IgnoreInaccessible = true,
                AttributesToSkip = FileAttributes.ReparsePoint,
                MatchCasing = MatchCasing.CaseInsensitive,
            }).ToList();
        }
        catch
        {
            return [];
        }
    }
}
