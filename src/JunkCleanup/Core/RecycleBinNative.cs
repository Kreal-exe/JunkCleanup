using System.Runtime.InteropServices;

namespace JunkCleanup.Core;

/// <summary>Shell API wrappers: move batches of files to the Recycle Bin, query and empty it.</summary>
internal static class RecycleBinNative
{
    private const uint FO_DELETE = 0x0003;
    private const ushort FOF_SILENT = 0x0004;
    private const ushort FOF_NOCONFIRMATION = 0x0010;
    private const ushort FOF_ALLOWUNDO = 0x0040;
    private const ushort FOF_NOERRORUI = 0x0400;
    private const ushort FOF_NO_CONNECTED_ELEMENTS = 0x2000;

    private const uint SHERB_NOCONFIRMATION = 0x1;
    private const uint SHERB_NOPROGRESSUI = 0x2;
    private const uint SHERB_NOSOUND = 0x4;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct SHFILEOPSTRUCT64
    {
        public IntPtr hwnd;
        public uint wFunc;
        public string pFrom;
        public string? pTo;
        public ushort fFlags;
        [MarshalAs(UnmanagedType.Bool)] public bool fAnyOperationsAborted;
        public IntPtr hNameMappings;
        public string? lpszProgressTitle;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode, Pack = 1)]
    private struct SHFILEOPSTRUCT32
    {
        public IntPtr hwnd;
        public uint wFunc;
        public string pFrom;
        public string? pTo;
        public ushort fFlags;
        [MarshalAs(UnmanagedType.Bool)] public bool fAnyOperationsAborted;
        public IntPtr hNameMappings;
        public string? lpszProgressTitle;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct SHQUERYRBINFO
    {
        public int cbSize;
        public long i64Size;
        public long i64NumItems;
    }

    [DllImport("shell32.dll", CharSet = CharSet.Unicode, EntryPoint = "SHFileOperationW")]
    private static extern int SHFileOperation64(ref SHFILEOPSTRUCT64 op);

    [DllImport("shell32.dll", CharSet = CharSet.Unicode, EntryPoint = "SHFileOperationW")]
    private static extern int SHFileOperation32(ref SHFILEOPSTRUCT32 op);

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    private static extern int SHQueryRecycleBinW(string? pszRootPath, ref SHQUERYRBINFO info);

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    private static extern int SHEmptyRecycleBinW(IntPtr hwnd, string? pszRootPath, uint dwFlags);

    /// <summary>Moves the given paths to the Recycle Bin in one shell operation. Returns the shell result code (0 = success).</summary>
    public static int MoveToRecycleBin(IReadOnlyList<string> paths)
    {
        if (paths.Count == 0) return 0;

        // Double-null terminated list; the marshaller preserves embedded nulls.
        var from = string.Join('\0', paths) + "\0\0";
        const ushort flags = FOF_ALLOWUNDO | FOF_NOCONFIRMATION | FOF_SILENT | FOF_NOERRORUI | FOF_NO_CONNECTED_ELEMENTS;

        if (IntPtr.Size == 8)
        {
            var op = new SHFILEOPSTRUCT64 { wFunc = FO_DELETE, pFrom = from, fFlags = flags };
            return SHFileOperation64(ref op);
        }
        else
        {
            var op = new SHFILEOPSTRUCT32 { wFunc = FO_DELETE, pFrom = from, fFlags = flags };
            return SHFileOperation32(ref op);
        }
    }

    public static (long Bytes, long Items) Query()
    {
        var info = new SHQUERYRBINFO { cbSize = Marshal.SizeOf<SHQUERYRBINFO>() };
        var hr = SHQueryRecycleBinW(null, ref info);
        return hr == 0 ? (info.i64Size, info.i64NumItems) : (0, 0);
    }

    public static bool Empty()
    {
        var hr = SHEmptyRecycleBinW(IntPtr.Zero, null, SHERB_NOCONFIRMATION | SHERB_NOPROGRESSUI | SHERB_NOSOUND);
        return hr == 0;
    }
}
