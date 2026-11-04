namespace JunkCleanup.Core;

/// <summary>
/// Build output and installed dependencies of projects nobody has touched for a while: node_modules, Rust and Maven
/// target, Python virtual environments, Gradle build, .NET bin and obj… A project is recognised by its own file
/// (package.json, Cargo.toml…), and only the folders that file's tool rebuilds are offered. A project with a file
/// changed in the last <see cref="Idle"/> is being worked on and left alone.
/// </summary>
public static class ProjectArtifacts
{
    public static readonly TimeSpan Idle = TimeSpan.FromDays(30);

    /// <summary>How deep under a projects folder a project is looked for.</summary>
    private const int MaxDepth = 5;

    /// <summary>Files read to decide whether a project is in use; enough to see recent work in any real project.</summary>
    private const int ActivityBudget = 4000;

    /// <summary>Folders under the home folder where projects usually live.</summary>
    public static readonly string[] SearchFolders =
    [
        "Code", "code", "Projects", "projects", "Developer", "dev", "Dev", "src", "repos", "git", "GitHub", "Sites",
        Path.Combine("source", "repos"),
        Path.Combine("Documents", "Code"), Path.Combine("Documents", "Projects"), Path.Combine("Documents", "GitHub"),
        Path.Combine("Documents", "Developer"),
    ];

    private sealed record Kind(Func<IReadOnlySet<string>, bool> IsProject, string[] Folders);

    private static bool Has(IReadOnlySet<string> files, params string[] names) => names.Any(files.Contains);

    private static readonly Kind[] Kinds =
    [
        new(f => Has(f, "package.json"), ["node_modules", ".next", ".nuxt", ".turbo", ".parcel-cache", ".svelte-kit", ".angular"]),
        new(f => Has(f, "Cargo.toml"), ["target"]),
        new(f => Has(f, "pom.xml"), ["target"]),
        new(f => Has(f, "build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts"), ["build", ".gradle"]),
        new(f => Has(f, "pyproject.toml", "requirements.txt", "setup.py", "Pipfile"),
            [".venv", "venv", ".tox", ".nox", ".pytest_cache", ".mypy_cache", ".ruff_cache", "__pycache__"]),
        new(f => f.Any(n => n.EndsWith(".csproj", StringComparison.OrdinalIgnoreCase) || n.EndsWith(".fsproj", StringComparison.OrdinalIgnoreCase)), ["bin", "obj"]),
        new(f => Has(f, "pubspec.yaml"), [".dart_tool", "build"]),
        new(f => Has(f, "Package.swift"), [".build"]),
        new(f => Has(f, "mix.exs"), ["_build", "deps"]),
    ];

    /// <summary>Every folder name that is some tool's output: never searched for projects, never read for activity.</summary>
    private static readonly HashSet<string> AllArtifactNames = Kinds.SelectMany(k => k.Folders).ToHashSet(StringComparer.Ordinal);

    private static readonly object Gate = new();
    private static (string Home, DateTime At, IReadOnlyList<string> Found)? _last;

    /// <summary>
    /// The artifact folders of idle projects under the usual projects folders of <paramref name="home"/>. The answer is
    /// kept for a few seconds: a scan resolves every target's roots more than once.
    /// </summary>
    public static IReadOnlyList<string> Find(string home)
    {
        if (string.IsNullOrEmpty(home)) return [];
        lock (Gate)
        {
            if (_last is { } last && last.Home == home && DateTime.UtcNow - last.At < TimeSpan.FromSeconds(20)) return last.Found;
            var found = Find(SearchFolders.Select(f => Path.Combine(home, f)), DateTime.UtcNow - Idle);
            _last = (home, DateTime.UtcNow, found);
            return found;
        }
    }

