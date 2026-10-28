using JunkCleanup.Core;

namespace JunkCleanup.Linux.Tests;

public sealed class PathGuardTests
{
    [Theory]
    [InlineData("/")]
    [InlineData("/usr")]
    [InlineData("/etc")]
    [InlineData("/var")]
    [InlineData("/var/log")]
    [InlineData("/home")]
    [InlineData("/tmp")]
    public void SystemFoldersAreRefused(string path) => Assert.False(PathGuard.IsAllowedRoot(path));

    [Theory]
    [InlineData("")]
    [InlineData("/Documents")]
    [InlineData("/Downloads")]
    [InlineData("/.cache")]
    [InlineData("/.config")]
    [InlineData("/.local/share")]
    [InlineData("/.ssh")]
    [InlineData("/.mozilla/firefox")]
    [InlineData("/.var/app")]
    [InlineData("/snap")]
    [InlineData("/.local/share/Trash")]
    public void PersonalFoldersAreRefused(string relative)
    {
        using var home = new FakeHome();
        var path = home.Home + relative;
        Directory.CreateDirectory(path);
        Assert.False(PathGuard.IsAllowedRoot(path));
    }

    [Fact]
    public void CacheSubfoldersAreAllowed()
    {
        using var home = new FakeHome();
        Assert.True(PathGuard.IsAllowedRoot(home.Dir(".cache/pip")));
        Assert.True(PathGuard.IsAllowedRoot(home.Dir(".var/app/com.spotify.Client/cache")));
        Assert.True(PathGuard.IsAllowedRoot("/var/crash"));
    }

    [Fact]
    public void AFolderHoldingTheHomeFolderIsRefused()
    {
        using var home = new FakeHome();
        Assert.False(PathGuard.IsAllowedRoot(Path.GetDirectoryName(home.Home)!));
        Assert.False(PathGuard.IsAllowedRoot(home.Root));
    }

    [Fact]
    public void ASymlinkIsJudgedByItsTarget()
    {
        using var home = new FakeHome();
        var documents = home.Dir("Documents");
        home.Dir(".cache");
        Directory.CreateSymbolicLink(home.Home + "/.cache/pip", documents);
        Assert.False(PathGuard.IsAllowedRoot(home.Home + "/.cache/pip"));
        Assert.DoesNotContain(PathResolver.Expand("$XDG_CACHE_HOME/pip"), PathGuard.IsAllowedRoot);
    }

    [Fact]
    public void AFolderHoldingALinkedPersonalFolderIsRefused()
    {
        using var home = new FakeHome();
        // ~/Documents lives on another disk: that disk's folder above it must not become a root either.
        var data = Path.Combine(home.Root, "data");
        Directory.CreateDirectory(Path.Combine(data, "Documents"));
        Directory.CreateSymbolicLink(home.Home + "/Documents", Path.Combine(data, "Documents"));
        Assert.False(PathGuard.IsAllowedRoot(data));
    }

    [Fact]
    public void LocalizedUserDirsAreProtected()
    {
        using var home = new FakeHome();
        var downloads = home.Dir("Загрузки");
        home.File(".config/user-dirs.dirs", 0);
        File.WriteAllText(home.Home + "/.config/user-dirs.dirs",
            "# written by xdg-user-dirs-update\nXDG_DOWNLOAD_DIR=\"$HOME/Загрузки\"\nXDG_PICTURES_DIR=\"/mnt/photos\"\n");
        Assert.False(PathGuard.IsAllowedRoot(downloads));
        Assert.Contains("/mnt/photos", PathGuard.ProtectedPaths());
    }

    [Fact]
    public void IsInsideIsLexicalAndCaseSensitive()
    {
        Assert.True(PathGuard.IsInside("/home/u/.cache/pip/a/b", ["/home/u/.cache/pip"]));
        Assert.False(PathGuard.IsInside("/home/u/.cache/pip", ["/home/u/.cache/pip"]));
        Assert.False(PathGuard.IsInside("/home/u/.cache/pip2/x", ["/home/u/.cache/pip"]));
        Assert.False(PathGuard.IsInside("/home/u/.cache/PIP/x", ["/home/u/.cache/pip"]));
        Assert.False(PathGuard.IsInside("/home/u/.cache/pip/../../Documents/x", ["/home/u/.cache/pip"]));
        Assert.False(PathGuard.IsInside("/etc/passwd", ["/"]));
    }

    [Fact]
    public void RealPathFollowsLinksAlongThePath()
    {
        using var home = new FakeHome();
        var target = home.Dir("big/cache");
        Directory.CreateSymbolicLink(home.Home + "/.cache", home.Home + "/big/cache");
        home.Dir("big/cache/pip");
        Assert.Equal(target + "/pip", PathGuard.RealPath(home.Home + "/.cache/pip"));
        Assert.Equal(home.Home + "/nothing/here", PathGuard.RealPath(home.Home + "/nothing/here"));
    }
}
