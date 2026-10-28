namespace JunkCleanup.Core;

/// <summary>
/// The built-in list of cleanable locations on Linux: the XDG cache and config folders, plus the copies Flatpak
/// (~/.var/app/ID/…) and Snap (~/snap/NAME/…) keep for sandboxed apps.
/// </summary>
public static class TargetCatalog
{
    // Material Design icon names (Material.Icons.MaterialIconKind)
    private const string GFolder = "FolderOutline";
    private const string GImage = "ImageOutline";
    private const string GBug = "BugOutline";
    private const string GLog = "TextLong";
    private const string GTrash = "TrashCanOutline";
    private const string GGlobe = "Web";
    private const string GPython = "LanguagePython";
    private const string GPackage = "PackageVariantClosed";
    private const string GCube = "CubeOutline";
    private const string GCode = "CodeBraces";
    private const string GConsole = "Console";
    private const string GBrain = "Brain";
    private const string GAndroid = "Android";
    private const string GTheater = "AnimationPlayOutline";
    private const string GChat = "ChatOutline";
    private const string GSend = "Send";
    private const string GMusic = "MusicNote";
    private const string GApps = "ApplicationOutline";
    private const string GGame = "GamepadVariantOutline";
    private const string GGpu = "Gpu";

    private const string Cache = "$XDG_CACHE_HOME";
    private const string Config = "$XDG_CONFIG_HOME";
    private const string Data = "$XDG_DATA_HOME";

    /// <summary>The caches Chromium keeps: the HTTP cache under ~/.cache, the rest next to each profile.</summary>
    private static string[] Chromium(string caches, string userData) =>
    [
        caches,
        $"{userData}/*/Cache", // the HTTP cache when the browser keeps it in the profile (Snap's Chromium)
        $"{userData}/*/Code Cache",
        $"{userData}/*/GPUCache",
        $"{userData}/*/DawnCache",
        $"{userData}/*/DawnWebGPUCache",
        $"{userData}/*/DawnGraphiteCache",
        $"{userData}/*/Service Worker/CacheStorage",
        $"{userData}/*/Service Worker/ScriptCache",
        $"{userData}/GrShaderCache",
        $"{userData}/ShaderCache",
        $"{userData}/GraphiteDawnCache",
    ];

    /// <summary>The same caches for Electron apps, which keep one profile directly in their folder.</summary>
    private static string[] Electron(string appRoot) =>
    [
        $"{appRoot}/Cache",
        $"{appRoot}/Code Cache",
        $"{appRoot}/GPUCache",
        $"{appRoot}/DawnCache",
        $"{appRoot}/DawnWebGPUCache",
        $"{appRoot}/DawnGraphiteCache",
        $"{appRoot}/Service Worker/CacheStorage",
        $"{appRoot}/Service Worker/ScriptCache",
    ];

    /// <summary>A Flatpak app's own XDG folders.</summary>
    private static string Flatpak(string appId, string kind) => $"~/.var/app/{appId}/{kind}";

    /// <summary>A Snap's per-revision and shared home folders ("current" is a symlink and is not walked).</summary>
    private static string[] Snap(string name, string relative) => [$"~/snap/{name}/*/{relative}"];

    private static string[] Steam(string relative) =>
    [
        $"{Data}/Steam/{relative}",
        $"~/.steam/steam/{relative}", // usually a link to the folder above; resolved and counted once
        $"~/.steam/debian-installation/{relative}",
        $"~/.var/app/com.valvesoftware.Steam/.local/share/Steam/{relative}",
        $"~/snap/steam/common/.local/share/Steam/{relative}",
    ];

