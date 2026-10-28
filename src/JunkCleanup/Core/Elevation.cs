using System.ComponentModel;
using System.Diagnostics;
using System.Security.Principal;

namespace JunkCleanup.Core;

public static class Elevation
{
    public static bool IsElevated { get; } = Compute();

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
