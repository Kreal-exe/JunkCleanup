using JunkCleanup.Core;

namespace JunkCleanup.Linux.Tests;

public sealed class TrashTests
{
    [Fact]
    public void MovesAFileIntoTheHomeTrashWithItsTrashInfo()
    {
        using var home = new FakeHome();
        var file = home.File(".cache/pip/my file ü.whl", 1234);

        Assert.True(RecycleBinNative.MoveToTrash(file));

        Assert.False(File.Exists(file));
        var trash = home.Home + "/.local/share/Trash";
        Assert.Equal(1234, new FileInfo(trash + "/files/my file ü.whl").Length);
        var info = File.ReadAllLines(trash + "/info/my file ü.whl.trashinfo");
        Assert.Equal("[Trash Info]", info[0]);
        Assert.Equal("Path=" + RecycleBinNative.EncodePath(file), info[1]);
        Assert.Contains("%20", info[1]);
        Assert.Contains("%C3%BC", info[1]);
        Assert.Matches(@"^DeletionDate=\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d$", info[2]);
    }

    [Fact]
    public void NameClashesGetANumberAndKeepTheExtension()
    {
        using var home = new FakeHome();
        var a = home.File(".cache/a/data.bin");
        var b = home.File(".cache/b/data.bin");
        var c = home.File(".cache/c/data.bin");

        Assert.Equal(0, RecycleBinNative.MoveToRecycleBin([a, b, c]));
        var files = Directory.GetFiles(home.Home + "/.local/share/Trash/files").Select(Path.GetFileName).Order().ToList();
        Assert.Equal(["data.2.bin", "data.3.bin", "data.bin"], files);
        Assert.Equal(3, Directory.GetFiles(home.Home + "/.local/share/Trash/info").Length);
    }

    [Fact]
    public void MovesAWholeFolderAsOneItem()
    {
        using var home = new FakeHome();
        home.File(".cache/pip/http/1/a", 10);
        home.File(".cache/pip/http/2/b", 20);

        Assert.True(RecycleBinNative.MoveToTrash(home.Home + "/.cache/pip/http"));
        Assert.False(Directory.Exists(home.Home + "/.cache/pip/http"));
        var (bytes, items) = RecycleBinNative.Query();
        Assert.Equal(30, bytes);
        Assert.Equal(1, items);
    }

    [Fact]
    public void HonoursXdgDataHome()
    {
        using var home = new FakeHome();
        var data = Path.Combine(home.Root, "xdg-data");
        Directory.CreateDirectory(data);
        home.Set("XDG_DATA_HOME", data);
        var file = home.File(".cache/x/y");
        Assert.True(RecycleBinNative.MoveToTrash(file));
        Assert.True(File.Exists(data + "/Trash/files/y"));
    }

    [Fact]
    public void NeverTrashesTheTrashOrMissingItems()
    {
        using var home = new FakeHome();
        var inTrash = home.File(".local/share/Trash/files/old");
        Assert.False(RecycleBinNative.MoveToTrash(inTrash));
        Assert.False(RecycleBinNative.MoveToTrash(home.Home + "/.local/share/Trash"));
        Assert.False(RecycleBinNative.MoveToTrash(home.Home + "/does/not/exist"));
        Assert.True(File.Exists(inTrash));
    }

    [Fact]
    public void ASymlinkIsTrashedItself_NotItsTarget()
    {
        using var home = new FakeHome();
        var precious = home.File("Documents/precious.txt");
        home.Dir(".cache/app");
        var link = home.Home + "/.cache/app/link";
        File.CreateSymbolicLink(link, precious);

        Assert.True(RecycleBinNative.MoveToTrash(link));
        Assert.True(File.Exists(precious));
        Assert.NotNull(new FileInfo(home.Home + "/.local/share/Trash/files/link").LinkTarget);
    }

    [Fact]
    public void EmptyRemovesEverything_IncludingReadOnlyFolders()
    {
        using var home = new FakeHome();
        home.File(".cache/go/mod/pkg@v1/a.go", 50);
        File.SetUnixFileMode(home.Home + "/.cache/go/mod/pkg@v1", UnixFileMode.UserRead | UnixFileMode.UserExecute);
        Assert.True(RecycleBinNative.MoveToTrash(home.Home + "/.cache/go/mod"));
        Assert.True(RecycleBinNative.MoveToTrash(home.File(".cache/z")));

        Assert.True(RecycleBinNative.Empty());
        Assert.Equal((0L, 0L), RecycleBinNative.Query());
        Assert.Empty(Directory.GetFileSystemEntries(home.Home + "/.local/share/Trash/info"));
    }

    [Fact]
    public void ReadsEscapedMountPoints() =>
        Assert.Equal("/media/user/My Disk", RecycleBinNative.UnescapeMount(@"/media/user/My\040Disk"));
}
