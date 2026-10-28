using JunkCleanup.Core;

[assembly: CollectionBehavior(DisableTestParallelization = true)]

namespace JunkCleanup.Linux.Tests;

/// <summary>A temporary home folder that PathResolver sees as $HOME, with optional XDG variables. Removed on dispose.</summary>
internal sealed class FakeHome : IDisposable
{
    private readonly Func<string, string?> _previous;
    private readonly Dictionary<string, string> _env = new(StringComparer.Ordinal);

    public FakeHome()
    {
        var temp = Path.Combine(Path.GetTempPath(), "cc-home-" + Guid.NewGuid().ToString("N")[..8]);
        Directory.CreateDirectory(temp);
        Root = PathGuard.RealPath(temp); // macOS: /var → /private/var
        Home = Path.Combine(Root, "home", "user");
        Directory.CreateDirectory(Home);
        _env["HOME"] = Home;
        _previous = PathResolver.GetEnv;
        PathResolver.GetEnv = name => _env.TryGetValue(name, out var v) ? v : null;
    }

    /// <summary>The temp folder; Home is inside it (Root/home/user), so a "volume root" is around for tests.</summary>
    public string Root { get; }
    public string Home { get; }

    public void Set(string name, string value) => _env[name] = value;

    public string Dir(string relative)
    {
        var path = Path.Combine(Home, relative);
        Directory.CreateDirectory(path);
        return path;
    }

    public string File(string relative, int bytes = 100)
    {
        var path = Path.Combine(Home, relative);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        System.IO.File.WriteAllBytes(path, new byte[bytes]);
        return path;
    }

    public void Dispose()
    {
        PathResolver.GetEnv = _previous;
        try
        {
            foreach (var dir in Directory.EnumerateDirectories(Root, "*", SearchOption.AllDirectories))
                try { System.IO.File.SetUnixFileMode(dir, (UnixFileMode)0b111_000_000); } catch { }
            Directory.Delete(Root, recursive: true);
        }
        catch
        {
            // a temp folder left behind is harmless
        }
    }
}
