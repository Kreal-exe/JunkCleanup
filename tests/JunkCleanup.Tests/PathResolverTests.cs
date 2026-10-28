using JunkCleanup.Core;

namespace JunkCleanup.Tests;

public class PathResolverTests : IDisposable
{
    private readonly string _root = Path.Combine(Path.GetTempPath(), "JunkCleanupTests", Guid.NewGuid().ToString("N"));

    public PathResolverTests()
    {
        Directory.CreateDirectory(Path.Combine(_root, "User Data", "Default", "Cache"));
        Directory.CreateDirectory(Path.Combine(_root, "User Data", "Profile 1", "Cache"));
        Directory.CreateDirectory(Path.Combine(_root, "User Data", "Profile 2"));
        Directory.CreateDirectory(Path.Combine(_root, "app-updater", "pending"));
    }

    [Fact]
    public void Wildcard_segment_expands_only_to_existing_leaf_folders()
    {
        var result = PathResolver.Expand(Path.Combine(_root, "User Data", "*", "Cache")).ToList();

        Assert.Equal(2, result.Count);
        Assert.Contains(Path.Combine(_root, "User Data", "Default", "Cache"), result);
        Assert.Contains(Path.Combine(_root, "User Data", "Profile 1", "Cache"), result);
    }

    [Fact]
    public void Wildcard_with_suffix_matches_folder_names()
    {
        var result = PathResolver.Expand(Path.Combine(_root, "*-updater", "pending")).ToList();
        Assert.Single(result);
    }

    [Fact]
    public void Missing_folder_yields_nothing()
        => Assert.Empty(PathResolver.Expand(Path.Combine(_root, "nope")));

    [Fact]
    public void Unknown_environment_variable_yields_nothing()
        => Assert.Empty(PathResolver.Expand(@"%JUNKCLEANUP_DOES_NOT_EXIST%\x"));

    [Fact]
    public void Environment_variables_are_expanded()
    {
        // %TEMP% may be a short (8.3) path on CI runners, so compare existence rather than the exact string.
        var result = PathResolver.Expand("%TEMP%").ToList();
        Assert.Single(result);
        Assert.True(Directory.Exists(result[0]));
        Assert.False(result[0].Contains('%'));
    }

    public void Dispose()
    {
        try { Directory.Delete(_root, true); } catch { /* best effort */ }
    }
}
