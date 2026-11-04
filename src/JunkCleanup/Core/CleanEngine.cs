using System.Diagnostics;

namespace JunkCleanup.Core;

public sealed class CleanOptions
{
    public bool UseRecycleBin { get; init; } = true;
    public bool DryRun { get; init; }

    /// <summary>
    /// Marks a file that could not be deleted (held open by an app) for removal at the next restart; true when it
    /// was marked. Null when the platform or the rights do not allow it (on Windows it takes administrator).
    /// </summary>
    public Func<string, bool>? ScheduleAtRestart { get; init; }
}

public sealed record CleanProgress(
    string TargetId,
    bool TargetDone,
    long BytesFreed,
    int FilesDeleted,
    int Failed,
    int TargetsDone,
    int TargetsTotal,
    TargetCleanResult? TargetResult);

public sealed class TargetCleanResult
{
    public required string TargetId { get; init; }
    public long BytesFreed { get; set; }
    public long BytesRemaining { get; set; }
    public int FilesDeleted { get; set; }
    public int Failed { get; set; }

    /// <summary>Of the failed files, those marked for removal at the next restart.</summary>
    public int AtRestart { get; set; }

    /// <summary>Files still on disk afterwards: the ones that failed plus any left when the clean was stopped.</summary>
    public int FilesRemaining { get; set; }

    public string? Error { get; set; }
}

public sealed class CleanReport
{
    public long BytesFreed { get; set; }
    public int FilesDeleted { get; set; }
    public int Failed { get; set; }
    public int AtRestart { get; set; }
    public bool Cancelled { get; set; }
    public TimeSpan Elapsed { get; set; }
    public Dictionary<string, TargetCleanResult> Targets { get; } = new(StringComparer.Ordinal);
}

/// <summary>
/// Deletes scanned files, either into the Recycle Bin or permanently, never leaving the scanned roots.
/// Targets are cleaned side by side and files within a target in parallel; cancelling stops between files and
/// reports what was done so far.
/// </summary>
public sealed class CleanEngine
{
    private const int RecycleBatchSize = 500;
    private static readonly int TargetParallelism = Math.Clamp(Environment.ProcessorCount / 2, 2, 4);
    private static readonly int FileParallelism = Math.Clamp(Environment.ProcessorCount, 4, 16);

    public async Task<CleanReport> CleanAsync(
        IReadOnlyList<TargetScanResult> targets,
        CleanOptions options,
        IProgress<CleanProgress>? progress,
        CancellationToken ct)
    {
        var report = new CleanReport();
        var sw = Stopwatch.StartNew();
        var live = new (long Freed, int Deleted, int Failed)[targets.Count];
        var gate = new object();
        var done = 0;

        void Publish(string targetId, bool targetDone, TargetCleanResult? result)
        {
            if (progress is null) return;
            long freed = 0;
            int deleted = 0, failed = 0, finished;
            lock (gate)
            {
                foreach (var (f, d, x) in live)
                {
                    freed += f;
                    deleted += d;
                    failed += x;
                }
                finished = done;
            }
            progress.Report(new CleanProgress(targetId, targetDone, freed, deleted, failed, finished, targets.Count, result));
        }

        // The token is checked inside, so a stop ends the loop quietly instead of throwing.
        var parallel = new ParallelOptions { MaxDegreeOfParallelism = TargetParallelism };
        await Parallel.ForEachAsync(Enumerable.Range(0, targets.Count), parallel, async (i, _) =>
        {
            if (ct.IsCancellationRequested) return;
            var scan = targets[i];

            var result = await Task.Run(() => CleanTarget(scan, options, (freed, deleted, failed) =>
            {
                lock (gate) live[i] = (freed, deleted, failed);
                Publish(scan.Target.Id, false, null);
            }, ct));

            lock (gate)
            {
                live[i] = (result.BytesFreed, result.FilesDeleted, result.Failed);
                done++;
                report.BytesFreed += result.BytesFreed;
                report.FilesDeleted += result.FilesDeleted;
                report.Failed += result.Failed;
                report.AtRestart += result.AtRestart;
                report.Targets[scan.Target.Id] = result;
            }
            Publish(scan.Target.Id, true, result);
        });

        report.Cancelled = ct.IsCancellationRequested;
        report.Elapsed = sw.Elapsed;
        return report;
    }