    internal static IReadOnlyList<string> Find(IEnumerable<string> searchRoots, DateTime idleSince)
    {
        var found = new List<string>();
        var seen = new HashSet<string>(PathGuard.Comparer);
        var queue = new Queue<(string Dir, int Depth)>();
        foreach (var root in searchRoots)
        {
            if (!Directory.Exists(root) || IsLink(root)) continue;
            string full;
            try { full = PathGuard.Normalize(root); } catch { continue; }
            // "code" and "Code" are one folder where names ignore case.
            if (seen.Add(full)) queue.Enqueue((full, 0));
        }

        while (queue.Count > 0)
        {
            var (dir, depth) = queue.Dequeue();
            var (files, folders) = List(dir);

            var artifacts = new List<string>();
            foreach (var kind in Kinds)
            {
                if (!kind.IsProject(files)) continue;
                foreach (var name in kind.Folders)
                    if (folders.Contains(name) && IsArtifact(dir, name) && !artifacts.Contains(name)) artifacts.Add(name);
            }
            if (artifacts.Count > 0 && LastActivity(dir) < idleSince)
                found.AddRange(artifacts.Select(a => Path.Combine(dir, a)));

            if (depth >= MaxDepth) continue;
            foreach (var name in folders)
            {
                if (name.StartsWith('.') || AllArtifactNames.Contains(name)) continue;
                var sub = Path.Combine(dir, name);
                if (!IsLink(sub) && seen.Add(sub)) queue.Enqueue((sub, depth + 1));
            }
        }
        return found;
    }

    /// <summary>A generic name ("venv", "build") counts only when it holds what the tool puts there.</summary>
    private static bool IsArtifact(string project, string name) => name switch
    {
        "venv" or ".venv" => File.Exists(Path.Combine(project, name, "pyvenv.cfg")),
        _ => !IsLink(Path.Combine(project, name)),
    };

    /// <summary>When anything in the project other than its tools' output last changed (its own files and git index).</summary>
    internal static DateTime LastActivity(string project)
    {
        var newest = DateTime.MinValue;
        var budget = ActivityBudget;
        var stack = new Stack<(string Dir, int Depth)>();
        stack.Push((project, 0));
        try
        {
            var index = new FileInfo(Path.Combine(project, ".git", "index"));
            if (index.Exists) newest = index.LastWriteTimeUtc;
        }
        catch
        {
            // no git, or unreadable
        }

        while (stack.Count > 0 && budget > 0)
        {
            var (dir, depth) = stack.Pop();
            try
            {
                foreach (var info in new DirectoryInfo(dir).EnumerateFileSystemInfos("*", Options))
                {
                    if (--budget <= 0) break;
                    if (info is DirectoryInfo d)
                    {
                        if (depth < 3 && !d.Name.StartsWith('.') && !AllArtifactNames.Contains(d.Name)) stack.Push((d.FullName, depth + 1));
                    }
                    else if (info.LastWriteTimeUtc > newest)
                    {
                        newest = info.LastWriteTimeUtc;
                    }
                }
            }
            catch
            {
                // unreadable part: judge by the rest
            }
        }
        // A project that could not be read at all counts as in use.
        return newest == DateTime.MinValue ? DateTime.MaxValue : newest;
    }

    private static readonly EnumerationOptions Options = new()
    {
        IgnoreInaccessible = true, AttributesToSkip = FileAttributes.ReparsePoint, ReturnSpecialDirectories = false,
    };

    private static (HashSet<string> Files, HashSet<string> Folders) List(string dir)
    {
        var files = new HashSet<string>(StringComparer.Ordinal);
        var folders = new HashSet<string>(StringComparer.Ordinal);
        try
        {
            foreach (var info in new DirectoryInfo(dir).EnumerateFileSystemInfos("*", Options))
                (info is DirectoryInfo ? folders : files).Add(info.Name);
        }
        catch
        {
            // unreadable folder: nothing to offer from it
        }
        return (files, folders);
    }

    private static bool IsLink(string path)
    {
        try
        {
            return (File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0;
        }
        catch
        {
            return true;
        }
    }
}
