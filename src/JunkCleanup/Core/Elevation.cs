using System.ComponentModel;
using System.Diagnostics;
using System.Security.Principal;

namespace JunkCleanup.Core;

public static class Elevation
{
    public static bool IsElevated { get; } = Compute();

    private const uint MOVEFILE_DELAY_UNTIL_REBOOT = 0x4;

    [System.Runtime.InteropServices.DllImport("kernel32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode, SetLastError = true)]
    private static extern bool MoveFileEx(string existing, string? replacement, uint flags);

    /// <summary>
    /// Marks a file held open by an app for deletion when Windows next starts (what BleachBit and installers do).
    /// Needs administrator; returns false without it.
    /// </summary>
    public static bool DeleteAtRestart(string path) => IsElevated && MoveFileEx(path, null, MOVEFILE_DELAY_UNTIL_REBOOT);

    private static bool Compute()
    {
        try
        {
            using var identity = WindowsIdentity.GetCurrent();
            return new WindowsPrincipal(identity).IsInRole(WindowsBuiltInRole.Administrator);
        }
        catch
        {
            return false;
        }
    }

    /// <summary>Relaunches the current executable with a UAC prompt. Returns false if the user declined.</summary>
    public static bool RestartElevated(string arguments = "")
    {
        var exe = Environment.ProcessPath;
        if (string.IsNullOrEmpty(exe)) return false;

        try
        {
            Process.Start(new ProcessStartInfo(exe)
            {
                UseShellExecute = true,
                Verb = "runas",
                Arguments = arguments,
                WorkingDirectory = Path.GetDirectoryName(exe) ?? string.Empty,
            });
            return true;
        }
        catch (Win32Exception)
        {
            return false;
        }
    }
}
