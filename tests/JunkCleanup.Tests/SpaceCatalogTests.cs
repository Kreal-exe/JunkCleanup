using JunkCleanup.Core;
using JunkCleanup.Localization;

namespace JunkCleanup.Tests;

public class SpaceCatalogTests
{
    [Fact]
    public void Every_rule_has_a_name_and_description_in_every_language()
    {
        var kinds = SpaceCatalog.Rules.SelectMany(r => r.Children.Select(c => c.Kind).Append(r.ListKind)).OfType<string>().Distinct().ToList();
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
    public void Ids_are_unique_and_every_rule_has_a_place_and_an_icon()
    {
        Assert.Equal(SpaceCatalog.Rules.Count, SpaceCatalog.Rules.Select(r => r.Id).Distinct().Count());
        foreach (var rule in SpaceCatalog.Rules)
        {
            Assert.NotEmpty(rule.Paths);
            Assert.False(string.IsNullOrEmpty(rule.Glyph), rule.Id);
        }
    }

    [Fact]
    public void Hermes_parts_that_are_the_agent_are_kept()
    {
        var hermes = SpaceCatalog.Rules.Single(r => r.Id == "hermes");
        Assert.Equal(SpaceRisk.Keep, hermes.Risk);
        Assert.All(hermes.Children.Where(c => c.Kind == "app"), c => Assert.Equal(SpaceRisk.Keep, c.Risk));
        Assert.All(hermes.Children.Where(c => c.Kind == "cache"), c => Assert.Equal(SpaceRisk.Safe, c.Risk));
    }

    [Fact]
    public void Protected_folders_are_never_offered_for_removal()
    {
        var profile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        var entry = new SpaceEntry { Id = "folder:" + profile, Segment = SpaceSegment.Other, Risk = SpaceRisk.Careful, Glyph = "", Paths = [profile] };
        Assert.False(entry.CanDelete);
    }

    [Fact]
    public void Another_drive_is_mapped_from_its_root_with_only_what_lives_on_it()
    {
        var home = SpaceCatalog.HomeDrive;
        var other = home.StartsWith("Z", StringComparison.OrdinalIgnoreCase) ? @"Y:\" : @"Z:\";
        var scope = SpaceCatalog.Scope(other);
        Assert.Equal(other, scope.VolumePath);
        Assert.Equal(other, Assert.Single(scope.Roots).Pattern);
        Assert.False(scope.Includes!(Path.Combine(home, "Users")));
        Assert.True(scope.Includes!(Path.Combine(other, "Games")));
        Assert.Contains("$Recycle.Bin", scope.KeepNames);
    }

    [Fact]
    public void The_home_drive_keeps_the_profile_scope()
    {
        var scope = SpaceCatalog.Scope(SpaceCatalog.HomeDrive);
        Assert.Equal(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), scope.VolumePath);
        Assert.True(scope.Includes!(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData)));
        Assert.Equal(scope.Roots, SpaceCatalog.Scope().Roots);
        Assert.Equal(SpaceCatalog.HomeDrive, scope.Roots[^1].Pattern);
    }

    [Fact]
    public async Task Folders_at_a_drive_root_are_the_users_own_files()
    {
        var root = Directory.CreateTempSubdirectory("jc-drive-").FullName;
        try
        {
            Directory.CreateDirectory(Path.Combine(root, "other"));
            File.WriteAllBytes(Path.Combine(root, "other", "photo.jpg"), new byte[4096]);
            Directory.CreateDirectory(Path.Combine(root, ".tool"));
            File.WriteAllBytes(Path.Combine(root, ".tool", "state.db"), new byte[4096]);
            Directory.CreateDirectory(Path.Combine(root, "Program Files"));
            File.WriteAllBytes(Path.Combine(root, "Program Files", "app.exe"), new byte[4096]);
            var scope = new SpaceScope
            {
                Rules = [], Roots = [(root, SpaceSegment.Files)], VolumePath = root,
                Filed = [(Path.Combine(root, "Program Files"), SpaceSegment.Apps)], KeepNames = ["Program Files"],
                Glyphs = ("f", "p", "c"),
            };
            var report = await new DiskMapEngine().AnalyzeAsync(scope, [], null, CancellationToken.None);
            var all = report.Items.SelectMany(i => i.Children.Prepend(i)).ToList();

            var mine = all.Single(e => e.Name == "other");
            Assert.Equal(SpaceSegment.Files, mine.Segment);
            Assert.Equal(SpaceRisk.Keep, mine.Risk);
            Assert.Equal("space.personal", mine.Key);
            Assert.False(mine.CanDelete);

            var tool = all.Single(e => e.Name == ".tool");
            Assert.Equal(SpaceSegment.Other, tool.Segment);
            Assert.Equal("space.folder", tool.Key);

            var apps = all.Single(e => e.Name == "Program Files");
            Assert.Equal(SpaceSegment.Apps, apps.Segment);
            Assert.Equal("space.folder", apps.Key);
            Assert.False(apps.CanDelete);
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }
}
