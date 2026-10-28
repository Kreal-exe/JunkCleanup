namespace JunkCleanup.Core;

/// <summary>
/// The Disk page on Linux: known space consumers (with the parts that are safe to remove), the folders to look
/// through, and how what is found is filed.
/// </summary>
public static class SpaceCatalog
{
    private const string Cache = "$XDG_CACHE_HOME";
    private const string Config = "$XDG_CONFIG_HOME";
    private const string Data = "$XDG_DATA_HOME";

    public static IReadOnlyList<SpaceRule> Rules { get; } =
    [
        // ── AI agents and models ──
        new()
        {
            // Hermes Agent (Nous Research): its caches and pre-restore backups can go; its runtimes, code, history,
            // memories and skills are the agent itself.
            Id = "hermes", Segment = SpaceSegment.Developer, Glyph = "Robot", Paths = ["~/.hermes"],
            Children =
            [
                new("cache", "cache", SpaceRisk.Safe), new("cache", "hermes-agent/.cache", SpaceRisk.Safe),
                new("cache", "image_cache", SpaceRisk.Safe), new("cache", "audio_cache", SpaceRisk.Safe),
                new("backups", "backups", SpaceRisk.Careful), new("logs", "logs", SpaceRisk.Moderate),
                new("app", "installs", SpaceRisk.Keep), new("app", "hermes-agent", SpaceRisk.Keep), new("app", "tools", SpaceRisk.Keep),
            ],
        },
        new() { Id = "huggingface", Segment = SpaceSegment.Models, Glyph = "Brain", Paths = [$"{Cache}/huggingface/hub"], Risk = SpaceRisk.Careful, ListKind = "model" },
        new() { Id = "ollama", Segment = SpaceSegment.Models, Glyph = "Brain", Paths = ["~/.ollama/models"], Risk = SpaceRisk.Careful, Command = "ollama rm <model>" },
        new() { Id = "lmstudio", Segment = SpaceSegment.Models, Glyph = "Brain", Paths = ["~/.lmstudio/models", $"{Cache}/lm-studio/models"], Risk = SpaceRisk.Careful, ListKind = "model" },

        // ── emulators, virtual machines, containers ──
        new() { Id = "android.images", Segment = SpaceSegment.VirtualMachines, Glyph = "Android", Paths = ["~/Android/Sdk/system-images/*/*"], Risk = SpaceRisk.Moderate, ListKind = "image" },
        new() { Id = "android.avd", Segment = SpaceSegment.VirtualMachines, Glyph = "Cellphone", Paths = ["~/.android/avd"], Risk = SpaceRisk.Careful, ListKind = "vm" },
        new() { Id = "vms", Segment = SpaceSegment.VirtualMachines, Glyph = "Monitor", Paths = [$"{Data}/gnome-boxes/images", $"{Data}/libvirt/images", "~/VirtualBox VMs"], Risk = SpaceRisk.Careful, ListKind = "vm" },
        new() { Id = "containers", Segment = SpaceSegment.VirtualMachines, Glyph = "Docker", Paths = [$"{Data}/containers", $"{Data}/docker"], Command = "podman system prune -a  /  docker system prune -a" },

        // ── apps ──
        new() { Id = "flatpak", Segment = SpaceSegment.Apps, Glyph = "PackageVariant", Paths = [$"{Data}/flatpak", "/var/lib/flatpak"], Command = "flatpak uninstall --unused" },
        new() { Id = "snap", Segment = SpaceSegment.Apps, Glyph = "PackageVariant", Paths = ["/var/lib/snapd/snaps"], Command = "sudo snap set system refresh.retain=2" },
        new() { Id = "games", Segment = SpaceSegment.Apps, Glyph = "GamepadVariantOutline", Paths = [$"{Data}/Steam/steamapps/common"], ListKind = "game" },
        new() { Id = "opt", Segment = SpaceSegment.Apps, Glyph = "ApplicationOutline", Paths = ["/opt"] },

        // ── system ──
        new() { Id = "journal", Segment = SpaceSegment.System, Glyph = "TextLong", Paths = ["/var/log/journal"], Command = "sudo journalctl --vacuum-size=200M" },
        new() { Id = "pkgcache.apt", Segment = SpaceSegment.System, Glyph = "PackageVariantClosed", Paths = ["/var/cache/apt/archives"], Command = "sudo apt clean" },
        new() { Id = "pkgcache.pacman", Segment = SpaceSegment.System, Glyph = "PackageVariantClosed", Paths = ["/var/cache/pacman/pkg"], Command = "sudo pacman -Sc" },
        new() { Id = "pkgcache.dnf", Segment = SpaceSegment.System, Glyph = "PackageVariantClosed", Paths = ["/var/cache/dnf", "/var/cache/libdnf5"], Command = "sudo dnf clean packages" },
        new() { Id = "system", Segment = SpaceSegment.System, Glyph = "Linux", Paths = ["/usr"] },
        new() { Id = "trash", Segment = SpaceSegment.Other, Glyph = "TrashCanOutline", Paths = [$"{Data}/Trash"] },
    ];

    public static SpaceScope Scope()
    {
        var home = PathResolver.Home;
        return new SpaceScope
        {
            Rules = Rules,
            Roots = [("~", SpaceSegment.Other)],
            Containers = ["~/.local", $"{Data}", $"{Config}", $"{Cache}", "~/.var/app", "~/snap"],
            Filed = [("~/.local", SpaceSegment.Apps), ($"{Config}", SpaceSegment.Apps), ("~/.var", SpaceSegment.Apps), ("~/snap", SpaceSegment.Apps), ($"{Cache}", SpaceSegment.Other)],
            KeepNames =
            [
                "google-chrome", "chromium", "BraveSoftware", "vivaldi", "microsoft-edge", "opera", "yandex-browser", "mozilla",
                "thunderbird", "evolution", "keyrings", "gnome-shell", "dconf", "Code", "VSCodium", "JetBrains", "TelegramDesktop",
                "discord", "Slack", "Signal", "flatpak", "applications", "fonts", "icons", "themes",
            ],
            PersonalFolders = ["Desktop", "Documents", "Downloads", "Music", "Pictures", "Videos", "Public", "Templates", .. PathGuard.UserDirs(home)],
            VolumePath = home,
            Glyphs = ("FolderOutline", "FolderAccountOutline", "Broom"),
        };
    }
}
