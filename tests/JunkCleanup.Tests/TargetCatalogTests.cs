using JunkCleanup.Core;
using JunkCleanup.Localization;

namespace JunkCleanup.Tests;

public class TargetCatalogTests
{
    [Fact]
    public void Ids_are_unique()
    {
        var ids = TargetCatalog.All.Select(t => t.Id).ToList();
        Assert.Equal(ids.Count, ids.Distinct(StringComparer.Ordinal).Count());
    }

    [Fact]
    public void Every_target_has_english_name_and_description()
    {
        var en = LocalizationManager.Load("en")!;
        foreach (var t in TargetCatalog.All)
        {
            Assert.True(en.ContainsKey(t.NameKey), $"missing {t.NameKey}");
            Assert.True(en.ContainsKey(t.DescriptionKey), $"missing {t.DescriptionKey}");
        }
    }

    [Fact]
    public void File_targets_declare_roots_and_patterns()
    {
        foreach (var t in TargetCatalog.All.Where(t => t.Kind == TargetKind.Files))
        {
            Assert.NotEmpty(t.RootPatterns);
            Assert.NotEmpty(t.FilePatterns);
            Assert.All(t.RootPatterns, p => Assert.False(string.IsNullOrWhiteSpace(p)));
        }
    }

    [Fact]
    public void Resolved_roots_never_overlap_between_targets()
    {
        // Two targets counting the same files would double-count and double-delete.
        var resolved = TargetCatalog.All
            .Where(t => t.Kind == TargetKind.Files)
            .SelectMany(t => t.ResolveRoots().Select(r => (t.Id, Root: PathGuard.Normalize(r))))
            .ToList();

        foreach (var a in resolved)
        foreach (var b in resolved)
        {
            if (a.Id == b.Id) continue;
            var overlaps = a.Root.Equals(b.Root, StringComparison.OrdinalIgnoreCase) || PathGuard.IsInside(a.Root, [b.Root]);
            Assert.False(overlaps, $"{a.Id} ({a.Root}) overlaps {b.Id} ({b.Root})");
        }
    }

    [Fact]
    public void Resolved_roots_are_never_protected_locations()
    {
        foreach (var t in TargetCatalog.All.Where(t => t.Kind == TargetKind.Files))
            Assert.All(t.ResolveRoots(), r => Assert.True(PathGuard.IsAllowedRoot(r), $"{t.Id}: {r}"));
    }

    [Fact]
    public void Custom_target_is_moderate_and_named_after_folder()
    {
        var t = TargetCatalog.CreateCustom(@"C:\Some\Folder\MyCache\");
        Assert.Equal(TargetCategory.Custom, t.Category);
        Assert.Equal(RiskLevel.Moderate, t.Risk);
        Assert.Equal("MyCache", t.DisplayName);
        Assert.StartsWith("custom:", t.Id);
        Assert.Equal(TargetCatalog.CreateCustom(@"c:\some\folder\mycache").Id, t.Id);
    }
}
