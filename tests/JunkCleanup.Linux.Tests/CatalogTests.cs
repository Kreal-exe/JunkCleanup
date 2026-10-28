using JunkCleanup.Controls;
using JunkCleanup.Core;
using JunkCleanup.Localization;
using Material.Icons;

namespace JunkCleanup.Linux.Tests;

public sealed class CatalogTests
{
    [Fact]
    public void IdsAreUnique() =>
        Assert.Equal(TargetCatalog.All.Count, TargetCatalog.All.Select(t => t.Id).Distinct().Count());

    [Fact]
    public void EveryIconExists()
    {
        foreach (var t in TargetCatalog.All)
            Assert.True(Enum.TryParse<MaterialIconKind>(t.Glyph, out _), $"{t.Id}: no Material icon \"{t.Glyph}\"");
    }

    [Fact]
    public void EveryTargetHasANameAndDescriptionInEveryLanguage()
    {
        foreach (var language in LocalizationManager.Languages)
        {
            var strings = LocalizationManager.Load(language.Code);
            Assert.NotNull(strings);
            foreach (var t in TargetCatalog.All)
            {
                Assert.True(strings!.ContainsKey(t.NameKey), $"{language.Code}: {t.NameKey}");
                Assert.True(strings.ContainsKey(t.DescriptionKey), $"{language.Code}: {t.DescriptionKey}");
            }
        }
    }

    [Fact]
    public void LinuxWordingIsLaidOverTheWindowsStrings()
    {
        foreach (var language in LocalizationManager.Languages)
        {
            var strings = LocalizationManager.Load(language.Code)!;
            Assert.DoesNotContain("Windows", strings["about.description"]);
            Assert.Contains("Linu", strings["about.description"]); // "Linuksa" in Polish
            Assert.Contains("{0}", strings["about.builtWith"]);
            Assert.Contains("{1}", strings["insight.pkgcache.detail"]);
        }
    }

    [Fact]
    public void SystemLocaleNamesMatchTheAppLanguages()
    {
        Assert.Equal("ru", LocalizationManager.MatchName("ru-RU"));
        Assert.Equal("pt", LocalizationManager.MatchName("pt-BR"));
        Assert.Equal("zh-Hant", LocalizationManager.MatchName("zh-TW"));
        Assert.Equal("zh-Hans", LocalizationManager.MatchName("zh-CN"));
        Assert.Null(LocalizationManager.MatchName("xx-YY"));
    }

    [Fact]
    public void IconConverterFallsBackForUnknownNames() =>
        Assert.Equal(MaterialIconKind.FolderOutline, IconConverter.Parse("NoSuchIcon"));

    /// <summary>A home folder laid out like a real desktop: each target finds exactly its own folders.</summary>
    [Fact]
    public void ResolvesARealisticHome()
    {
        using var home = new FakeHome();
        home.Dir(".cache/thumbnails/large");
        home.Dir(".cache/pip/http-v2");
        home.Dir(".cache/google-chrome/Default/Cache");
        home.Dir(".config/google-chrome/Default/Code Cache");
        home.Dir(".config/google-chrome/Profile 1/GPUCache");
        home.Dir(".config/google-chrome/Default/Local Storage"); // user data, not a cache
        home.Dir(".cache/mozilla/firefox/abc.default-release/cache2");
        home.Dir(".mozilla/firefox/abc.default-release/shader-cache");
        home.Dir(".config/discord/Cache");
        home.Dir(".config/Obsidian/Cache");
        home.Dir(".var/app/org.mozilla.firefox/cache/mozilla/firefox/p1.default");
        home.Dir(".var/app/org.gimp.GIMP/cache/gimp");
        home.Dir("snap/spotify/common/.cache/spotify");
        home.Dir("snap/code/180/.cache/fontconfig");
        // Snap's Chromium keeps the HTTP cache inside the profile; Snap's Firefox next to launcher-managed caches.
        home.Dir("snap/chromium/common/chromium/Default/Cache/Cache_Data");
        home.Dir("snap/chromium/common/chromium/Default/Local Storage");
        home.Dir("snap/firefox/common/.cache/mozilla/firefox/tg0p8lmr.default/cache2");
        home.Dir("snap/firefox/common/.cache/mesa_shader_cache");
        home.Dir("snap/firefox/common/.cache/gio-modules");
        home.Dir("snap/firefox/common/.cache/immodules");
        home.Dir(".local/share/Trash/files");

        IReadOnlyList<string> Roots(string id) => TargetCatalog.All.Single(t => t.Id == id).ResolveRoots();
        var h = home.Home;

        Assert.Equal([h + "/.cache/thumbnails"], Roots("linux.thumbnails"));
        Assert.Equal([h + "/.cache/pip"], Roots("dev.pip"));
        Assert.Equal(
            new[] { h + "/.cache/google-chrome", h + "/.config/google-chrome/Default/Code Cache", h + "/.config/google-chrome/Profile 1/GPUCache" }.Order(),
            Roots("browser.chrome").Order());
        Assert.Equal(
            new[] { h + "/.cache/mozilla/firefox/abc.default-release", h + "/.var/app/org.mozilla.firefox/cache/mozilla/firefox/p1.default",
                    h + "/.mozilla/firefox/abc.default-release/shader-cache", h + "/snap/firefox/common/.cache/mozilla/firefox/tg0p8lmr.default" }.Order(),
            Roots("browser.firefox").Order());
        Assert.Equal([h + "/.config/discord/Cache"], Roots("app.discord"));
        Assert.Equal([h + "/snap/chromium/common/chromium/Default/Cache"], Roots("browser.chromium"));
        Assert.Equal([h + "/snap/spotify/common/.cache/spotify"], Roots("app.spotify"));

        // The catch-alls skip whatever a specific target owns: Discord and both Firefox caches stay with their targets.
        Assert.Equal([h + "/.config/Obsidian/Cache"], Roots("app.electron"));
        Assert.Equal([h + "/.var/app/org.gimp.GIMP/cache/gimp"], Roots("app.flatpak"));
        Assert.Equal(
            new[] { h + "/snap/code/180/.cache/fontconfig", h + "/snap/firefox/common/.cache/mesa_shader_cache" }.Order(),
            Roots("app.snap").Order());

        // Nothing resolves to a protected folder.
        foreach (var t in TargetCatalog.All)
            foreach (var root in t.ResolveRoots())
                Assert.True(PathGuard.IsAllowedRoot(root), $"{t.Id}: {root}");
    }

    [Fact]
    public void CustomFoldersKeepTheirCase()
    {
        var custom = TargetCatalog.CreateCustom("/data/Cache/");
        Assert.Equal("custom:/data/Cache", custom.Id);
        Assert.Equal("Cache", custom.DisplayName);
    }
}
