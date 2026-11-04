using JunkCleanup.Core;

namespace JunkCleanup.Linux.Tests;

public sealed class ProjectArtifactsTests : IDisposable
{
    private readonly string _root = Path.Combine(Path.GetTempPath(), "jc-projects-" + Guid.NewGuid().ToString("N"));
    private static readonly DateTime Old = DateTime.UtcNow.AddDays(-90);

    public void Dispose()
    {
        try { Directory.Delete(_root, true); } catch { /* best effort */ }
    }

    private string File(string relative, DateTime? written = null)
    {
        var path = Path.Combine(_root, relative);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        System.IO.File.WriteAllText(path, "x");
        System.IO.File.SetLastWriteTimeUtc(path, written ?? Old);
        return path;
    }

    private IReadOnlyList<string> Find() => ProjectArtifacts.Find([_root], DateTime.UtcNow - ProjectArtifacts.Idle);

    [Fact]
    public void IdleProjectsOfferTheirToolsOutputOnly()
    {
        File("web/package.json");
        File("web/index.js");
        File("web/node_modules/left-pad/index.js");
        File("web/.next/cache/a");
        File("rust/Cargo.toml");
        File("rust/target/debug/app");
        File("py/pyproject.toml");
        File("py/.venv/pyvenv.cfg");
        File("py/venv/notes.txt"); // not a virtual environment
        File("plain/target/keep.txt"); // no project file: not a build folder

        var found = Find().Select(p => Path.GetRelativePath(_root, p)).Order().ToList();
        Assert.Equal(["py/.venv", "rust/target", "web/.next", "web/node_modules"], found);
    }

    [Fact]
    public void ProjectsInUseAndNestedDependenciesAreLeftAlone()
    {
        File("active/package.json");
        File("active/src/app.ts", DateTime.UtcNow.AddDays(-2));
        File("active/node_modules/x/index.js");
        File("old/package.json");
        File("old/node_modules/dep/package.json");
        File("old/node_modules/dep/node_modules/inner/index.js");

        var found = Find().Select(p => Path.GetRelativePath(_root, p)).ToList();
        Assert.Equal(["old/node_modules"], found);
    }
}
