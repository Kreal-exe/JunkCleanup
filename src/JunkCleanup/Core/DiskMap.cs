using System.Diagnostics;

namespace JunkCleanup.Core;

/// <summary>Where the space on a disk goes, in the bands of the Disk page's bar.</summary>
public enum SpaceSegment { System, Apps, Caches, Developer, Models, VirtualMachines, Files, Other }

/// <summary>How safe removing an item is. <see cref="Keep"/> items are only shown, never removed by the app.</summary>
public enum SpaceRisk { Safe, Moderate, Careful, Keep }

/// <summary>
/// A part of a known item, relative to it: <c>new("cache", "cache", SpaceRisk.Safe)</c>. The kind names the strings
/// <c>space.kind.{Kind}.name / .desc</c>; the pattern may hold <c>*</c> segments.
/// </summary>
public sealed record SpaceChildRule(string Kind, string Pattern, SpaceRisk Risk);

/// <summary>
/// A known space consumer (an AI agent's folder, model downloads, emulator images, virtual machines…): where it lives,
/// which band it belongs to, and which of its parts are safe to remove. Names live in the localization files under
/// <c>space.{Id}.name</c> / <c>space.{Id}.desc</c>.
/// </summary>
public sealed class SpaceRule
{
    public required string Id { get; init; }
    public required SpaceSegment Segment { get; init; }
    public required string Glyph { get; init; }

    /// <summary>Folder or file patterns, resolved like a target's roots.</summary>
    public string[] Paths { get; init; } = [];

    /// <summary>Risk of the item as a whole (and of its listed subfolders).</summary>
    public SpaceRisk Risk { get; init; } = SpaceRisk.Keep;

    /// <summary>A command that removes it when the app cannot (it belongs to root, a tool manages it).</summary>
    public string? Command { get; init; }

    public SpaceChildRule[] Children { get; init; } = [];

    /// <summary>Each subfolder becomes a child of this kind, named after the folder (one per model, VM, image…).</summary>
    public string? ListKind { get; init; }
}

public sealed class SpaceEntry
{
    public required string Id { get; init; }
    public required SpaceSegment Segment { get; init; }
    public required SpaceRisk Risk { get; init; }
    public required string Glyph { get; init; }

    /// <summary>The string key prefix ("space.hermes", "space.kind.cache"); null when <see cref="Name"/> is literal.</summary>
    public string? Key { get; init; }

    /// <summary>A literal name (a folder name) for discovered folders and listed children.</summary>
    public string? Name { get; init; }

    public IReadOnlyList<string> Paths { get; init; } = [];
    public string? Command { get; init; }

    /// <summary>A whole cache target found by the cleaner: removed from the Targets page, not here.</summary>
    public string? TargetId { get; init; }

    public long Bytes { get; set; }
    public bool Unreadable { get; set; }
    public List<SpaceEntry> Children { get; } = [];

    public string Path => Paths.Count > 0 ? Paths[0] : string.Empty;

    /// <summary>One folder or file, not Keep, no command, not a cache target, and not a protected location.</summary>
    public bool CanDelete => Risk != SpaceRisk.Keep && Command is null && TargetId is null && Paths.Count == 1 && PathGuard.IsAllowedRoot(Paths[0]);
}

public sealed class SpaceReport
{
    public string VolumeName { get; init; } = string.Empty;
    public long Total { get; init; }
    public long Free { get; init; }
    public long Used => Math.Max(0, Total - Free);
    public List<SpaceEntry> Items { get; } = [];
    public Dictionary<SpaceSegment, long> Segments { get; } = [];
    public TimeSpan Elapsed { get; set; }
    public long Measured => Items.Sum(i => i.Bytes);
}

/// <summary>What a platform contributes: its known items, the folders to look through and how to file what is found.</summary>
public sealed class SpaceScope
{
    public required IReadOnlyList<SpaceRule> Rules { get; init; }

    /// <summary>Folders whose subfolders are each measured as an item (the home folder, Applications, Program Files…).</summary>
    public required IReadOnlyList<(string Pattern, SpaceSegment Segment)> Roots { get; init; }

    /// <summary>Discovered folders that are only containers: each of their subfolders is listed as a child.</summary>
    public IReadOnlyList<string> Containers { get; init; } = [];

    /// <summary>Discovered folders that belong to a band other than their root's (~/.local → Apps, AppData → Apps).</summary>
    public IReadOnlyList<(string Pattern, SpaceSegment Segment)> Filed { get; init; } = [];

    /// <summary>
    /// Discovered folders that are only shown, never offered for removal: browser profiles, keychains, the OS vendor's
    /// app data. Removing them loses passwords, history or settings, not space worth having.
    /// </summary>
    public IReadOnlyList<string> KeepNames { get; init; } = [];

