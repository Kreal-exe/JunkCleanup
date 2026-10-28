using System.Diagnostics;

namespace JunkCleanup.Core;

public readonly record struct FileEntry(string Path, long Length);

/// <param name="Complete">Every file underneath was collected, so the folder can go to the Recycle Bin as one item.</param>
public sealed record EntrySummary(string Path, string Name, bool IsDirectory, long Bytes, int Files, bool Complete = false);

public enum ScanPhase { Started, Progress, Completed }

public sealed record ScanProgress(
    ScanPhase Phase,
    int Completed,
    int Total,
    string TargetId,
    long BytesFound,
    TargetScanResult? Result,
    long TargetBytes = 0);

public sealed class ScanOptions
{
    /// <summary>Files modified more recently than this are skipped for targets that respect the age filter. Null disables.</summary>
    public TimeSpan? SkipNewerThan { get; init; }

    /// <summary>Maximum number of first-level entries kept per target for the details view.</summary>
    public int MaxTopEntries { get; init; } = 100;
}

public sealed class TargetScanResult
{
    public TargetScanResult(CleanupTarget target) => Target = target;

    public CleanupTarget Target { get; }
    public IReadOnlyList<string> Roots { get; set; } = [];
    public List<FileEntry> Files { get; } = [];
    public List<EntrySummary> TopEntries { get; set; } = [];
    public long TotalBytes { get; set; }
    public int FileCount { get; set; }
    public bool AccessDenied { get; set; }
    public string? Error { get; set; }
    public TimeSpan Elapsed { get; set; }
}

/// <summary>Scans targets in parallel and reports live progress.</summary>
public sealed class ScanEngine
{
    public async Task<IReadOnlyList<TargetScanResult>> ScanAsync(
        IReadOnlyList<CleanupTarget> targets,
        ScanOptions options,
        IProgress<ScanProgress>? progress,
        CancellationToken ct)
    {
        var results = new TargetScanResult[targets.Count];
        long bytesFound = 0;
        var completed = 0;
        var lastReport = Stopwatch.StartNew();
        var reportLock = new object();

        var parallel = new ParallelOptions
        {
            MaxDegreeOfParallelism = Math.Clamp(Environment.ProcessorCount, 2, 8),
            CancellationToken = ct,
        };

        await Parallel.ForEachAsync(Enumerable.Range(0, targets.Count), parallel, async (i, token) =>
        {
            var target = targets[i];
            progress?.Report(new ScanProgress(ScanPhase.Started, Volatile.Read(ref completed), targets.Count, target.Id, Interlocked.Read(ref bytesFound), null));

            long targetBytes = 0;
            var result = await Task.Run(() => ScanTarget(target, options, delta =>
            {
                var total = Interlocked.Add(ref bytesFound, delta);
                targetBytes += delta; // one worker per target
                if (progress is null) return;

                // Throttle live byte updates to ~30/s across all workers.
                lock (reportLock)
                {
                    if (lastReport.ElapsedMilliseconds < 33) return;
                    lastReport.Restart();
                }

                progress.Report(new ScanProgress(ScanPhase.Progress, Volatile.Read(ref completed), targets.Count, target.Id, total, null, targetBytes));
            }, token), token);

            results[i] = result;
            var done = Interlocked.Increment(ref completed);
            progress?.Report(new ScanProgress(ScanPhase.Completed, done, targets.Count, target.Id, Interlocked.Read(ref bytesFound), result, result.TotalBytes));
        });

        return results;
    }

