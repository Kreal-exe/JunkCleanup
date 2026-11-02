using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace JunkCleanup.Settings;

public sealed class AppSettings
{
    /// <summary>"auto" or a language code from <see cref="Localization.LocalizationManager.Languages"/>.</summary>
    public string Language { get; set; } = "auto";

    /// <summary>"dark", "light" or "system".</summary>
    public string Theme { get; set; } = "dark";

    public bool UseRecycleBin { get; set; } = true;
    public int SkipRecentHours { get; set; } = 24;

    /// <summary>A scan also measures the disk for the Disk page.</summary>
    public bool MeasureDiskWithScan { get; set; } = true;

    /// <summary>Clean asks first, with the size and the number of files.</summary>
    public bool ConfirmClean { get; set; } = true;
    public bool Animations { get; set; } = true;
    public bool Backdrop { get; set; } = true;
    /// <summary>Stored as "scanOnLaunch": 1.0.0 builds saved "scanOnStartup": false by default, and that old value must not
    /// keep the new default (scan on launch) from reaching them.</summary>
    [JsonPropertyName("scanOnLaunch")]
    public bool ScanOnStartup { get; set; } = true;

    public Dictionary<string, bool> TargetStates { get; set; } = new(StringComparer.Ordinal);
    public List<string> CustomFolders { get; set; } = [];

    public double WindowWidth { get; set; }
    public double WindowHeight { get; set; }
    public bool WindowMaximized { get; set; }

    public long LifetimeBytesFreed { get; set; }
}

public static class SettingsStore
{
    private static readonly JsonSerializerOptions Options = new()
    {
        WriteIndented = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.Never,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
    };

    // JUNKCLEANUP_SETTINGS may point at an alternative settings file (portable use, testing).
    public static string FilePath { get; } =
        Environment.GetEnvironmentVariable("JUNKCLEANUP_SETTINGS") is { Length: > 0 } custom
            ? Path.GetFullPath(custom)
            : Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "JunkCleanup", "settings.json");

    public static string Directory { get; } = Path.GetDirectoryName(FilePath)!;

    /// <summary>Where the app kept its settings before it was renamed from CacheCleanup; read until the first save.</summary>
    private static string LegacyPath => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "CacheCleanup", "settings.json");

    public static AppSettings Load()
    {
        try
        {
            var path = File.Exists(FilePath) || Environment.GetEnvironmentVariable("JUNKCLEANUP_SETTINGS") is { Length: > 0 } ? FilePath : LegacyPath;
            if (File.Exists(path))
            {
                var json = File.ReadAllText(path);
                return JsonSerializer.Deserialize<AppSettings>(json, Options) ?? new AppSettings();
            }
        }
        catch
        {
            // corrupt settings fall back to defaults
        }

        return new AppSettings();
    }

    public static void Save(AppSettings settings)
    {
        try
        {
            System.IO.Directory.CreateDirectory(Directory);
            var tmp = FilePath + ".tmp";
            File.WriteAllText(tmp, JsonSerializer.Serialize(settings, Options));
            File.Move(tmp, FilePath, overwrite: true);
        }
        catch
        {
            // never crash because of settings
        }
    }
}
