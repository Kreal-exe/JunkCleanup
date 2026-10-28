namespace JunkCleanup.Core;

/// <summary>
/// The Disk page on Windows: known space consumers (with the parts that are safe to remove), the folders to look
/// through, and how what is found is filed. Icons are Segoe Fluent Icons, like the target catalog's.
/// </summary>
public static class SpaceCatalog
{
    private const string GFolder = "";
    private const string GPersonal = "";
    private const string GErase = "";
    private const string GRobot = "";
    private const string GBrain = "";
    private const string GAndroid = "";
    private const string GPhone = "";
    private const string GMonitor = "";
    private const string GCube = "";
    private const string GGame = "";
    private const string GApps = "";
    private const string GWindows = "";

    public static IReadOnlyList<SpaceRule> Rules { get; } =
    [
        // ── AI agents and models ──
        new()
        {
            // Hermes Agent (Nous Research): its caches and pre-restore backups can go; its runtimes, code, history,
            // memories and skills are the agent itself.
            Id = "hermes", Segment = SpaceSegment.Developer, Glyph = GRobot, Paths = [@"%USERPROFILE%\.hermes"],
            Children =
            [
                new("cache", "cache", SpaceRisk.Safe), new("cache", @"hermes-agent\.cache", SpaceRisk.Safe),
                new("cache", "image_cache", SpaceRisk.Safe), new("cache", "audio_cache", SpaceRisk.Safe),
                new("backups", "backups", SpaceRisk.Careful), new("logs", "logs", SpaceRisk.Moderate),
                new("app", "installs", SpaceRisk.Keep), new("app", "hermes-agent", SpaceRisk.Keep), new("app", "tools", SpaceRisk.Keep),
            ],
        },
        new() { Id = "huggingface", Segment = SpaceSegment.Models, Glyph = GBrain, Paths = [@"%USERPROFILE%\.cache\huggingface\hub"], Risk = SpaceRisk.Careful, ListKind = "model" },
        new() { Id = "ollama", Segment = SpaceSegment.Models, Glyph = GBrain, Paths = [@"%USERPROFILE%\.ollama\models"], Risk = SpaceRisk.Careful, Command = "ollama rm <model>" },
        new() { Id = "lmstudio", Segment = SpaceSegment.Models, Glyph = GBrain, Paths = [@"%USERPROFILE%\.lmstudio\models", @"%USERPROFILE%\.cache\lm-studio\models"], Risk = SpaceRisk.Careful, ListKind = "model" },

        // ── emulators, virtual machines, containers ──
        new() { Id = "android.images", Segment = SpaceSegment.VirtualMachines, Glyph = GAndroid, Paths = [@"%LOCALAPPDATA%\Android\Sdk\system-images\*\*"], Risk = SpaceRisk.Moderate, ListKind = "image" },
        new() { Id = "android.avd", Segment = SpaceSegment.VirtualMachines, Glyph = GPhone, Paths = [@"%USERPROFILE%\.android\avd"], Risk = SpaceRisk.Careful, ListKind = "vm" },
        new() { Id = "wsl", Segment = SpaceSegment.VirtualMachines, Glyph = GMonitor, Paths = [@"%LOCALAPPDATA%\Packages\CanonicalGroupLimited.*\LocalState", @"%LOCALAPPDATA%\wsl"], Command = "wsl --list --verbose" },
        new() { Id = "docker", Segment = SpaceSegment.VirtualMachines, Glyph = GCube, Paths = [@"%LOCALAPPDATA%\Docker\wsl"], Command = "docker system prune -a" },

        // ── apps and the system ──
        new() { Id = "games", Segment = SpaceSegment.Apps, Glyph = GGame, Paths = [@"{steam}\steamapps\common"], ListKind = "game" },
        new() { Id = "programfiles", Segment = SpaceSegment.Apps, Glyph = GApps, Paths = [@"%ProgramFiles%", @"%ProgramFiles(x86)%"] },
        new() { Id = "programdata", Segment = SpaceSegment.Apps, Glyph = GApps, Paths = [@"%ProgramData%"] },
        new() { Id = "windows", Segment = SpaceSegment.System, Glyph = GWindows, Paths = [@"%WINDIR%"], Command = "Dism.exe /Online /Cleanup-Image /StartComponentCleanup" },
    ];

    public static SpaceScope Scope() => new()
    {
        Rules = Rules,
        Roots = [(@"%USERPROFILE%", SpaceSegment.Other), (@"%LOCALAPPDATA%", SpaceSegment.Apps), (@"%APPDATA%", SpaceSegment.Apps)],
        Containers = [],
        Filed = [(@"%USERPROFILE%\AppData", SpaceSegment.Apps)],
        KeepNames =
        [
            "Microsoft", "Packages", "Programs", "Google", "Mozilla", "BraveSoftware", "Vivaldi", "Opera Software", "Yandex",
            "Apple", "Apple Computer", "Comms", "ConnectedDevicesPlatform", "Publishers", "Microsoft Edge", "Thunderbird",
            "Telegram Desktop", "discord", "Slack", "Code", "JetBrains", "AppData", "NTUSER.DAT",
        ],
        PersonalFolders =
        [
            "Desktop", "Documents", "Downloads", "Music", "Pictures", "Videos", "OneDrive", "Favorites", "Contacts", "Links",
            "Saved Games", "Searches", "3D Objects",
        ],
        VolumePath = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
        Glyphs = (GFolder, GPersonal, GErase),
    };
}
