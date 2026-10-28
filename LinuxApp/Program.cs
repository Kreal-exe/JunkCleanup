using Avalonia;
using JunkCleanup.Core;

namespace JunkCleanup;

internal static class Program
{
    [STAThread]
    public static int Main(string[] args)
    {
        if (args.Contains("--scan")) return ScanReport(args.Contains("--files"));
        return BuildAvaloniaApp().StartWithClassicDesktopLifetime(args);
    }

    public static AppBuilder BuildAvaloniaApp()
        => AppBuilder.Configure<App>()
            .UsePlatformDetect()
            .WithInterFont()
            .With(new X11PlatformOptions { WmClass = "JunkCleanup" })
            .LogToTrace();

    /// <summary>
    /// "JunkCleanup --scan": every target, the folders it resolves to and what it would free, without a window and
    /// without touching anything. "--files" also lists each file. Handy over SSH and for checking a new distro.
    /// </summary>
    private static int ScanReport(bool listFiles)
    {
        var targets = TargetCatalog.All.ToList();
        var results = new ScanEngine().ScanAsync(targets, new ScanOptions { SkipNewerThan = TimeSpan.FromHours(24) }, null, CancellationToken.None)
            .GetAwaiter().GetResult();

        long total = 0;
        foreach (var r in results)
        {
            var t = r.Target;
            var present = t.Kind == TargetKind.RecycleBin || r.Roots.Count > 0;
            var flags = $"{t.Risk}{(t.EnabledByDefault ? "" : ", off by default")}";
            Console.WriteLine($"{(present ? "●" : "○")} {t.Id,-22} {ByteFormatter.Format(r.TotalBytes),10}  {r.FileCount,7} files  [{flags}]");
            if (t.Kind == TargetKind.RecycleBin) Console.WriteLine($"      {RecycleBinNative.HomeTrash}");
            foreach (var root in r.Roots) Console.WriteLine($"      {root}");
            if (r.AccessDenied) Console.WriteLine("      (some folders could not be read)");
            if (r.Error is not null) Console.WriteLine($"      error: {r.Error}");
            if (listFiles)
                foreach (var f in r.Files) Console.WriteLine($"        {f.Path}  {ByteFormatter.Format(f.Length)}");
            if (present && t.EnabledByDefault) total += r.TotalBytes;
        }

        Console.WriteLine();
        Console.WriteLine($"Selected by default: {ByteFormatter.Format(total)}. Nothing was changed.");
        return 0;
    }
}
