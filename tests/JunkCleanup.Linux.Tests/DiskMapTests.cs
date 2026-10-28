using JunkCleanup.Core;
using JunkCleanup.Localization;
using Material.Icons;

namespace JunkCleanup.Linux.Tests;

public sealed class DiskMapTests
{
    private static async Task<SpaceReport> Analyze() =>
        await new DiskMapEngine().AnalyzeAsync(SpaceCatalog.Scope(), TargetCatalog.All, null, CancellationToken.None);

    private static IEnumerable<SpaceEntry> Flatten(IEnumerable<SpaceEntry> entries) =>
        entries.SelectMany(e => Flatten(e.Children).Prepend(e));

    [Fact]
    public void EveryRuleHasAnIconAndStringsInEveryLanguage()
    {
        foreach (var rule in SpaceCatalog.Rules)
            Assert.True(Enum.TryParse<MaterialIconKind>(rule.Glyph, out _), $"{rule.Id}: no Material icon \"{rule.Glyph}\"");
        var kinds = SpaceCatalog.Rules.SelectMany(r => r.Children.Select(c => c.Kind).Append(r.ListKind)).OfType<string>().Distinct();
        foreach (var language in LocalizationManager.Languages)
        {
            var strings = LocalizationManager.Load(language.Code)!;
            foreach (var rule in SpaceCatalog.Rules)
            {
                Assert.True(strings.ContainsKey($"space.{rule.Id}.name"), $"{language.Code}: space.{rule.Id}.name");
                Assert.True(strings.ContainsKey($"space.{rule.Id}.desc"), $"{language.Code}: space.{rule.Id}.desc");
            }
            foreach (var kind in kinds) Assert.True(strings.ContainsKey($"space.kind.{kind}.name"), $"{language.Code}: {kind}");
            foreach (var segment in Enum.GetValues<SpaceSegment>()) Assert.True(strings.ContainsKey($"disk.seg.{segment}"), $"{language.Code}: {segment}");
        }
    }

    [Fact]
    public async Task HermesIsSplitIntoWhatCanGoAndWhatIsTheAgent()
    {
        using var home = new FakeHome();
        home.File(".hermes/cache/uv/wheel.whl", 5000);
        home.File(".hermes/hermes-agent/.cache/x", 300);
        home.File(".hermes/hermes-agent/run.py", 700);
        home.File(".hermes/backups/pre-restore-1/home.tar.gz", 4000);
        home.File(".hermes/installs/env/lib.so", 9000);
        home.File(".hermes/state.db", 100);

        var report = await Analyze();
        var hermes = report.Items.Concat(report.Items.SelectMany(i => i.Children)).Single(e => e.Id == "hermes");
        Assert.Equal(19100, hermes.Bytes);

        SpaceEntry Part(string path) => hermes.Children.Single(c => c.Path == home.Home + "/.hermes/" + path);
        Assert.Equal(SpaceRisk.Safe, Part("cache").Risk);
        Assert.True(Part("cache").CanDelete);
        Assert.Equal(SpaceRisk.Safe, Part("hermes-agent/.cache").Risk);
        Assert.Equal(SpaceRisk.Careful, Part("backups").Risk);
        Assert.Equal(SpaceRisk.Keep, Part("installs").Risk);
        Assert.False(Part("installs").CanDelete);
        Assert.False(hermes.CanDelete);
    }

    [Fact]
    public async Task EveryByteIsCountedOnce()
    {
        using var home = new FakeHome();
        home.File(".cache/pip/http/a", 1000);                       // a cache target
        home.File(".cache/huggingface/hub/models--x--y/w.bin", 2000); // a known item inside ~/.cache
        home.File(".cache/someapp/blob", 300);                       // the rest of ~/.cache
        home.File("Documents/report.pdf", 400);                      // personal
        home.File(".weird/data", 500);                               // unknown
        home.File(".hermes/cache/x", 600);

        var report = await Analyze();
        var top = report.Items;
        // Everything under the fake home, once (the report also holds entries outside it: /usr, /var…).
        var leafs = top.SelectMany(e => e.Children.Count > 0 && e.Id is "caches" or "hermes" or "huggingface" ? [e] : e.Id.StartsWith("small:") ? e.Children : [e])
            .Where(e => e.Paths.All(p => p.StartsWith(home.Home, StringComparison.Ordinal)) || e.Id == "caches")
            .ToList();
        Assert.Equal(4800, leafs.Sum(e => e.Bytes));

        var models = top.Single(e => e.Id == "huggingface");
        Assert.Equal(SpaceSegment.Models, models.Segment);
        Assert.Equal("models--x--y", models.Children.Single().Name);
        Assert.Equal(2000, models.Bytes);

        var caches = top.Single(e => e.Id == "caches");
        Assert.Equal(1000, caches.Bytes);
        Assert.Contains(caches.Children, c => c.TargetId == "dev.pip");
        Assert.False(caches.Children.Single().CanDelete); // cleaned from the Targets page

        var all = Flatten(top).ToList();
        var documents = all.Single(e => e.Path == home.Home + "/Documents");
        Assert.Equal(SpaceSegment.Files, documents.Segment);
        Assert.Equal(SpaceRisk.Keep, documents.Risk);
        Assert.False(documents.CanDelete);

        var weird = all.Single(e => e.Path == home.Home + "/.weird");
        Assert.Equal(SpaceRisk.Careful, weird.Risk);
        Assert.True(weird.CanDelete);

        var restOfCache = all.Single(e => e.Path == home.Home + "/.cache");
        Assert.Equal(300, restOfCache.Bytes);
        Assert.False(restOfCache.CanDelete); // ~/.cache itself is protected
    }

    [Fact]
    public async Task RemovingAPartMovesItToTheTrash_AndRefusesKeepItems()
    {
        using var home = new FakeHome();
        home.File(".hermes/cache/uv/a.whl", 5000);
        home.File(".hermes/installs/env/lib.so", 9000);

        var report = await Analyze();
        var hermes = Flatten(report.Items).Single(e => e.Id == "hermes");
        var engine = new DiskMapEngine();

        var cache = hermes.Children.Single(c => c.Path.EndsWith("/cache", StringComparison.Ordinal));
        Assert.Equal(5000, engine.Remove(cache, useRecycleBin: true));
        Assert.False(Directory.Exists(home.Home + "/.hermes/cache"));
        Assert.True(File.Exists(home.Home + "/.local/share/Trash/files/cache/uv/a.whl"));

        var installs = hermes.Children.Single(c => c.Path.EndsWith("/installs", StringComparison.Ordinal));
        Assert.Equal(0, engine.Remove(installs, useRecycleBin: false));
        Assert.True(File.Exists(home.Home + "/.hermes/installs/env/lib.so"));
    }

    [Fact]
    public void MeasureSkipsLinksAndExcludedFolders()
    {
        using var home = new FakeHome();
        home.File("a/one", 10);
        home.File("a/skip/two", 20);
        home.File("Documents/big", 1000);
        Directory.CreateSymbolicLink(home.Home + "/a/docs", home.Home + "/Documents");

        var (bytes, _) = DiskMapEngine.Measure(home.Home + "/a", new HashSet<string> { home.Home + "/a/skip" }, CancellationToken.None);
        Assert.Equal(10, bytes);
    }
}