    public TargetScanResult ScanTarget(CleanupTarget target, ScanOptions options, Action<long>? onBytes, CancellationToken ct)
    {
        var sw = Stopwatch.StartNew();
        var result = new TargetScanResult(target);

        try
        {
            if (target.Kind == TargetKind.RecycleBin)
            {
                var (bytes, items) = RecycleBinNative.Query();
                result.TotalBytes = bytes;
                result.FileCount = (int)Math.Min(items, int.MaxValue);
                onBytes?.Invoke(bytes);
                return result;
            }

            result.Roots = target.ResolveRoots();
            var cutoff = options.SkipNewerThan is { } age && target.RespectsAgeFilter && age > TimeSpan.Zero
                ? DateTime.UtcNow - age
                : (DateTime?)null;

            var groups = new Dictionary<string, GroupAccumulator>(PathGuard.Comparer);
            var enumeration = new EnumerationOptions
            {
                RecurseSubdirectories = target.Recursive,
                IgnoreInaccessible = true,
                AttributesToSkip = FileAttributes.ReparsePoint,
                MatchCasing = MatchCasing.CaseInsensitive,
                ReturnSpecialDirectories = false,
            };

            long pending = 0;
            foreach (var root in result.Roots)
            {
                ct.ThrowIfCancellationRequested();

                if (!HasReadAccess(root))
                {
                    result.AccessDenied = true;
                    continue;
                }

                var rootInfo = new DirectoryInfo(root);
                var prefixLength = PathGuard.Normalize(root).Length + 1;

                foreach (var pattern in target.FilePatterns)
                {
                    IEnumerable<FileInfo> files;
                    try
                    {
                        files = rootInfo.EnumerateFiles(pattern, enumeration);
                    }
                    catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
                    {
                        result.Error = ex.Message;
                        continue;
                    }

                    foreach (var file in files)
                    {
                        ct.ThrowIfCancellationRequested();

                        // Group by the first path segment under the root for the details view.
                        var relative = file.FullName.Length > prefixLength ? file.FullName.AsSpan(prefixLength) : ReadOnlySpan<char>.Empty;
                        var sep = relative.IndexOf(Path.DirectorySeparatorChar);
                        var isDirectory = sep >= 0;
                        var name = isDirectory ? relative[..sep].ToString() : relative.ToString();
                        var key = Path.Combine(root, name);

                        if (!groups.TryGetValue(key, out var acc))
                        {
                            acc = new GroupAccumulator(key, name, isDirectory);
                            groups[key] = acc;
                        }

                        long length;
                        try
                        {
                            if (cutoff is { } c && file.LastWriteTimeUtc > c)
                            {
                                acc.Complete = false;
                                continue;
                            }
                            length = file.Length;
                        }
                        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
                        {
                            acc.Complete = false;
                            continue;
                        }

                        result.Files.Add(new FileEntry(file.FullName, length));
                        result.TotalBytes += length;
                        result.FileCount++;

                        acc.Bytes += length;
                        acc.Files++;

                        pending += length;
                        if (pending >= 4 * 1024 * 1024 && onBytes is not null)
                        {
                            onBytes(pending);
                            pending = 0;
                        }
                    }
                }
            }

            if (pending > 0) onBytes?.Invoke(pending);

            // With a file pattern only some files of a folder are ours, so no folder is ever complete.
            var allFiles = target.FilePatterns is ["*"];
            result.TopEntries = groups.Values
                .Where(g => g.Files > 0)
                .OrderByDescending(g => g.Bytes)
                .Take(options.MaxTopEntries)
                .Select(g => new EntrySummary(g.Path, g.Name, g.IsDirectory, g.Bytes, g.Files, g.Complete && allFiles && target.Recursive))
                .ToList();
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (Exception ex)
        {
            result.Error = ex.Message;
        }
        finally
        {
            result.Elapsed = sw.Elapsed;
        }

        return result;
    }

    private static bool HasReadAccess(string root)
    {
        try
        {
            using var e = Directory.EnumerateFileSystemEntries(root).GetEnumerator();
            e.MoveNext();
            return true;
        }
        catch (UnauthorizedAccessException)
        {
            return false;
        }
        catch (Exception)
        {
            return true; // other errors are reported per-file
        }
    }

    private sealed class GroupAccumulator(string path, string name, bool isDirectory)
    {
        public string Path { get; } = path;
        public string Name { get; } = name;
        public bool IsDirectory { get; } = isDirectory;
        public long Bytes;
        public int Files;
        public bool Complete = true;
    }
}