    /// <summary>Folder names inside the roots that are the user's own files (Documents, Music…).</summary>
    public IReadOnlyList<string> PersonalFolders { get; init; } = [];

    /// <summary>Path of the volume to report on (the one holding the home folder).</summary>
    public required string VolumePath { get; init; }

    /// <summary>
    /// Which known items and cache targets belong to the report: on Windows, only those on the drive being mapped, so a
    /// cache on D: is not counted into C:. Null takes them all.
    /// </summary>
    public Func<string, bool>? Includes { get; init; }

    /// <summary>Icons in the platform's icon set: a discovered folder, a personal folder, the cleanable caches.</summary>
    public required (string Folder, string Personal, string Caches) Glyphs { get; init; }
}

/// <summary>
/// Measures the disk: every known item (with its parts), every cache target, and every other folder under the scope's
/// roots, each byte counted once. What is used but was not measured (the system, swap, unreadable places) becomes the
/// System band.
/// </summary>
public sealed class DiskMapEngine
{
    /// <summary>Discovered folders smaller than this are folded into one "other" entry.</summary>
    public const long SmallFolder = 64L * 1024 * 1024;

    public async Task<SpaceReport> AnalyzeAsync(SpaceScope scope, IReadOnlyList<CleanupTarget> targets, IProgress<string>? progress, CancellationToken ct)
    {
        var sw = Stopwatch.StartNew();
        var (volumeName, total, free) = Volume(scope.VolumePath);
        var report = new SpaceReport { VolumeName = volumeName, Total = total, Free = free };

        var entries = new List<SpaceEntry>();
        var claimed = new HashSet<string>(PathGuard.Comparer);

        // 1. Known items and their parts.
        foreach (var rule in scope.Rules)
        {
            var paths = rule.Paths.SelectMany(PathResolver.Expand).Distinct(PathGuard.Comparer)
                .Where(p => scope.Includes?.Invoke(p) != false)
                .Where(p => !claimed.Contains(p) && !claimed.Any(c => PathGuard.IsInside(p, [c]))).ToList();
            if (paths.Count == 0) continue;
            foreach (var p in paths) claimed.Add(p);

            var entry = new SpaceEntry
            {
                Id = rule.Id, Segment = rule.Segment, Risk = rule.Risk, Glyph = rule.Glyph, Key = "space." + rule.Id,
                Paths = paths, Command = rule.Command,
            };
            foreach (var root in paths)
            {
                foreach (var child in rule.Children)
                    foreach (var p in PathResolver.Expand(Path.Combine(root, child.Pattern)))
                        entry.Children.Add(new SpaceEntry
                        {
                            Id = rule.Id + "/" + child.Kind, Segment = rule.Segment, Risk = child.Risk, Glyph = rule.Glyph,
                            Key = "space.kind." + child.Kind, Paths = [p],
                        });
                if (rule.ListKind is { } kind)
                    foreach (var p in SubFolders(root))
                        entry.Children.Add(new SpaceEntry
                        {
                            Id = rule.Id + "/" + Path.GetFileName(p), Segment = rule.Segment, Risk = rule.Risk, Glyph = rule.Glyph,
                            Key = "space.kind." + kind, Name = Path.GetFileName(p), Paths = [p],
                        });
            }
            entries.Add(entry);
        }

        // 2. What the cleaner can clean, one child per target (a target already filed under a known item stays there).
        var caches = new SpaceEntry { Id = "caches", Segment = SpaceSegment.Caches, Risk = SpaceRisk.Safe, Glyph = scope.Glyphs.Caches, Key = "space.caches" };
        foreach (var target in targets.Where(t => t.Kind == TargetKind.Files))
        {
            var roots = target.ResolveRoots().Where(r => scope.Includes?.Invoke(r) != false)
                .Where(r => !claimed.Contains(r) && !claimed.Any(c => PathGuard.IsInside(r, [c]))).ToList();
            if (roots.Count == 0) continue;
            foreach (var r in roots) claimed.Add(r);
            caches.Children.Add(new SpaceEntry
            {
                Id = target.Id, Segment = SpaceSegment.Caches, Risk = (SpaceRisk)(int)target.Risk, Glyph = target.Glyph,
                Key = target.DisplayName is null ? "target." + target.Id : null, Name = target.DisplayName,
                Paths = roots, TargetId = target.Id,
            });
        }
        if (caches.Children.Count > 0) entries.Add(caches);

        // 3. Everything else under the roots, folder by folder.
        var personal = new HashSet<string>(scope.PersonalFolders, PathGuard.Comparer);
        var keep = new HashSet<string>(scope.KeepNames, PathGuard.Comparer);
        var containers = scope.Containers.SelectMany(PathResolver.Expand).ToHashSet(PathGuard.Comparer);
        var filed = new Dictionary<string, SpaceSegment>(PathGuard.Comparer);
        foreach (var (pattern, segment) in scope.Filed)
            foreach (var p in PathResolver.Expand(pattern)) filed[p] = segment;
        var discovered = new List<SpaceEntry>();
        foreach (var (pattern, segment) in scope.Roots)
        {
            foreach (var root in PathResolver.Expand(pattern))
            {
                foreach (var dir in SubFolders(root))
                {
                    if (claimed.Contains(dir)) continue;
                    var isPersonal = personal.Contains(Path.GetFileName(dir)) || personal.Contains(dir);
                    var band = isPersonal ? SpaceSegment.Files : filed.GetValueOrDefault(dir, segment);
                    var entry = Discovered(dir, band, isPersonal, keep, scope);
                    if (containers.Contains(dir))
                        foreach (var sub in SubFolders(dir).Where(s => !claimed.Contains(s)))
                            entry.Children.Add(Discovered(sub, entry.Segment, isPersonal, keep, scope));
                    discovered.Add(entry);
                    claimed.Add(dir);
                }
            }
        }
        entries.AddRange(discovered);

        // 4. Measure every entry, children first, skipping what another entry owns.
        var all = entries.SelectMany(e => e.Children.Prepend(e)).ToList();
        var done = 0;
        await Parallel.ForEachAsync(all, new ParallelOptions { MaxDegreeOfParallelism = Math.Clamp(Environment.ProcessorCount, 2, 8), CancellationToken = ct }, (entry, token) =>
        {
            var exclude = claimed.Where(c => entry.Paths.Any(p => PathGuard.IsInside(c, [p]))).ToHashSet(PathGuard.Comparer);
            long bytes = 0;
            var unreadable = false;
            foreach (var p in entry.Paths)
            {
                var (b, u) = Measure(p, exclude, token);
                bytes += b;
                unreadable |= u;
            }
            entry.Bytes = bytes;
            entry.Unreadable = unreadable;
            if (Interlocked.Increment(ref done) % 8 == 0) progress?.Report(entry.Path);
            return ValueTask.CompletedTask;
        });

        // Parts lie inside their item, so the item's own measurement already holds them; the cache entry, which has
        // no folder of its own, is the sum of its targets.
        foreach (var e in entries)
        {
            if (e.Id == "caches") e.Bytes = e.Children.Sum(c => c.Bytes);
            e.Children.RemoveAll(c => c.Bytes == 0);
            e.Children.Sort((a, b) => b.Bytes.CompareTo(a.Bytes));
        }

        // 5. Small discovered folders fold into one entry per band.
        var small = entries.Where(e => e.Id.StartsWith("folder:", StringComparison.Ordinal) && e.Bytes < SmallFolder).ToList();
        foreach (var group in small.GroupBy(e => e.Segment))
        {
            var rest = new SpaceEntry
            {
                Id = "small:" + group.Key, Segment = group.Key, Risk = SpaceRisk.Keep, Glyph = scope.Glyphs.Folder, Key = "space.small",
                Bytes = group.Sum(e => e.Bytes),
            };
            rest.Children.AddRange(group.Where(e => e.Bytes > 0).OrderByDescending(e => e.Bytes));
            entries.RemoveAll(group.Contains);
            if (rest.Bytes > 0) entries.Add(rest);
        }

        report.Items.AddRange(entries.Where(e => e.Bytes > 0).OrderByDescending(e => e.Bytes));
        foreach (var segment in Enum.GetValues<SpaceSegment>())
            report.Segments[segment] = report.Items.Where(e => e.Segment == segment).Sum(e => e.Bytes);
        // Used but not measured: the operating system, swap and whatever could not be read.
        report.Segments[SpaceSegment.System] += Math.Max(0, report.Used - report.Measured);
        report.Elapsed = sw.Elapsed;
        return report;
    }