    public TargetCleanResult CleanTarget(TargetScanResult scan, CleanOptions options, Action<long, int, int>? onProgress, CancellationToken ct)
    {
        var result = new TargetCleanResult { TargetId = scan.Target.Id };

        try
        {
            if (scan.Target.Kind == TargetKind.RecycleBin)
            {
                // What is in it now: more than scanned when files were moved there since.
                var (binBytes, binItems) = options.DryRun ? (scan.TotalBytes, scan.FileCount) : RecycleBinNative.Query();
                if (options.DryRun || RecycleBinNative.Empty())
                {
                    result.BytesFreed = Math.Max(binBytes, scan.TotalBytes);
                    result.FilesDeleted = (int)Math.Max(binItems, scan.FileCount);
                }
                else
                {
                    result.Failed = scan.FileCount;
                }
                return Finish(result, scan);
            }

            var roots = scan.Roots;
            var safeFiles = new List<FileEntry>(scan.Files.Count);
            foreach (var file in scan.Files)
            {
                if (PathGuard.IsInside(file.Path, roots)) safeFiles.Add(file);
                else result.Failed++;
            }

            if (options.DryRun)
            {
                result.BytesFreed = safeFiles.Sum(f => f.Length);
                result.FilesDeleted = safeFiles.Count;
                return Finish(result, scan);
            }

            long freed = 0;
            int deleted = 0, failed = result.Failed, atRestart = 0;
            var reportGate = new object();
            var lastReport = Stopwatch.StartNew();
            void Report()
            {
                lock (reportGate)
                {
                    if (lastReport.ElapsedMilliseconds < 40) return;
                    lastReport.Restart();
                }
                onProgress?.Invoke(Interlocked.Read(ref freed), Volatile.Read(ref deleted), Volatile.Read(ref failed));
            }

            if (options.UseRecycleBin)
            {
                // Recycling 100 000 cache files one by one takes minutes, so a first-level folder whose every file
                // was scanned goes to the Recycle Bin as one item (it is still underneath the scanned root).
                var handled = new HashSet<string>(PathGuard.Comparer);
                var folders = scan.TopEntries
                    .Where(e => e.IsDirectory && e.Complete && e.Files > 0 && PathGuard.IsInside(e.Path, roots) && IsPlainDirectory(e.Path))
                    .ToList();
                foreach (var batch in folders.Chunk(50))
                {
                    if (ct.IsCancellationRequested) break;
                    RecycleBinNative.MoveToRecycleBin(batch.Select(e => e.Path).ToList());
                    foreach (var entry in batch)
                    {
                        if (Directory.Exists(entry.Path)) continue;
                        handled.Add(entry.Path);
                        deleted += entry.Files;
                        freed += entry.Bytes;
                    }
                    Report();
                }

                var rest = handled.Count == 0 ? safeFiles : safeFiles.Where(f => !handled.Contains(OwnerFolder(f.Path, roots) ?? string.Empty)).ToList();
                foreach (var batch in rest.Chunk(RecycleBatchSize))
                {
                    if (ct.IsCancellationRequested) break;
                    RecycleBinNative.MoveToRecycleBin(batch.Select(f => f.Path).ToList());

                    // The shell stops a batch at the first file it cannot move (one held open by an app), leaving every
                    // file after it in place; those go one by one, so only the files that are really in use stay.
                    foreach (var file in batch)
                    {
                        if (File.Exists(file.Path))
                        {
                            if (ct.IsCancellationRequested) { failed++; continue; }
                            RecycleBinNative.MoveToRecycleBin([file.Path]);
                        }
                        if (File.Exists(file.Path))
                        {
                            failed++;
                        }
                        else
                        {
                            deleted++;
                            freed += file.Length;
                        }
                    }

                    Report();
                }
            }
            else
            {
                var parallel = new ParallelOptions { MaxDegreeOfParallelism = FileParallelism };
                Parallel.ForEach(safeFiles, parallel, (file, state) =>
                {
                    if (ct.IsCancellationRequested)
                    {
                        state.Stop();
                        return;
                    }

                    if (DeleteFile(file.Path))
                    {
                        Interlocked.Increment(ref deleted);
                        Interlocked.Add(ref freed, file.Length);
                    }
                    else
                    {
                        Interlocked.Increment(ref failed);
                        if (options.ScheduleAtRestart?.Invoke(file.Path) == true) Interlocked.Increment(ref atRestart);
                    }

                    Report();
                });
            }

            result.BytesFreed = freed;
            result.FilesDeleted = deleted;
            result.Failed = failed;
            result.AtRestart = atRestart;

            foreach (var root in roots)
            {
                if (ct.IsCancellationRequested) break;
                PruneEmptyDirectories(root, ct);
                if (scan.Target.RemovesRoots && !options.DryRun)
                {
                    try
                    {
                        if (!Directory.EnumerateFileSystemEntries(root).Any()) Directory.Delete(root, false);
                    }
                    catch
                    {
                        // in use; an empty folder is harmless
                    }
                }
            }
        }
        catch (Exception ex)
        {
            result.Error = ex.Message;
        }

        return Finish(result, scan);

        TargetCleanResult Finish(TargetCleanResult r, TargetScanResult s)
        {
            r.BytesRemaining = Math.Max(0, s.TotalBytes - r.BytesFreed);
            r.FilesRemaining = Math.Max(0, s.FileCount - r.FilesDeleted);
            onProgress?.Invoke(r.BytesFreed, r.FilesDeleted, r.Failed);
            return r;
        }
    }