    public static IReadOnlyList<CleanupTarget> All { get; } =
    [
        // ───────────────────────── System ─────────────────────────
        new()
        {
            Id = "linux.thumbnails", Category = TargetCategory.System, Glyph = GImage,
            RootPatterns = [$"{Cache}/thumbnails"],
        },
        new()
        {
            // Ubuntu's apport writes crash reports here; only the ones owned by you can be removed.
            Id = "linux.crash", Category = TargetCategory.System, Glyph = GBug,
            RootPatterns = ["/var/crash"], FilePatterns = ["*.crash"], Recursive = false,
        },
        new()
        {
            // The system journal belongs to root (see the insight with its vacuum command); these are the user's own logs.
            Id = "linux.logs", Category = TargetCategory.System, Glyph = GLog,
            RootPatterns = [$"{Data}/xorg", $"{Data}/sddm"], FilePatterns = ["*.log", "*.log.old"],
        },
        new()
        {
            Id = "linux.trash", Category = TargetCategory.System, Glyph = GTrash,
            Kind = TargetKind.RecycleBin, EnabledByDefault = false,
        },

        // ───────────────────────── Browsers ─────────────────────────
        new()
        {
            Id = "browser.chrome", Category = TargetCategory.Browsers, Glyph = GGlobe,
            RootPatterns =
            [
                .. Chromium($"{Cache}/google-chrome", $"{Config}/google-chrome"),
                .. Chromium(Flatpak("com.google.Chrome", "cache/google-chrome"), Flatpak("com.google.Chrome", "config/google-chrome")),
            ],
        },
        new()
        {
            Id = "browser.chromium", Category = TargetCategory.Browsers, Glyph = GGlobe,
            RootPatterns =
            [
                .. Chromium($"{Cache}/chromium", $"{Config}/chromium"),
                .. Chromium("~/snap/chromium/common/.cache/chromium", "~/snap/chromium/common/chromium"),
                .. Chromium(Flatpak("org.chromium.Chromium", "cache/chromium"), Flatpak("org.chromium.Chromium", "config/chromium")),
            ],
        },
        new()
        {
            Id = "browser.edge", Category = TargetCategory.Browsers, Glyph = GGlobe,
            RootPatterns =
            [
                .. Chromium($"{Cache}/microsoft-edge", $"{Config}/microsoft-edge"),
                .. Chromium(Flatpak("com.microsoft.Edge", "cache/microsoft-edge"), Flatpak("com.microsoft.Edge", "config/microsoft-edge")),
            ],
        },
        new()
        {
            Id = "browser.brave", Category = TargetCategory.Browsers, Glyph = GGlobe,
            RootPatterns =
            [
                .. Chromium($"{Cache}/BraveSoftware/Brave-Browser", $"{Config}/BraveSoftware/Brave-Browser"),
                .. Chromium(Flatpak("com.brave.Browser", "cache/BraveSoftware/Brave-Browser"), Flatpak("com.brave.Browser", "config/BraveSoftware/Brave-Browser")),
                .. Chromium("~/snap/brave/common/.cache/BraveSoftware/Brave-Browser", "~/snap/brave/current/.config/BraveSoftware/Brave-Browser"),
            ],
        },
        new()
        {
            Id = "browser.vivaldi", Category = TargetCategory.Browsers, Glyph = GGlobe,
            RootPatterns = Chromium($"{Cache}/vivaldi", $"{Config}/vivaldi"),
        },
        new()
        {
            Id = "browser.opera", Category = TargetCategory.Browsers, Glyph = GGlobe,
            RootPatterns = [$"{Cache}/opera", .. Electron($"{Config}/opera")],
        },
        new()
        {
            Id = "browser.yandex", Category = TargetCategory.Browsers, Glyph = GGlobe,
            RootPatterns = Chromium($"{Cache}/yandex-browser", $"{Config}/yandex-browser"),
        },
        new()
        {
            // Firefox keeps each profile's disk cache in a folder of its own under ~/.cache, so the whole folder goes.
            Id = "browser.firefox", Category = TargetCategory.Browsers, Glyph = GGlobe,
            RootPatterns =
            [
                $"{Cache}/mozilla/firefox/*",
                "~/snap/firefox/common/.cache/mozilla/firefox/*",
                Flatpak("org.mozilla.firefox", "cache/mozilla/firefox/*"),
                "~/.mozilla/firefox/*/shader-cache",
                $"{Config}/mozilla/firefox/*/shader-cache",
                "~/snap/firefox/common/.mozilla/firefox/*/shader-cache",
                Flatpak("org.mozilla.firefox", ".mozilla/firefox/*/shader-cache"),
            ],
        },

        // ───────────────────────── Developer ─────────────────────────
        new()
        {
            Id = "dev.pip", Category = TargetCategory.Developer, Glyph = GPython,
            RootPatterns = [$"{Cache}/pip"],
        },
        new()
        {
            Id = "dev.uv", Category = TargetCategory.Developer, Glyph = GPython,
            RootPatterns = [$"{Cache}/uv"],
        },
        new()
        {
            Id = "dev.npm", Category = TargetCategory.Developer, Glyph = GPackage,
            RootPatterns = ["~/.npm/_cacache", "~/.npm/_npx", "~/.npm/_logs"],
        },
        new()
        {
            Id = "dev.yarn", Category = TargetCategory.Developer, Glyph = GPackage,
            RootPatterns = [$"{Cache}/yarn", "~/.yarn/berry/cache"],
        },
        new()
        {
            Id = "dev.pnpm", Category = TargetCategory.Developer, Glyph = GPackage,
            Risk = RiskLevel.Moderate,
            RootPatterns = [$"{Data}/pnpm/store", $"{Cache}/pnpm"],
        },
        new()
        {
            Id = "dev.bun", Category = TargetCategory.Developer, Glyph = GPackage,
            RootPatterns = ["~/.bun/install/cache"],
        },
        new()
        {
            Id = "dev.nuget", Category = TargetCategory.Developer, Glyph = GPackage,
            RootPatterns = [$"{Data}/NuGet/http-cache", $"{Data}/NuGet/v3-cache", $"{Data}/NuGet/plugins-cache"],
        },
        new()
        {
            Id = "dev.nuget.packages", Category = TargetCategory.Developer, Glyph = GPackage,
            Risk = RiskLevel.Moderate, EnabledByDefault = false,
            RootPatterns = ["~/.nuget/packages"],
        },
        new()
        {
            Id = "dev.gradle", Category = TargetCategory.Developer, Glyph = GCube,
            Risk = RiskLevel.Moderate,
            RootPatterns = ["~/.gradle/caches", "~/.gradle/wrapper/dists"],
        },
        new()
        {
            Id = "dev.maven", Category = TargetCategory.Developer, Glyph = GCube,
            Risk = RiskLevel.Moderate, EnabledByDefault = false,
            RootPatterns = ["~/.m2/repository"],
        },
        new()
        {
            Id = "dev.cargo", Category = TargetCategory.Developer, Glyph = GCube,
            Risk = RiskLevel.Moderate,
            RootPatterns = ["~/.cargo/registry/cache", "~/.cargo/registry/src", "~/.cargo/git/checkouts"],
        },
        new()
        {
            Id = "dev.go", Category = TargetCategory.Developer, Glyph = GCode,
            RootPatterns = [$"{Cache}/go-build"],
        },
        new()
        {
            Id = "dev.conda", Category = TargetCategory.Developer, Glyph = GPython,
            Risk = RiskLevel.Moderate,
            RootPatterns = ["~/.conda/pkgs", "~/miniconda3/pkgs", "~/anaconda3/pkgs", "~/miniforge3/pkgs", "~/mambaforge/pkgs"],
            FilePatterns = ["*.tar.bz2", "*.conda"],
        },
        new()
        {
            Id = "dev.android", Category = TargetCategory.Developer, Glyph = GAndroid,
            RootPatterns = ["~/.android/cache", "~/.android/build-cache"],
        },
        new()
        {
            Id = "dev.vscode", Category = TargetCategory.Developer, Glyph = GCode,
            RootPatterns =
            [
                .. Electron($"{Config}/Code"),
                $"{Config}/Code/CachedData",
                $"{Config}/Code/CachedExtensionVSIXs",
                $"{Config}/Code/logs",
                .. Electron(Flatpak("com.visualstudio.code", "config/Code")),
                // forks keep the same layout
                $"{Config}/VSCodium/CachedData",
                $"{Config}/VSCodium/CachedExtensionVSIXs",
                $"{Config}/Cursor/CachedData",
                $"{Config}/Cursor/CachedExtensionVSIXs",
                $"{Config}/Windsurf/CachedData",
                $"{Config}/Windsurf/CachedExtensionVSIXs",
            ],
        },
        new()
        {
            Id = "dev.jetbrains", Category = TargetCategory.Developer, Glyph = GCode,
            Risk = RiskLevel.Moderate,
            RootPatterns = [$"{Cache}/JetBrains/*"],
        },
        new()
        {
            Id = "dev.playwright", Category = TargetCategory.Developer, Glyph = GTheater,
            Risk = RiskLevel.Careful, EnabledByDefault = false,
            RootPatterns = [$"{Cache}/ms-playwright"],
        },
        new()
        {
            Id = "dev.huggingface", Category = TargetCategory.Developer, Glyph = GBrain,
            Risk = RiskLevel.Careful, EnabledByDefault = false,
            RootPatterns = [$"{Cache}/huggingface/hub"],
        },
        new()
        {
            Id = "dev.ollama", Category = TargetCategory.Developer, Glyph = GBrain,
            Risk = RiskLevel.Careful, EnabledByDefault = false,
            RootPatterns = ["~/.ollama/models"],
        },
        new()
        {
            Id = "dev.lmstudio", Category = TargetCategory.Developer, Glyph = GBrain,
            Risk = RiskLevel.Careful, EnabledByDefault = false,
            RootPatterns = ["~/.lmstudio/models", $"{Cache}/lm-studio/models"],
        },
        new()
        {
            // ~/.cache mixes real caches with model weights, installed runtimes and even database files, so only
            // folders known to be regenerable caches are taken, never the whole directory.
            Id = "dev.xdgcache", Category = TargetCategory.Developer, Glyph = GFolder,
            Fallback = true,
            RootPatterns =
            [
                $"{Cache}/fontconfig", $"{Cache}/gh", $"{Cache}/pre-commit", $"{Cache}/node-gyp", $"{Cache}/typescript",
                $"{Cache}/puppeteer", $"{Cache}/selenium", $"{Cache}/black", $"{Cache}/mypy", $"{Cache}/ruff", $"{Cache}/pylint",
                $"{Cache}/jedi", $"{Cache}/matplotlib", $"{Cache}/deno", $"{Cache}/composer", $"{Cache}/golangci-lint",
                $"{Cache}/electron", $"{Cache}/electron-builder", $"{Cache}/node/corepack", $"{Cache}/prisma", $"{Cache}/Cypress",
                $"{Cache}/pip-tools", $"{Cache}/pypoetry/cache", $"{Cache}/pypoetry/artifacts", $"{Cache}/codex-runtimes/codex-runtime-install-*",
            ],
        },

        // ───────────────────────── Apps ─────────────────────────
        new()
        {
            Id = "app.discord", Category = TargetCategory.Apps, Glyph = GChat,
            RootPatterns =
            [
                .. Electron($"{Config}/discord"), .. Electron($"{Config}/discordptb"), .. Electron($"{Config}/discordcanary"),
                .. Electron(Flatpak("com.discordapp.Discord", "config/discord")),
                .. Electron("~/snap/discord/*/.config/discord"),
            ],
        },
        new()
        {
            Id = "app.slack", Category = TargetCategory.Apps, Glyph = GChat,
            RootPatterns =
            [
                .. Electron($"{Config}/Slack"), $"{Config}/Slack/logs",
                .. Electron(Flatpak("com.slack.Slack", "config/Slack")),
                .. Electron("~/snap/slack/*/.config/Slack"),
            ],
        },
        new()
        {
            Id = "app.telegram", Category = TargetCategory.Apps, Glyph = GSend,
            Risk = RiskLevel.Moderate,
            RootPatterns =
            [
                $"{Data}/TelegramDesktop/tdata/user_data*/cache", $"{Data}/TelegramDesktop/tdata/user_data*/media_cache",
                Flatpak("org.telegram.desktop", "data/TelegramDesktop/tdata/user_data*/cache"),
                Flatpak("org.telegram.desktop", "data/TelegramDesktop/tdata/user_data*/media_cache"),
                .. Snap("telegram-desktop", ".local/share/TelegramDesktop/tdata/user_data*/cache"),
                .. Snap("telegram-desktop", ".local/share/TelegramDesktop/tdata/user_data*/media_cache"),
            ],
        },
        new()
        {
            Id = "app.spotify", Category = TargetCategory.Apps, Glyph = GMusic,
            Risk = RiskLevel.Moderate,
            RootPatterns = [$"{Cache}/spotify", Flatpak("com.spotify.Client", "cache/spotify"), "~/snap/spotify/common/.cache/spotify"],
        },
        new()
        {
            Id = "app.codex", Category = TargetCategory.Apps, Glyph = GConsole,
            RootPatterns = ["~/.codex/cache"],
        },
        new()
        {
            // Node, Python and LibreOffice for Codex: downloaded again (~1.6 GB) the next time Codex needs them.
            Id = "app.codexruntime", Category = TargetCategory.Apps, Glyph = GPackage,
            Risk = RiskLevel.Moderate, EnabledByDefault = false,
            RootPatterns = [$"{Cache}/codex-runtimes/codex-primary-runtime"],
        },
        new()
        {
            // Each Flatpak app's own ~/.cache, folder by folder: one a specific target above covers (a browser's
            // profile cache) is left to it, the rest (fontconfig, mesa shaders, the app's own) is taken.
            Id = "app.flatpak", Category = TargetCategory.Apps, Glyph = GApps,
            Fallback = true, RespectsAgeFilter = true,
            RootPatterns = ["~/.var/app/*/cache/*"],
        },
        new()
        {
            // Each Snap's own ~/.cache (per revision and shared), folder by folder like Flatpak's. The desktop launcher
            // keeps its GIO and input-method module caches there and rebuilds them only when the runtime changes.
            Id = "app.snap", Category = TargetCategory.Apps, Glyph = GApps,
            Fallback = true, RespectsAgeFilter = true,
            RootPatterns = ["~/snap/*/*/.cache/*"],
            ExcludedNames = ["gio-modules", "immodules"],
        },
        new()
        {
            // Every other Electron / Chromium-based app (Obsidian, Notion, Figma, Signal…).
            Id = "app.electron", Category = TargetCategory.Apps, Glyph = GChat,
            Risk = RiskLevel.Moderate, Fallback = true,
            RootPatterns = Electron($"{Config}/*"),
        },

        // ───────────────────────── Gaming ─────────────────────────
        new()
        {
            Id = "game.steam", Category = TargetCategory.Gaming, Glyph = GGame,
            Risk = RiskLevel.Moderate,
            RootPatterns = [.. Steam("steamapps/shadercache"), .. Steam("appcache/httpcache"), .. Steam("config/htmlcache")],
        },
        new()
        {
            Id = "game.shaders", Category = TargetCategory.Gaming, Glyph = GGpu,
            Risk = RiskLevel.Moderate,
            RootPatterns =
            [
                $"{Cache}/mesa_shader_cache", $"{Cache}/mesa_shader_cache_db", $"{Cache}/radv_builtin_shaders",
                $"{Cache}/nvidia/GLCache", "~/.nv/GLCache", "~/.nv/ComputeCache",
            ],
        },
    ];

    public static CleanupTarget CreateCustom(string folder)
    {
        var normalized = PathGuard.Normalize(folder);
        var name = Path.GetFileName(normalized);
        if (string.IsNullOrEmpty(name)) name = normalized;

        return new CleanupTarget
        {
            Id = "custom:" + normalized,
            Category = TargetCategory.Custom,
            Glyph = GFolder,
            Risk = RiskLevel.Moderate,
            RootPatterns = [normalized],
            DisplayName = name,
        };
    }
}
