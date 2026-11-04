namespace JunkCleanup.Core;

/// <summary>The built-in list of cleanable locations.</summary>
public static class TargetCatalog
{
    // Segoe Fluent Icons glyphs
    private const string GFolder = "";
    private const string GWindows = "";
    private const string GRocket = "";
    private const string GUpdate = "";
    private const string GPicture = "";
    private const string GGlobe = "";
    private const string GBug = "";
    private const string GReport = "";
    private const string GDocument = "";
    private const string GMemory = "";
    private const string GShader = "";
    private const string GRecycle = "";
    private const string GPackage = "";
    private const string GCode = "";
    private const string GCube = "";
    private const string GChat = "";
    private const string GMusic = "";
    private const string GPhone = "";
    private const string GVideo = "";
    private const string GDownload = "";
    private const string GGame = "";
    private const string GDriver = "";
    private const string GBrain = "";
    private const string GAndroid = "";
    private const string GPython = "";
    private const string GCloud = "";

    private static string[] Chromium(string userData) =>
    [
        $@"{userData}\*\Cache",
        $@"{userData}\*\Code Cache",
        $@"{userData}\*\GPUCache",
        $@"{userData}\*\DawnCache",
        $@"{userData}\*\DawnWebGPUCache",
        $@"{userData}\*\DawnGraphiteCache",
        $@"{userData}\*\Service Worker\CacheStorage",
        $@"{userData}\*\Service Worker\ScriptCache",
        $@"{userData}\GrShaderCache",
        $@"{userData}\ShaderCache",
        $@"{userData}\GraphiteDawnCache",
    ];

    private static string[] Electron(string appRoot) =>
    [
        $@"{appRoot}\Cache",
        $@"{appRoot}\Code Cache",
        $@"{appRoot}\GPUCache",
        $@"{appRoot}\DawnCache",
        $@"{appRoot}\DawnWebGPUCache",
        $@"{appRoot}\DawnGraphiteCache",
        $@"{appRoot}\Service Worker\CacheStorage",
        $@"{appRoot}\Service Worker\ScriptCache",
    ];

