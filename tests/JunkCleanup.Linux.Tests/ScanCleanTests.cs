using JunkCleanup.Core;

namespace JunkCleanup.Linux.Tests;

/// <summary>The shared engines on Linux paths: what is scanned is what gets removed, and nothing else.</summary>
public sealed class ScanCleanTests
{
    private static CleanupTarget Target(string id) => TargetCatalog.All.Single(t => t.Id == id);

    [Fact]
    public async Task ScanFindsEveryFileAndGroupsByFirstLevel()
    {
        using var home = new FakeHome();
        home.File(".cache/pip/http-v2/a/1", 1000);
        home.File(".cache/pip/http-v2/b/2", 2000);
        home.File(".cache/pip/selfcheck.json", 10);

        var results = await new ScanEngine().ScanAsync([Target("dev.pip")], new ScanOptions(), null, CancellationToken.None);
        var scan = results[0];
        Assert.Equal(3010, scan.TotalBytes);
        Assert.Equal(3, scan.FileCount);
        var top = scan.TopEntries[0];
        Assert.Equal("http-v2", top.Name);
        Assert.True(top.IsDirectory);
        Assert.True(top.Complete);
        Assert.Equal(3000, top.Bytes);
    }

    [Fact]
    public void ScanDoesNotFollowSymlinkedFolders()
    {
        using var home = new FakeHome();
        home.File("Documents/thesis.pdf", 5000);
        home.File(".cache/pip/real", 1);
        Directory.CreateSymbolicLink(home.Home + "/.cache/pip/docs", home.Home + "/Documents");

        var scan = new ScanEngine().ScanTarget(Target("dev.pip"), new ScanOptions(), null, CancellationToken.None);
        Assert.Equal(1, scan.FileCount);
    }

    [Theory]
    [InlineData(true)]
    [InlineData(false)]
    public async Task CleanRemovesTheScannedFiles_AndNothingOutside(bool useTrash)
    {
        using var home = new FakeHome();
        home.File(".cache/pip/http-v2/a/1", 1000);
        home.File(".cache/pip/wheels/x.whl", 500);
        var keep = home.File("Documents/keep.txt", 7);
        var sibling = home.File(".cache/uv-not-scanned/file", 9);

        var scans = await new ScanEngine().ScanAsync([Target("dev.pip")], new ScanOptions(), null, CancellationToken.None);
        var report = await new CleanEngine().CleanAsync(scans, new CleanOptions { UseRecycleBin = useTrash }, null, CancellationToken.None);

        Assert.Equal(1500, report.BytesFreed);
        Assert.Equal(2, report.FilesDeleted);
        Assert.Equal(0, report.Failed);
        Assert.True(Directory.Exists(home.Home + "/.cache/pip")); // the root itself stays
        Assert.Empty(Directory.GetFileSystemEntries(home.Home + "/.cache/pip"));
        Assert.True(File.Exists(keep));
        Assert.True(File.Exists(sibling));

        var trashed = Directory.Exists(home.Home + "/.local/share/Trash/files")
            ? Directory.GetFileSystemEntries(home.Home + "/.local/share/Trash/files").Length
            : 0;
        Assert.Equal(useTrash ? 2 : 0, trashed); // two complete first-level folders, each one item
    }

    [Fact]
    public async Task RecentFilesAreSkippedWhereTheTargetAsksForIt()
    {
        using var home = new FakeHome();
        var old = home.File(".var/app/org.gimp.GIMP/cache/tmp/old", 10);
        File.SetLastWriteTimeUtc(old, DateTime.UtcNow.AddDays(-3));
        home.File(".var/app/org.gimp.GIMP/cache/tmp/fresh", 10);

        var scans = await new ScanEngine().ScanAsync([Target("app.flatpak")], new ScanOptions { SkipNewerThan = TimeSpan.FromHours(24) }, null, CancellationToken.None);
        Assert.Equal(1, scans[0].FileCount);
    }

    [Fact]
    public async Task RemoveEntryTakesOneFolderOut()
    {
        using var home = new FakeHome();
        home.File(".cache/JetBrains/IntelliJIdea2025.2/caches/a", 100);
        home.File(".cache/JetBrains/IntelliJIdea2025.2/log/b", 50);

        var scan = (await new ScanEngine().ScanAsync([Target("dev.jetbrains")], new ScanOptions(), null, CancellationToken.None))[0];
        var caches = scan.TopEntries.Single(e => e.Name == "caches");
        var result = new CleanEngine().RemoveEntry(scan, caches, new CleanOptions { UseRecycleBin = true });

        Assert.NotNull(result);
        Assert.Equal(100, result!.BytesFreed);
        Assert.Equal(50, scan.TotalBytes);
        Assert.True(File.Exists(home.Home + "/.cache/JetBrains/IntelliJIdea2025.2/log/b"));
        Assert.True(File.Exists(home.Home + "/.local/share/Trash/files/caches/a"));
    }

    [Fact]
    public async Task TheTrashTargetEmptiesTheHomeTrash()
    {
        using var home = new FakeHome();
        Assert.True(RecycleBinNative.MoveToTrash(home.File("old-download.iso", 4096)));

        var scans = await new ScanEngine().ScanAsync([Target("linux.trash")], new ScanOptions(), null, CancellationToken.None);
        Assert.Equal(4096, scans[0].TotalBytes);
        var report = await new CleanEngine().CleanAsync(scans, new CleanOptions(), null, CancellationToken.None);
        Assert.Equal(4096, report.BytesFreed);
        Assert.Empty(Directory.GetFileSystemEntries(home.Home + "/.local/share/Trash/files"));
    }
}
