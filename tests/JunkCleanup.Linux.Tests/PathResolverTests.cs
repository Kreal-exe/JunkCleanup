using JunkCleanup.Core;

namespace JunkCleanup.Linux.Tests;

public sealed class PathResolverTests
{
    [Fact]
    public void XdgFoldersDefaultToTheSpecLocations()
    {
        using var home = new FakeHome();
        Assert.Equal(home.Home + "/.cache", PathResolver.CacheHome);
        Assert.Equal(home.Home + "/.config", PathResolver.ConfigHome);
        Assert.Equal(home.Home + "/.local/share", PathResolver.DataHome);
        Assert.Equal(home.Home + "/.local/state", PathResolver.StateHome);
    }

    [Fact]
    public void XdgVariablesOverrideTheDefaults_OnlyWhenAbsolute()
    {
        using var home = new FakeHome();
        home.Set("XDG_CACHE_HOME", "/data/cache/");
        home.Set("XDG_CONFIG_HOME", "relative/config");
        Assert.Equal("/data/cache", PathResolver.CacheHome);
        Assert.Equal(home.Home + "/.config", PathResolver.ConfigHome);
    }

    [Fact]
    public void ExpandsTildeAndVariables()
    {
        using var home = new FakeHome();
        home.Set("CARGO_HOME", "/opt/cargo");
        Assert.Equal(home.Home + "/.npm/_cacache", PathResolver.ExpandVariables("~/.npm/_cacache"));
        Assert.Equal(home.Home + "/.cache/pip", PathResolver.ExpandVariables("$XDG_CACHE_HOME/pip"));
        Assert.Equal("/opt/cargo/registry", PathResolver.ExpandVariables("${CARGO_HOME}/registry"));
        Assert.Null(PathResolver.ExpandVariables("$NOT_SET_ANYWHERE/x"));
        Assert.Null(PathResolver.ExpandVariables("relative/path"));
    }

    [Fact]
    public void ExpandReturnsOnlyExistingFolders()
    {
        using var home = new FakeHome();
        Assert.Empty(PathResolver.Expand("$XDG_CACHE_HOME/pip"));
        var pip = home.Dir(".cache/pip");
        Assert.Equal([pip], PathResolver.Expand("$XDG_CACHE_HOME/pip"));
    }

    [Fact]
    public void WildcardsMatchEveryProfile_CaseSensitively()
    {
        using var home = new FakeHome();
        var a = home.Dir(".cache/mozilla/firefox/abc.default-release");
        var b = home.Dir(".cache/mozilla/firefox/xyz.work");
        home.Dir(".var/app/org.mozilla.firefox/cache/mozilla/firefox/p1.default");

        var found = PathResolver.Expand("$XDG_CACHE_HOME/mozilla/firefox/*").OrderBy(p => p).ToList();
        Assert.Equal([a, b], found);
        Assert.Single(PathResolver.Expand("~/.var/app/*/cache/mozilla/firefox/*"));
        // Linux file systems are case-sensitive; macOS's APFS (where these tests also run) usually is not.
        var caseSensitive = !Directory.Exists(home.Home + "/.VAR");
        if (caseSensitive) Assert.Empty(PathResolver.Expand("~/.var/APP/*/cache"));
    }

    [Fact]
    public void WildcardsDoNotWalkThroughSymlinks()
    {
        using var home = new FakeHome();
        home.Dir("snap/firefox/4793/.cache");
        Directory.CreateSymbolicLink(Path.Combine(home.Home, "snap/firefox/current"), "4793");

        var found = PathResolver.Expand("~/snap/*/*/.cache");
        Assert.Equal([home.Home + "/snap/firefox/4793/.cache"], found);
    }

    [Fact]
    public void SymlinkedRootsResolveToTheirTarget_AndCountOnce()
    {
        using var home = new FakeHome();
        var real = home.Dir(".local/share/Steam/steamapps/shadercache");
        Directory.CreateDirectory(home.Home + "/.steam");
        Directory.CreateSymbolicLink(home.Home + "/.steam/steam", home.Home + "/.local/share/Steam");

        var roots = TargetCatalog.All.Single(t => t.Id == "game.steam").ResolveRoots();
        Assert.Equal([real], roots);
    }
}