    public static IReadOnlyList<CleanupTarget> All { get; } =
    [
        // ───────────────────────── System ─────────────────────────
        new()
        {
            Id = "temp.user", Category = TargetCategory.System, Glyph = GFolder,
            RespectsAgeFilter = true,
            RootPatterns = [@"%TEMP%"],
        },
        new()
        {
            Id = "temp.windows", Category = TargetCategory.System, Glyph = GWindows,
            RequiresAdmin = true, RespectsAgeFilter = true,
            RootPatterns = [@"%WINDIR%\Temp"],
        },
        new()
        {
            Id = "win.prefetch", Category = TargetCategory.System, Glyph = GRocket,
            RequiresAdmin = true, Risk = RiskLevel.Moderate, EnabledByDefault = false,
            RootPatterns = [@"%WINDIR%\Prefetch"], FilePatterns = ["*.pf"], Recursive = false,
        },
        new()
        {
            Id = "win.update", Category = TargetCategory.System, Glyph = GUpdate,
            RequiresAdmin = true,
            RootPatterns = [@"%WINDIR%\SoftwareDistribution\Download"],
        },
        new()
        {
            Id = "win.deliveryopt", Category = TargetCategory.System, Glyph = GCloud,
            RequiresAdmin = true,
            RootPatterns = [@"%WINDIR%\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache"],
        },
        new()
        {
            Id = "win.thumbnails", Category = TargetCategory.System, Glyph = GPicture,
            RootPatterns = [@"%LOCALAPPDATA%\Microsoft\Windows\Explorer"],
            FilePatterns = ["thumbcache_*.db", "iconcache_*.db"], Recursive = false,
        },
        new()
        {
            Id = "win.inetcache", Category = TargetCategory.System, Glyph = GGlobe,
            RootPatterns = [@"%LOCALAPPDATA%\Microsoft\Windows\INetCache"],
        },
        new()
        {
            Id = "win.crashdumps", Category = TargetCategory.System, Glyph = GBug,
            RootPatterns = [@"%LOCALAPPDATA%\CrashDumps"],
        },
        new()
        {
            Id = "win.wer", Category = TargetCategory.System, Glyph = GReport,
            RootPatterns =
            [
                @"%PROGRAMDATA%\Microsoft\Windows\WER\ReportQueue",
                @"%PROGRAMDATA%\Microsoft\Windows\WER\ReportArchive",
                @"%PROGRAMDATA%\Microsoft\Windows\WER\Temp",
                @"%LOCALAPPDATA%\Microsoft\Windows\WER\ReportQueue",
                @"%LOCALAPPDATA%\Microsoft\Windows\WER\ReportArchive",
                @"%LOCALAPPDATA%\Microsoft\Windows\WER\Temp",
            ],
        },
        new()
        {
            Id = "win.logs", Category = TargetCategory.System, Glyph = GDocument,
            RequiresAdmin = true,
            RootPatterns = [@"%WINDIR%\Logs\CBS", @"%WINDIR%\Logs\DISM", @"%WINDIR%\Logs\WindowsUpdate", @"%WINDIR%\Logs\MoSetup"],
            FilePatterns = ["*.log", "*.cab", "*.etl"],
        },
        new()
        {
            Id = "win.memdump", Category = TargetCategory.System, Glyph = GMemory,
            RequiresAdmin = true,
            RootPatterns = [@"%WINDIR%\Minidump", @"%WINDIR%\LiveKernelReports"],
            FilePatterns = ["*.dmp"],
        },
        new()
        {
            Id = "win.dxcache", Category = TargetCategory.System, Glyph = GShader,
            RootPatterns = [@"%LOCALAPPDATA%\D3DSCache"],
        },
        new()
        {
            Id = "win.recyclebin", Category = TargetCategory.System, Glyph = GRecycle,
            Kind = TargetKind.RecycleBin, EnabledByDefault = false,
        },

        // ───────────────────────── Browsers ─────────────────────────
        new()
        {
            Id = "browser.chrome", Category = TargetCategory.Browsers, Glyph = GGlobe,
            RootPatterns = Chromium(@"%LOCALAPPDATA%\Google\Chrome\User Data"),
        },
        new()
        {
            Id = "browser.edge", Category = TargetCategory.Browsers, Glyph = GGlobe,
            RootPatterns = Chromium(@"%LOCALAPPDATA%\Microsoft\Edge\User Data"),
        },
        new()
        {
            Id = "browser.brave", Category = TargetCategory.Browsers, Glyph = GGlobe,
            RootPatterns = Chromium(@"%LOCALAPPDATA%\BraveSoftware\Brave-Browser\User Data"),
        },
        new()
        {
            Id = "browser.vivaldi", Category = TargetCategory.Browsers, Glyph = GGlobe,
            RootPatterns = Chromium(@"%LOCALAPPDATA%\Vivaldi\User Data"),
        },
        new()
        {
            Id = "browser.opera", Category = TargetCategory.Browsers, Glyph = GGlobe,
            RootPatterns =
            [
                .. Electron(@"%APPDATA%\Opera Software\Opera Stable"),
                .. Electron(@"%APPDATA%\Opera Software\Opera GX Stable"),
                @"%LOCALAPPDATA%\Opera Software\Opera Stable\Cache",
                @"%LOCALAPPDATA%\Opera Software\Opera GX Stable\Cache",
            ],
        },
        new()
        {
            Id = "browser.yandex", Category = TargetCategory.Browsers, Glyph = GGlobe,
            RootPatterns = Chromium(@"%LOCALAPPDATA%\Yandex\YandexBrowser\User Data"),
        },
        new()
        {
            Id = "browser.firefox", Category = TargetCategory.Browsers, Glyph = GGlobe,
            RootPatterns =
            [
                @"%LOCALAPPDATA%\Mozilla\Firefox\Profiles\*\cache2",
                @"%LOCALAPPDATA%\Mozilla\Firefox\Profiles\*\startupCache",
                @"%LOCALAPPDATA%\Mozilla\Firefox\Profiles\*\shader-cache",
                @"%LOCALAPPDATA%\Mozilla\Firefox\Profiles\*\jumpListCache",
                @"%APPDATA%\Mozilla\Firefox\Profiles\*\shader-cache",
            ],
        },

        // ───────────────────────── Developer ─────────────────────────
        new()
        {
            Id = "dev.pip", Category = TargetCategory.Developer, Glyph = GPython,
            RootPatterns = [@"%LOCALAPPDATA%\pip\cache"],
        },
        new()
        {
            Id = "dev.uv", Category = TargetCategory.Developer, Glyph = GPython,
            RootPatterns = [@"%LOCALAPPDATA%\uv\cache"],
        },
        new()
        {
            Id = "dev.npm", Category = TargetCategory.Developer, Glyph = GPackage,
            RootPatterns = [@"%LOCALAPPDATA%\npm-cache"],
        },
        new()
        {
            Id = "dev.yarn", Category = TargetCategory.Developer, Glyph = GPackage,
            RootPatterns = [@"%LOCALAPPDATA%\Yarn\Cache", @"%LOCALAPPDATA%\Yarn\Berry\cache"],
        },
        new()
        {
            Id = "dev.pnpm", Category = TargetCategory.Developer, Glyph = GPackage,
            Risk = RiskLevel.Moderate,
            RootPatterns = [@"%LOCALAPPDATA%\pnpm-cache", @"%LOCALAPPDATA%\pnpm\store"],
        },
        new()
        {
            Id = "dev.nuget", Category = TargetCategory.Developer, Glyph = GPackage,
            RootPatterns = [@"%LOCALAPPDATA%\NuGet\v3-cache", @"%LOCALAPPDATA%\NuGet\plugins-cache"],
        },
        new()
        {
            Id = "dev.nuget.packages", Category = TargetCategory.Developer, Glyph = GPackage,
            Risk = RiskLevel.Moderate, EnabledByDefault = false,
            RootPatterns = [@"%USERPROFILE%\.nuget\packages"],
        },
        new()
        {
            Id = "dev.gradle", Category = TargetCategory.Developer, Glyph = GCube,
            Risk = RiskLevel.Moderate,
            RootPatterns = [@"%USERPROFILE%\.gradle\caches", @"%USERPROFILE%\.gradle\wrapper\dists"],
        },
        new()
        {
            Id = "dev.maven", Category = TargetCategory.Developer, Glyph = GCube,
            Risk = RiskLevel.Moderate, EnabledByDefault = false,
            RootPatterns = [@"%USERPROFILE%\.m2\repository"],
        },
        new()
        {
            Id = "dev.cargo", Category = TargetCategory.Developer, Glyph = GCube,
            Risk = RiskLevel.Moderate,
            RootPatterns = [@"%USERPROFILE%\.cargo\registry\cache", @"%USERPROFILE%\.cargo\registry\src", @"%USERPROFILE%\.cargo\git\checkouts"],
        },
        new()
        {
            Id = "dev.go", Category = TargetCategory.Developer, Glyph = GCode,
            RootPatterns = [@"%LOCALAPPDATA%\go-build"],
        },
        new()
        {
            Id = "dev.vscode", Category = TargetCategory.Developer, Glyph = GCode,
            RootPatterns =
            [
                .. Electron(@"%APPDATA%\Code"),
                @"%APPDATA%\Code\CachedData",
                @"%APPDATA%\Code\CachedExtensionVSIXs",
                @"%APPDATA%\Code\logs",
                // forks keep the same layout
                @"%APPDATA%\Cursor\CachedData",
                @"%APPDATA%\Cursor\CachedExtensionVSIXs",
                @"%APPDATA%\Windsurf\CachedData",
                @"%APPDATA%\Windsurf\CachedExtensionVSIXs",
            ],
        },
        new()
        {
            Id = "dev.jetbrains", Category = TargetCategory.Developer, Glyph = GCode,
            Risk = RiskLevel.Moderate,
            RootPatterns = [@"%LOCALAPPDATA%\JetBrains\*\caches", @"%LOCALAPPDATA%\JetBrains\*\tmp", @"%LOCALAPPDATA%\JetBrains\*\log"],
        },
        new()
        {
            Id = "dev.visualstudio", Category = TargetCategory.Developer, Glyph = GCode,
            RootPatterns = [@"%LOCALAPPDATA%\Microsoft\VisualStudio\*\ComponentModelCache", @"%LOCALAPPDATA%\Microsoft\VisualStudio\*\Extensions\*\ExtensionCache"],
        },
        new()
        {
            Id = "dev.playwright", Category = TargetCategory.Developer, Glyph = GGlobe,
            Risk = RiskLevel.Moderate, EnabledByDefault = false,
            RootPatterns = [@"%LOCALAPPDATA%\ms-playwright"],
        },
        new()
        {
            Id = "dev.projects", Category = TargetCategory.Developer, Glyph = GCode,
            Risk = RiskLevel.Moderate, EnabledByDefault = false, RemovesRoots = true,
            Finder = () => ProjectArtifacts.Find(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)),
        },
        new()
        {
            Id = "dev.huggingface", Category = TargetCategory.Developer, Glyph = GBrain,
            Risk = RiskLevel.Careful, EnabledByDefault = false,
            RootPatterns = [@"%USERPROFILE%\.cache\huggingface\hub"],
        },
        new()
        {
            Id = "dev.ollama", Category = TargetCategory.Developer, Glyph = GBrain,
            Risk = RiskLevel.Careful, EnabledByDefault = false,
            RootPatterns = [@"%USERPROFILE%\.ollama\models"],
        },
        new()
        {
            Id = "dev.lmstudio", Category = TargetCategory.Developer, Glyph = GBrain,
            Risk = RiskLevel.Careful, EnabledByDefault = false,
            RootPatterns = [@"%USERPROFILE%\.lmstudio\models", @"%USERPROFILE%\.cache\lm-studio\models"],
        },
        new()
        {
            // ~/.cache mixes real caches with model weights, installed runtimes and even database files, so only
            // folders known to be regenerable caches are taken, never the whole directory.
            Id = "dev.xdgcache", Category = TargetCategory.Developer, Glyph = GFolder,
            Fallback = true,
            RootPatterns =
            [
                @"%USERPROFILE%\.cache\fontconfig", @"%USERPROFILE%\.cache\mesa_shader_cache", @"%USERPROFILE%\.cache\gh", @"%USERPROFILE%\.cache\pip",
                @"%USERPROFILE%\.cache\pre-commit", @"%USERPROFILE%\.cache\node-gyp", @"%USERPROFILE%\.cache\typescript", @"%USERPROFILE%\.cache\yarn",
                @"%USERPROFILE%\.cache\puppeteer", @"%USERPROFILE%\.cache\selenium", @"%USERPROFILE%\.cache\black", @"%USERPROFILE%\.cache\mypy",
                @"%USERPROFILE%\.cache\ruff", @"%USERPROFILE%\.cache\pylint", @"%USERPROFILE%\.cache\jedi", @"%USERPROFILE%\.cache\matplotlib",
                @"%USERPROFILE%\.cache\deno", @"%USERPROFILE%\.cache\codex-runtimes\codex-runtime-install-*",
            ],
        },
        new()
        {
            Id = "dev.android", Category = TargetCategory.Developer, Glyph = GAndroid,
            RootPatterns = [@"%USERPROFILE%\.android\cache", @"%USERPROFILE%\.android\build-cache", @"%LOCALAPPDATA%\Android\Sdk\.temp"],
        },
        new()
        {
            Id = "dev.conda", Category = TargetCategory.Developer, Glyph = GPython,
            Risk = RiskLevel.Moderate,
            RootPatterns = [@"%USERPROFILE%\.conda\pkgs", @"%USERPROFILE%\miniconda3\pkgs", @"%USERPROFILE%\anaconda3\pkgs"],
            FilePatterns = ["*.tar.bz2", "*.conda"],
        },
        new()
        {
            Id = "dev.unreal", Category = TargetCategory.Developer, Glyph = GCube,
            Risk = RiskLevel.Moderate,
            RootPatterns = [@"%LOCALAPPDATA%\UnrealEngine\Common\DerivedDataCache"],
        },

