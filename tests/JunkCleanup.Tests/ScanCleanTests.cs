using JunkCleanup.Core;

namespace JunkCleanup.Tests;

public class ScanCleanTests : IDisposable
{
    private readonly string _root = Path.Combine(Path.GetTempPath(), "JunkCleanupTests", Guid.NewGuid().ToString("N"));
    private readonly string _outside;

    public ScanCleanTests()
    {
        Directory.CreateDirectory(Path.Combine(_root, "a", "deep"));
        Directory.CreateDirectory(Path.Combine(_root, "b"));
        Directory.CreateDirectory(Path.Combine(_root, "empty"));
        File.WriteAllBytes(Path.Combine(_root, "top.bin"), new byte[1000]);
        File.WriteAllBytes(Path.Combine(_root, "a", "one.bin"), new byte[2000]);
        File.WriteAllBytes(Path.Combine(_root, "a", "deep", "two.bin"), new byte[3000]);
        File.WriteAllBytes(Path.Combine(_root, "b", "old.log"), new byte[4000]);
        File.SetLastWriteTimeUtc(Path.Combine(_root, "b", "old.log"), DateTime.UtcNow.AddDays(-10));

        _outside = Path.Combine(Path.GetTempPath(), "JunkCleanupTests", "outside-" + Guid.NewGuid().ToString("N") + ".bin");
        File.WriteAllBytes(_outside, new byte[10]);
    }

    private CleanupTarget Target(bool ageFilter = false, string[]? patterns = null) => new()
    {
        Id = "test",
        Category = TargetCategory.Custom,
        Glyph = "x",
        RootPatterns = [_root],
        FilePatterns = patterns ?? ["*"],
        RespectsAgeFilter = ageFilter,
    };

    [Fact]
    public void Keep_newest_offers_every_build_but_the_newest_version()
    {
        foreach (var v in new[] { "2.1.9", "2.1.308", "2.1.309" }) Directory.CreateDirectory(Path.Combine(_root, "builds", v));
        var target = new CleanupTarget
        {
            Id = "test", Category = TargetCategory.Custom, Glyph = "x", KeepNewest = true,
            RootPatterns = [Path.Combine(_root, "builds", "*")],
        };

        var offered = target.ResolveRoots().Select(Path.GetFileName).Order().ToArray();

        Assert.Equal(["2.1.308", "2.1.9"], offered);
    }

    [Fact]
    public void Scan_counts_every_file_and_groups_by_first_level_entry()
    {
        var result = new ScanEngine().ScanTarget(Target(), new ScanOptions(), null, CancellationToken.None);

        Assert.Null(result.Error);
        Assert.False(result.AccessDenied);
        Assert.Equal(4, result.FileCount);
        Assert.Equal(10000, result.TotalBytes);

        var groups = result.TopEntries.ToDictionary(e => e.Name, e => e);
        Assert.Equal(5000, groups["a"].Bytes);
        Assert.Equal(2, groups["a"].Files);
        Assert.True(groups["a"].IsDirectory);
        Assert.Equal(1000, groups["top.bin"].Bytes);
        Assert.False(groups["top.bin"].IsDirectory);
        Assert.Equal("a", result.TopEntries[0].Name); // sorted by size, descending
    }

    [Fact]
    public void Age_filter_skips_recent_files_only_for_targets_that_opt_in()
    {
        var options = new ScanOptions { SkipNewerThan = TimeSpan.FromDays(1) };
        var engine = new ScanEngine();

        var filtered = engine.ScanTarget(Target(ageFilter: true), options, null, CancellationToken.None);
        Assert.Equal(1, filtered.FileCount);
        Assert.Equal(4000, filtered.TotalBytes);

        var unfiltered = engine.ScanTarget(Target(ageFilter: false), options, null, CancellationToken.None);
        Assert.Equal(4, unfiltered.FileCount);
    }

    [Fact]
    public void File_patterns_restrict_matches()
    {
        var result = new ScanEngine().ScanTarget(Target(patterns: ["*.log"]), new ScanOptions(), null, CancellationToken.None);
        Assert.Equal(1, result.FileCount);
    }

    [Fact]
    public void Progress_reports_bytes_found()
    {
        long reported = 0;
        new ScanEngine().ScanTarget(Target(), new ScanOptions(), b => reported += b, CancellationToken.None);
        Assert.Equal(10000, reported);
    }