    /// <summary>
    /// Removes one entry the user picked, into the Recycle Bin / Trash or permanently. Refuses Keep items, commands,
    /// cache targets and protected locations. Returns the bytes freed (0 when nothing was removed).
    /// </summary>
    public long Remove(SpaceEntry entry, bool useRecycleBin)
    {
        if (!entry.CanDelete) return 0;
        var path = entry.Path;
        var isDirectory = Directory.Exists(path);
        if (!isDirectory && !File.Exists(path)) return 0;
        if (isDirectory && new DirectoryInfo(path).LinkTarget is not null) return 0;

        try
        {
            if (useRecycleBin) RecycleBinNative.MoveToRecycleBin([path]);
            else if (isDirectory) Directory.Delete(path, recursive: true);
            else File.Delete(path);
        }
        catch
        {
            // partly removed: measured below
        }

        if (Directory.Exists(path) || File.Exists(path))
        {
            var (left, _) = Measure(path, new HashSet<string>(PathGuard.Comparer), CancellationToken.None);
            return Math.Max(0, entry.Bytes - left);
        }
        return entry.Bytes;
    }

    private static SpaceEntry Discovered(string dir, SpaceSegment segment, bool personal, IReadOnlySet<string> keep, SpaceScope scope) => new()
    {
        Id = "folder:" + dir,
        Segment = segment,
        // Your own files, protected folders and profiles are shown only; anything else may go, at your discretion.
        Risk = personal || keep.Contains(Path.GetFileName(dir)) || !PathGuard.IsAllowedRoot(dir) ? SpaceRisk.Keep : SpaceRisk.Careful,
        Glyph = personal ? scope.Glyphs.Personal : scope.Glyphs.Folder,
        Key = personal ? "space.personal" : "space.folder",
        Name = Path.GetFileName(dir),
        Paths = [dir],
    };