        // ───────────────────────── Apps ─────────────────────────
        new()
        {
            Id = "app.discord", Category = TargetCategory.Apps, Glyph = GChat,
            RootPatterns = [.. Electron(@"%APPDATA%\discord"), .. Electron(@"%APPDATA%\discordptb"), .. Electron(@"%APPDATA%\discordcanary")],
        },
        new()
        {
            Id = "app.telegram", Category = TargetCategory.Apps, Glyph = GChat,
            Risk = RiskLevel.Moderate,
            RootPatterns = [@"%APPDATA%\Telegram Desktop\tdata\user_data*\cache", @"%APPDATA%\Telegram Desktop\tdata\user_data*\media_cache"],
        },
        new()
        {
            Id = "app.spotify", Category = TargetCategory.Apps, Glyph = GMusic,
            RootPatterns = [@"%LOCALAPPDATA%\Spotify\Storage", @"%LOCALAPPDATA%\Spotify\Data"],
        },
        new()
        {
            Id = "app.slack", Category = TargetCategory.Apps, Glyph = GChat,
            RootPatterns = [.. Electron(@"%APPDATA%\Slack"), @"%APPDATA%\Slack\logs"],
        },
        new()
        {
            Id = "app.teams", Category = TargetCategory.Apps, Glyph = GChat,
            RootPatterns =
            [
                @"%LOCALAPPDATA%\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams\EBWebView\*\Cache",
                @"%LOCALAPPDATA%\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams\EBWebView\*\Code Cache",
                @"%LOCALAPPDATA%\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams\EBWebView\*\GPUCache",
                .. Electron(@"%APPDATA%\Microsoft\Teams"),
            ],
        },
        new()
        {
            Id = "app.itunes", Category = TargetCategory.Apps, Glyph = GPhone,
            RootPatterns =
            [
                @"%PROGRAMDATA%\Apple Computer\iTunes\iPhone Temporary Files",
                @"%PROGRAMDATA%\Apple Computer\iTunes\iPhone Software Updates",
                @"%PROGRAMDATA%\Apple Computer\iTunes\iPad Software Updates",
                @"%PROGRAMDATA%\Apple Computer\iTunes\iPod Software Updates",
                @"%APPDATA%\Apple Computer\iTunes\iPhone Software Updates",
                @"%APPDATA%\Apple Computer\iTunes\iPad Software Updates",
            ],
        },
        new()
        {
            Id = "app.adobe", Category = TargetCategory.Apps, Glyph = GVideo,
            RootPatterns = [@"%APPDATA%\Adobe\Common\Media Cache Files", @"%APPDATA%\Adobe\Common\Media Cache", @"%APPDATA%\Adobe\Common\Peak Files"],
        },
        new()
        {
            Id = "app.updaters", Category = TargetCategory.Apps, Glyph = GDownload,
            RootPatterns = [@"%LOCALAPPDATA%\SquirrelTemp", @"%LOCALAPPDATA%\*-updater\pending"],
        },
        new()
        {
            Id = "app.storecache", Category = TargetCategory.Apps, Glyph = GGlobe,
            RootPatterns = [@"%LOCALAPPDATA%\Packages\*\AC\INetCache", @"%LOCALAPPDATA%\Packages\*\AC\Temp"],
        },
        new()
        {
            // Claude keeps the Claude Code builds it downloads side by side; only the newest is used.
            Id = "app.claudecode", Category = TargetCategory.Apps, Glyph = GCode, KeepNewest = true,
            RootPatterns = [@"%APPDATA%\Claude\claude-code\*"],
        },
        new()
        {
            Id = "app.codex", Category = TargetCategory.Apps, Glyph = GCode,
            RootPatterns = [@"%USERPROFILE%\.codex\cache"],
        },
        new()
        {
            // Node, Python and LibreOffice for Codex: downloaded again (~1.6 GB) the next time Codex needs them.
            Id = "app.codexruntime", Category = TargetCategory.Apps, Glyph = GPackage,
            Risk = RiskLevel.Moderate, EnabledByDefault = false,
            RootPatterns = [@"%USERPROFILE%\.cache\codex-runtimes\codex-primary-runtime"],
        },
        new()
        {
            // Every other Electron / Chromium-based app (Claude, Notion, Figma, Obsidian…).
            Id = "app.electron", Category = TargetCategory.Apps, Glyph = GChat,
            Risk = RiskLevel.Moderate, Fallback = true,
            RootPatterns = [.. Electron(@"%APPDATA%\*"), .. Electron(@"%LOCALAPPDATA%\*")],
        },

