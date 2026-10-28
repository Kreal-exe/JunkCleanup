using JunkCleanup.Core;

namespace JunkCleanup.Tests;

public class PathGuardTests
{
    [Theory]
    [InlineData(@"C:\")]
    [InlineData(@"c:/")]
    [InlineData(@"D:\")]
    public void Drive_roots_are_never_allowed(string root)
        => Assert.False(PathGuard.IsAllowedRoot(root));

    [Fact]
    public void Critical_folders_are_never_allowed()
    {
        Assert.False(PathGuard.IsAllowedRoot(Environment.GetFolderPath(Environment.SpecialFolder.Windows)));
        Assert.False(PathGuard.IsAllowedRoot(Environment.GetFolderPath(Environment.SpecialFolder.System)));
        Assert.False(PathGuard.IsAllowedRoot(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles)));
        Assert.False(PathGuard.IsAllowedRoot(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)));
        Assert.False(PathGuard.IsAllowedRoot(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData)));
        Assert.False(PathGuard.IsAllowedRoot(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments)));
        Assert.False(PathGuard.IsAllowedRoot(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads")));
    }

    [Fact]
    public void Protected_check_ignores_trailing_separator_and_case()
    {
        var windows = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
        Assert.False(PathGuard.IsAllowedRoot(windows + "\\"));
        Assert.False(PathGuard.IsAllowedRoot(windows.ToLowerInvariant()));
    }

    [Fact]
    public void Cache_folders_under_profile_are_allowed()
    {
        Assert.True(PathGuard.IsAllowedRoot(Path.GetTempPath()));
        Assert.True(PathGuard.IsAllowedRoot(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "pip", "cache")));
    }

    [Fact]
    public void Malformed_paths_are_rejected()
    {
        Assert.False(PathGuard.IsAllowedRoot(""));
        Assert.False(PathGuard.IsAllowedRoot("   "));
        Assert.False(PathGuard.IsAllowedRoot("not\0valid"));
    }

    [Fact]
    public void IsInside_requires_a_proper_descendant()
    {
        string[] roots = [@"C:\Cache\Root"];
        Assert.True(PathGuard.IsInside(@"C:\Cache\Root\file.bin", roots));
        Assert.True(PathGuard.IsInside(@"C:\cache\root\sub\file.bin", roots));
        Assert.False(PathGuard.IsInside(@"C:\Cache\Root", roots));
        Assert.False(PathGuard.IsInside(@"C:\Cache\RootOther\file.bin", roots));
        Assert.False(PathGuard.IsInside(@"C:\Cache\Root\..\Other\file.bin", roots));
        Assert.False(PathGuard.IsInside(@"D:\Cache\Root\file.bin", roots));
    }
}