    private static IEnumerable<string> SubFolders(string root)
    {
        try
        {
            return Directory.EnumerateDirectories(root, "*", new EnumerationOptions
            {
                IgnoreInaccessible = true,
                AttributesToSkip = FileAttributes.ReparsePoint,
            }).ToList();
        }
        catch
        {
            return [];
        }
    }

    /// <summary>Bytes under a path (a folder or one file), never following links, skipping excluded folders.</summary>
    internal static (long Bytes, bool Unreadable) Measure(string path, IReadOnlySet<string> exclude, CancellationToken ct)
    {
        try
        {
            if (File.Exists(path)) return (new FileInfo(path).Length, false);
        }
        catch
        {
            return (0, true);
        }

        long bytes = 0;
        var unreadable = 0;
        MeasureFolder(path, 0);
        ct.ThrowIfCancellationRequested();
        return (bytes, unreadable != 0);

        // The top levels fan out over the thread pool: C:\Windows or Program Files walked by one thread take minutes.
        void MeasureFolder(string dir, int depth)
        {
            if (ct.IsCancellationRequested) return;
            var folders = new List<string>();
            long local = 0;
            try
            {
                var entries = new System.IO.Enumeration.FileSystemEnumerable<(string? Folder, long Length)>(dir,
                    (ref System.IO.Enumeration.FileSystemEntry e) => e.IsDirectory ? (e.ToFullPath(), 0) : (null, e.Length), MeasureOptions);
                foreach (var (folder, length) in entries)
                {
                    if (folder is null) local += length;
                    else if (!exclude.Contains(folder)) folders.Add(folder);
                }
            }
            catch (Exception ex) when (ex is UnauthorizedAccessException or IOException or System.Security.SecurityException)
            {
                Interlocked.Exchange(ref unreadable, 1);
            }
            Interlocked.Add(ref bytes, local);

            if (depth < ParallelDepth && folders.Count > 1)
                Parallel.ForEach(folders, new ParallelOptions { MaxDegreeOfParallelism = Environment.ProcessorCount }, f => MeasureFolder(f, depth + 1));
            else
                foreach (var f in folders) MeasureFolder(f, depth + 1);
        }
    }

    private const int ParallelDepth = 3;

    private static readonly EnumerationOptions MeasureOptions = new()
    {
        IgnoreInaccessible = false, AttributesToSkip = FileAttributes.ReparsePoint, ReturnSpecialDirectories = false,
    };

    private static (string Name, long Total, long Free) Volume(string path)
    {
        try
        {
            var full = Path.GetFullPath(path);
            DriveInfo? best = null;
            foreach (var drive in DriveInfo.GetDrives())
            {
                try
                {
                    if (!drive.IsReady || drive.TotalSize <= 0) continue;
                    var root = drive.RootDirectory.FullName;
                    if (!full.StartsWith(root, PathGuard.Comparison)) continue;
                    if (best is null || root.Length > best.RootDirectory.FullName.Length) best = drive;
                }
                catch
                {
                    // a drive that went away
                }
            }
            if (best is null) return (path, 0, 0);
            var name = best.RootDirectory.FullName.TrimEnd('\\');
            return (name.Length == 0 ? "/" : name, best.TotalSize, best.AvailableFreeSpace);
        }
        catch
        {
            return (path, 0, 0);
        }
    }
}