        // ───────────────────────── Gaming ─────────────────────────
        new()
        {
            Id = "game.nvidia.shaders", Category = TargetCategory.Gaming, Glyph = GShader,
            Risk = RiskLevel.Moderate,
            RootPatterns = [@"%LOCALAPPDATA%\NVIDIA\DXCache", @"%LOCALAPPDATA%\NVIDIA\GLCache", @"%LOCALAPPDATA%\NVIDIA Corporation\NV_Cache", @"%PROGRAMDATA%\NVIDIA Corporation\NV_Cache"],
        },
        new()
        {
            Id = "game.nvidia.installers", Category = TargetCategory.Gaming, Glyph = GDriver,
            RootPatterns = [@"%PROGRAMDATA%\NVIDIA Corporation\NVIDIA App\UpdateFramework\ota-artifacts", @"%PROGRAMDATA%\NVIDIA Corporation\Downloader", @"%PROGRAMDATA%\NVIDIA\Downloader"],
        },
        new()
        {
            Id = "game.amd.shaders", Category = TargetCategory.Gaming, Glyph = GShader,
            Risk = RiskLevel.Moderate,
            RootPatterns = [@"%LOCALAPPDATA%\AMD\DxCache", @"%LOCALAPPDATA%\AMD\DxcCache", @"%LOCALAPPDATA%\AMD\GLCache", @"%LOCALAPPDATA%\AMD\VkCache"],
        },
        new()
        {
            Id = "game.intel.shaders", Category = TargetCategory.Gaming, Glyph = GShader,
            Risk = RiskLevel.Moderate,
            RootPatterns = [@"%LOCALAPPDATA%\Intel\ShaderCache"],
        },
        new()
        {
            Id = "game.steam", Category = TargetCategory.Gaming, Glyph = GGame,
            Risk = RiskLevel.Moderate,
            RootPatterns = [@"{steam}\steamapps\shadercache", @"{steam}\appcache\httpcache", @"{steam}\config\htmlcache"],
        },
        new()
        {
            Id = "game.epic", Category = TargetCategory.Gaming, Glyph = GGame,
            RootPatterns = [@"%LOCALAPPDATA%\EpicGamesLauncher\Saved\webcache*", @"%LOCALAPPDATA%\EpicGamesLauncher\Saved\Logs"],
        },
        new()
        {
            Id = "game.gog", Category = TargetCategory.Gaming, Glyph = GGame,
            RootPatterns = [@"%LOCALAPPDATA%\GOG.com\Galaxy\webcache", @"%LOCALAPPDATA%\GOG.com\Galaxy\logs"],
        },
        new()
        {
            Id = "game.ubisoft", Category = TargetCategory.Gaming, Glyph = GGame,
            RootPatterns = [@"%LOCALAPPDATA%\Ubisoft Game Launcher\cache", @"%LOCALAPPDATA%\Ubisoft Game Launcher\logs"],
        },
        new()
        {
            Id = "game.battlenet", Category = TargetCategory.Gaming, Glyph = GGame,
            RootPatterns = [@"%PROGRAMDATA%\Battle.net\Agent\data\cache", @"%LOCALAPPDATA%\Battle.net\Cache", @"%LOCALAPPDATA%\Blizzard Entertainment\Battle.net\Cache"],
        },
        new()
        {
            Id = "game.ea", Category = TargetCategory.Gaming, Glyph = GGame,
            RootPatterns = [@"%LOCALAPPDATA%\Electronic Arts\EA Desktop\CEF", @"%LOCALAPPDATA%\Electronic Arts\EA Desktop\IGOCache", @"%LOCALAPPDATA%\Electronic Arts\EA Desktop\Logs"],
        },
    ];

    public static CleanupTarget CreateCustom(string folder)
    {
        var normalized = PathGuard.Normalize(folder);
        var name = Path.GetFileName(normalized);
        if (string.IsNullOrEmpty(name)) name = normalized;

        return new CleanupTarget
        {
            Id = "custom:" + normalized.ToLowerInvariant(),
            Category = TargetCategory.Custom,
            Glyph = GFolder,
            Risk = RiskLevel.Moderate,
            RootPatterns = [normalized],
            DisplayName = name,
        };
    }
}