    /// <summary>
    /// Removes one first-level entry the user picked (a whole folder or a file) and takes it out of the scan result.
    /// Refuses anything that is not underneath the scanned roots. Returns null when nothing was removed.
    /// </summary>
    public TargetCleanResult? RemoveEntry(TargetScanResult scan, EntrySummary entry, CleanOptions options)
    {
        if (!PathGuard.IsInside(entry.Path, scan.Roots)) return null;
        var isDirectory = Directory.Exists(entry.Path);
        if (!isDirectory && !File.Exists(entry.Path)) return null;
        if (isDirectory && !IsPlainDirectory(entry.Path)) return null;

        try
        {
            if (options.UseRecycleBin)
            {
                RecycleBinNative.MoveToRecycleBin([entry.Path]);
            }
            else if (isDirectory)
            {
                Directory.Delete(entry.Path, recursive: true); // junctions inside are removed, never followed
            }
            else
            {
                DeleteFile(entry.Path);
            }
        }
        catch (Exception)
        {
            // partly removed: what is gone is counted below
        }

        // Take whatever is gone out of the scan, so the totals and a later clean match what is left on disk.
        var prefix = entry.Path.TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
        var gone = scan.Files.Where(f => (f.Path.Equals(entry.Path, PathGuard.Comparison)
                                          || f.Path.StartsWith(prefix, PathGuard.Comparison)) && !File.Exists(f.Path)).ToList();
        if (gone.Count == 0 && (isDirectory ? Directory.Exists(entry.Path) : File.Exists(entry.Path))) return null;

        var goneSet = gone.Select(f => f.Path).ToHashSet(PathGuard.Comparer);
        scan.Files.RemoveAll(f => goneSet.Contains(f.Path));
        var freed = gone.Sum(f => f.Length);
        scan.TotalBytes -= freed;
        scan.FileCount -= gone.Count;
        if (!Directory.Exists(entry.Path) && !File.Exists(entry.Path))
            scan.TopEntries = scan.TopEntries.Where(e => !e.Path.Equals(entry.Path, PathGuard.Comparison)).ToList();

        return new TargetCleanResult
        {
            TargetId = scan.Target.Id,
            BytesFreed = freed,
            FilesDeleted = gone.Count,
            BytesRemaining = scan.TotalBytes,
            FilesRemaining = scan.FileCount,
        };
    }

    /// <summary>The first-level folder under a root that holds the file, or null for files directly in a root.</summary>
    private static string? OwnerFolder(string path, IReadOnlyList<string> roots)
    {
        foreach (var root in roots)
        {
            var r = PathGuard.Normalize(root);
            if (path.Length <= r.Length + 1 || !path.StartsWith(r, PathGuard.Comparison) || path[r.Length] != Path.DirectorySeparatorChar) continue;
            var sep = path.IndexOf(Path.DirectorySeparatorChar, r.Length + 1);
            return sep < 0 ? null : path[..sep];
        }
        return null;
    }

    private static bool IsPlainDirectory(string path)
    {
        try
        {
            var info = new DirectoryInfo(path);
            return info.Exists && !info.Attributes.HasFlag(FileAttributes.ReparsePoint);
        }
        catch
        {
            return false;
        }
    }

    private static bool DeleteFile(string path)
    {
        try
        {
            File.Delete(path);
            return true;
        }
        catch (UnauthorizedAccessException)
        {
            try
            {
                File.SetAttributes(path, FileAttributes.Normal);
                File.Delete(path);
                return true;
            }
            catch
            {
                return false;
            }
        }
        catch (Exception)
        {
            return false;
        }
    }

    /// <summary>Removes directories under <paramref name="root"/> that are empty after cleaning. The root itself is kept.</summary>
    private static void PruneEmptyDirectories(string root, CancellationToken ct)
    {
        List<string> dirs;
        try
        {
            dirs = Directory.EnumerateDirectories(root, "*", new EnumerationOptions
            {
                RecurseSubdirectories = true,
                IgnoreInaccessible = true,
                AttributesToSkip = FileAttributes.ReparsePoint,
            }).ToList();
        }
        catch
        {
            return;
        }

        // Deepest first so parents become empty after their children are removed.
        dirs.Sort((a, b) => b.Length.CompareTo(a.Length));
        foreach (var dir in dirs)
        {
            if (ct.IsCancellationRequested) return;
            try
            {
                if (!Directory.EnumerateFileSystemEntries(dir).Any())
                    Directory.Delete(dir, false);
            }
            catch
            {
                // in use or protected; leave it
            }
        }
    }
}
