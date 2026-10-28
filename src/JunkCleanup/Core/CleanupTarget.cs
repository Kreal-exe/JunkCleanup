namespace JunkCleanup.Core;

public enum TargetCategory { System, Browsers, Developer, Apps, Gaming, Custom }

public enum RiskLevel { Safe, Moderate, Careful }

public enum TargetKind { Files, RecycleBin }

/// <summary>
/// A declarative description of one cleanable location: where it lives, what files count,
/// and how risky it is to remove them. Names and descriptions live in the localization files
/// under <c>target.{Id}.name</c> / <c>target.{Id}.desc</c>.
/// </summary>
public sealed class CleanupTarget
{
    public required string Id { get; init; }
    public required TargetCategory Category { get; init; }
    public required string Glyph { get; init; }

    public TargetKind Kind { get; init; } = TargetKind.Files;
    public RiskLevel Risk { get; init; } = RiskLevel.Safe;
    public bool RequiresAdmin { get; init; }
    public bool EnabledByDefault { get; init; } = true;

    /// <summary>When true the "skip recent files" setting applies (temp folders).</summary>
    public bool RespectsAgeFilter { get; init; }
    public bool Recursive { get; init; } = true;

    /// <summary>Directory patterns; may contain environment variables and <c>*</c> segments.</summary>
    public string[] RootPatterns { get; init; } = [];
    public string[] FilePatterns { get; init; } = ["*"];

    /// <summary>
    /// A catch-all (other apps' caches, ~/.cache): it never takes a folder that a specific target owns, holds one, or
    /// sits inside one, so nothing is counted or deleted twice.
    /// </summary>
    public bool Fallback { get; init; }

    /// <summary>Folder names a wildcard root never takes (files a launcher manages next to real caches).</summary>
    public string[] ExcludedNames { get; init; } = [];

    /// <summary>The roots are versions of one thing (an app's bundled runtimes): the newest one is in use and left alone.</summary>
    public bool KeepNewest { get; init; }

    /// <summary>Display name override (custom folders); null means use the localized key.</summary>
    public string? DisplayName { get; init; }

    public string NameKey => $"target.{Id}.name";
    public string DescriptionKey => $"target.{Id}.desc";

    public IReadOnlyList<string> ResolveRoots()
    {
        var roots = RootPatterns
            .SelectMany(PathResolver.Expand)
            .Distinct(PathGuard.Comparer)
            .Where(PathGuard.IsAllowedRoot)
            .Where(r => !ExcludedNames.Contains(Path.GetFileName(r), PathGuard.Comparer))
            .ToList();
        if (KeepNewest && roots.Count > 0) roots.Remove(roots.MaxBy(r => Path.GetFileName(r), VersionComparer.Instance)!);
        if (!Fallback) return roots;

        var claimed = TargetCatalog.All
            .Where(t => !t.Fallback && t.Kind == TargetKind.Files)
            .SelectMany(t => t.ResolveRoots())
            .Select(PathGuard.Normalize)
            .ToList();
        return roots.Where(root =>
        {
            var r = PathGuard.Normalize(root);
            return !claimed.Any(c => c.Equals(r, PathGuard.Comparison) || PathGuard.IsInside(r, [c]) || PathGuard.IsInside(c, [r]));
        }).ToList();
    }
}

/// <summary>Orders "2.1.309" after "2.1.308" and "10.0" after "9.0"; names that are not versions compare as text.</summary>
internal sealed class VersionComparer : IComparer<string>
{
    public static readonly VersionComparer Instance = new();

    public int Compare(string? x, string? y)
    {
        if (Version.TryParse(x, out var a) && Version.TryParse(y, out var b)) return a.CompareTo(b);
        return StringComparer.OrdinalIgnoreCase.Compare(x, y);
    }
}
