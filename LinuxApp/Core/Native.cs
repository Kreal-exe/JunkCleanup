using System.Runtime.InteropServices;

namespace JunkCleanup.Core;

/// <summary>
/// The few libc calls .NET does not expose: rename(2) without File.Move's copy-and-delete fallback across file systems
/// (a Trash move must never copy gigabytes), and the user id for the per-volume trash folders.
/// </summary>
internal static class Native
{
    public const int EXDEV = 18; // same number on Linux and macOS

    static Native()
    {
        // "libc" is not a file name on either system: glibc ships libc.so.6, macOS (where the tests run) libSystem.
        NativeLibrary.SetDllImportResolver(typeof(Native).Assembly, (name, assembly, path) =>
        {
            if (name != "libc") return IntPtr.Zero;
            var candidates = OperatingSystem.IsMacOS() ? new[] { "/usr/lib/libSystem.B.dylib" } : ["libc.so.6", "libc.so"];
            foreach (var candidate in candidates)
                if (NativeLibrary.TryLoad(candidate, assembly, path, out var handle)) return handle;
            return IntPtr.Zero;
        });
    }

    [DllImport("libc", EntryPoint = "rename", SetLastError = true)]
    private static extern int RenameNative([MarshalAs(UnmanagedType.LPUTF8Str)] string oldPath, [MarshalAs(UnmanagedType.LPUTF8Str)] string newPath);

    [DllImport("libc", EntryPoint = "getuid")]
    private static extern uint GetUidNative();

    [DllImport("libc", EntryPoint = "geteuid")]
    private static extern uint GetEUidNative();

    /// <summary>Renames in place; returns 0 or the errno (EXDEV when the two paths are on different file systems).</summary>
    public static int Rename(string from, string to)
    {
        try
        {
            return RenameNative(from, to) == 0 ? 0 : Marshal.GetLastPInvokeError();
        }
        catch (Exception ex) when (ex is DllNotFoundException or EntryPointNotFoundException)
        {
            return -1;
        }
    }

    public static uint UserId
    {
        get
        {
            try { return GetUidNative(); }
            catch (Exception ex) when (ex is DllNotFoundException or EntryPointNotFoundException) { return uint.MaxValue; }
        }
    }

    public static bool IsRoot
    {
        get
        {
            try { return GetEUidNative() == 0; }
            catch (Exception ex) when (ex is DllNotFoundException or EntryPointNotFoundException) { return false; }
        }
    }
}