    [Fact]
    public async Task Parallel_scan_reports_completion_per_target()
    {
        var phases = new List<ScanPhase>();
        var progress = new SynchronousProgress<ScanProgress>(p => phases.Add(p.Phase));
        var results = await new ScanEngine().ScanAsync([Target()], new ScanOptions(), progress, CancellationToken.None);

        Assert.Single(results);
        Assert.Contains(ScanPhase.Started, phases);
        Assert.Contains(ScanPhase.Completed, phases);
    }

    [Fact]
    public void Permanent_clean_deletes_files_and_prunes_empty_folders_but_keeps_root()
    {
        var scan = new ScanEngine().ScanTarget(Target(), new ScanOptions(), null, CancellationToken.None);
        var clean = new CleanEngine().CleanTarget(scan, new CleanOptions { UseRecycleBin = false }, null, CancellationToken.None);

        Assert.Equal(4, clean.FilesDeleted);
        Assert.Equal(0, clean.Failed);
        Assert.Equal(10000, clean.BytesFreed);
        Assert.True(Directory.Exists(_root));
        Assert.Empty(Directory.EnumerateFileSystemEntries(_root));
    }

    [Fact]
    public void Dry_run_touches_nothing()
    {
        var scan = new ScanEngine().ScanTarget(Target(), new ScanOptions(), null, CancellationToken.None);
        var clean = new CleanEngine().CleanTarget(scan, new CleanOptions { UseRecycleBin = false, DryRun = true }, null, CancellationToken.None);

        Assert.Equal(10000, clean.BytesFreed);
        Assert.Equal(4, Directory.EnumerateFiles(_root, "*", SearchOption.AllDirectories).Count());
    }

    [Fact]
    public void Files_outside_the_scanned_roots_are_refused_even_if_listed()
    {
        var scan = new ScanEngine().ScanTarget(Target(), new ScanOptions(), null, CancellationToken.None);
        scan.Files.Add(new FileEntry(_outside, 10));

        var clean = new CleanEngine().CleanTarget(scan, new CleanOptions { UseRecycleBin = false }, null, CancellationToken.None);

        Assert.Equal(1, clean.Failed);
        Assert.True(File.Exists(_outside));
    }

    [Fact]
    public void Locked_files_are_reported_as_failed_not_thrown()
    {
        var scan = new ScanEngine().ScanTarget(Target(), new ScanOptions(), null, CancellationToken.None);
        using var hold = new FileStream(Path.Combine(_root, "top.bin"), FileMode.Open, FileAccess.Read, FileShare.None);

        var clean = new CleanEngine().CleanTarget(scan, new CleanOptions { UseRecycleBin = false }, null, CancellationToken.None);

        Assert.Equal(3, clean.FilesDeleted);
        Assert.Equal(1, clean.Failed);
        Assert.Equal(1000, clean.BytesRemaining);
        Assert.Null(clean.Error);
    }

    [Fact]
    public void A_picked_entry_is_removed_alone_and_leaves_the_scan()
    {
        var scan = new ScanEngine().ScanTarget(Target(), new ScanOptions(), null, CancellationToken.None);
        var a = scan.TopEntries.Single(e => e.Name == "a");

        var result = new CleanEngine().RemoveEntry(scan, a, new CleanOptions { UseRecycleBin = false });

        Assert.NotNull(result);
        Assert.Equal(5000, result!.BytesFreed);
        Assert.Equal(2, result.FilesDeleted);
        Assert.False(Directory.Exists(Path.Combine(_root, "a")));
        Assert.True(File.Exists(Path.Combine(_root, "b", "old.log")));
        Assert.Equal(5000, scan.TotalBytes);
        Assert.DoesNotContain(scan.TopEntries, e => e.Name == "a");
    }

    [Fact]
    public void An_entry_outside_the_scanned_roots_is_refused()
    {
        var scan = new ScanEngine().ScanTarget(Target(), new ScanOptions(), null, CancellationToken.None);
        var outsider = new EntrySummary(_outside, "outside", false, 10, 1);

        Assert.Null(new CleanEngine().RemoveEntry(scan, outsider, new CleanOptions { UseRecycleBin = false }));
        Assert.True(File.Exists(_outside));
    }

    public void Dispose()
    {
        try { Directory.Delete(_root, true); } catch { /* best effort */ }
        try { File.Delete(_outside); } catch { /* best effort */ }
    }

    private sealed class SynchronousProgress<T>(Action<T> handler) : IProgress<T>
    {
        public void Report(T value) => handler(value);
    }
}
