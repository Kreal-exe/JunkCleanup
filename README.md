<p align="center">
  <img src="docs/logo.png" width="112" alt="JunkCleanup logo">
</p>

<h1 align="center">JunkCleanup</h1>

<p align="center">
  <b>Reclaim your disk. Beautifully.</b><br>
  A fast cleaner for Windows, macOS and Linux — caches, temp files and leftovers, with a UI you actually want to open.
</p>

<p align="center">
  <a href="https://github.com/Kreal-exe/JunkCleanup/actions/workflows/build.yml"><img src="https://github.com/Kreal-exe/JunkCleanup/actions/workflows/build.yml/badge.svg" alt="Build"></a>
  <a href="https://github.com/Kreal-exe/JunkCleanup/releases"><img src="https://img.shields.io/github/v/release/Kreal-exe/JunkCleanup?include_prereleases&label=release" alt="Release"></a>
  <img src="https://img.shields.io/badge/.NET-10-512BD4" alt=".NET 10">
  <img src="https://img.shields.io/badge/WPF-native-0078D4" alt="WPF">
  <img src="https://img.shields.io/badge/macOS-Objective--C%20%2F%20AppKit-000000?logo=apple" alt="macOS">
  <img src="https://img.shields.io/badge/Linux-Avalonia-FCC624?logo=linux&logoColor=black" alt="Linux">
  <img src="https://img.shields.io/badge/languages-19-22D3EE" alt="19 languages">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-34D399" alt="MIT"></a>
</p>

<p align="center">
  <img src="docs/dashboard.png" width="900" alt="Dashboard">
</p>

---

## Why

Windows Settings says *"Installed apps: 107 GB"* and leaves you guessing. Most of that is not apps — it is browser caches, package-manager caches, shader caches, old installers, firmware downloads and other junk that regenerates itself the moment you need it. JunkCleanup knows where that junk lives, measures it in under a second, and lets you throw it out with one click — safely.

Macs fill up the same way: `~/Library/Caches`, Xcode's DerivedData, Homebrew, npm, uv and Gradle caches, browser
caches. The macOS app is a native twin of the Windows one — same look, same motion, same safety model. On Linux it is
`~/.cache`, Flatpak and Snap copies of every app's caches, browser profiles and package managers; the Linux app shares
the Windows app's scan and clean engine and looks the same.

## Highlights

- **65 built-in targets** across System, Browsers, Developer tools, Apps and Gaming — from `%TEMP%` and thumbnail caches to pip / npm / NuGet / Cargo, Chrome / Edge / Firefox, Discord / Telegram / Spotify, NVIDIA / AMD shader caches, Steam / Epic / GOG launchers, iTunes firmware leftovers, Microsoft Store app caches, old Claude Code builds, Codex caches, every other Electron app and `~/.cache` — and more.
- **Fast, parallel scanning.** The scan starts as soon as the app opens (a switch in Settings); 130 000+ files are measured in well under a second, and the dashboard counts up live while it runs.
- **Risk-aware.** Every target is tagged *Safe*, *Moderate* or *Careful*, with a one-line explanation of what deleting it costs you. *Safe only* selects the no-brainers.
- **Safe by design.** Caches and temp files are deleted for good (apps rebuild them); what you remove by hand goes to the Recycle Bin. Only files underneath scanned locations are ever touched; drive roots, Windows, Program Files and your personal folders are hard-blocked. Recent temp files can be skipped automatically.
- **Insights.** Things the cleaner will not touch but you should know about: the hibernation file, page file, `Windows.old`, a full Recycle Bin — with the exact command or settings page to deal with them.
- **Disk page: where the space really goes.** One bar over the whole disk, in bands — system, apps, cleanable caches, developer tools, AI models, virtual machines and emulators, your files, other — and every large folder below it, largest first, measured so each byte counts once. Known space hogs are split into their parts with a risk each (Hermes Agent: its caches are *Safe*, its pre-restore backups *Careful*, its runtimes and memories *Keep*; Hugging Face, Ollama and LM Studio models one row per model; Android system images and emulators, WSL, Docker, VMs, Steam games). *Safe* parts go with one click (**Remove safe items**), anything not *Keep* can be deleted at your discretion with a two-step confirm, and what only a tool or root can remove comes with the command to copy. What is used but cannot be read is shown honestly as *System and other*. On Windows, pick the drive to map: the system drive is read through your profile and every folder at its root, any other drive folder by folder from its root, with the caches and known items that live on it.
- **Look inside, delete one thing.** Click any target (or a row of *Largest targets*) to open its contents, largest first: every folder and file with an icon for what it is — models, archives, video, code — its share, *Show in Explorer / Finder* and its own *Delete*. Clear one 4 GB model out of the Hugging Face cache without touching the rest.
- **Custom folders.** Add your own cache directories; they are scanned and cleaned like any other target.
- **Administrator aware.** System locations that need elevation are marked; one click restarts the app elevated.
- **A UI that moves.** Mica backdrop on Windows 11, dark and light themes, animated counters, a live breakdown bar, staggered card entrances, smooth expanders, a sliding navigation indicator, confetti when you are done.
- **Stop any time.** Cleaning runs targets side by side and files in parallel; *Stop* (or Esc) ends it between files and keeps what is left.
- **19 languages**, auto-detected from the system and switchable live: English, Русский, Українська, Deutsch, Français, Español, Polski, Português, Italiano, Nederlands, Türkçe, Bahasa Indonesia, Tiếng Việt, हिन्दी, ไทย, 简体中文, 繁體中文, 日本語, 한국어.

## Screenshots

| Targets | Largest targets |
|:--:|:--:|
| <img src="docs/targets.png" width="440" alt="Targets"> | <img src="docs/largest.png" width="440" alt="Largest targets"> |

| Light theme | Settings |
|:--:|:--:|
| <img src="docs/light.png" width="440" alt="Light theme"> | <img src="docs/settings.png" width="440" alt="Settings"> |

| Disk map | Pick a drive |
|:--:|:--:|
| <img src="docs/disk.png" width="440" alt="Disk page on Windows"> | <img src="docs/disk-drives.png" width="440" alt="Drive picker on the Disk page"> |

## macOS

<p align="center">
  <img src="docs/mac-dashboard.png" width="900" alt="JunkCleanup on macOS">
</p>

| Targets | Light theme |
|:--:|:--:|
| <img src="docs/mac-targets.png" width="440" alt="Targets on macOS"> | <img src="docs/mac-light.png" width="440" alt="Light theme on macOS"> |

| Disk map | Hermes Agent, part by part |
|:--:|:--:|
| <img src="docs/mac-disk.png" width="440" alt="Disk page on macOS"> | <img src="docs/mac-disk-parts.png" width="440" alt="Hermes split into Keep and Careful parts on macOS"> |

| Largest entries | Settings |
|:--:|:--:|
| <img src="docs/mac-expanded.png" width="440" alt="Expanded target on macOS"> | <img src="docs/mac-settings.png" width="440" alt="Settings on macOS"> |

<p align="center">
  <img src="docs/mac-details.png" width="900" alt="A target's contents, each entry removable on its own">
</p>

Native Objective-C and AppKit, drawn with Core Animation: the same palette, cards, gradient buttons, ring, counters,
staggered entrances, drifting background and confetti as the WPF app, with the same easing curves and timings. The
window is translucent (vibrancy), follows the system theme if asked, and uses SF Symbols and the system font.

**60 macOS targets** across the same five categories:

| Category | Targets |
|---|---|
| System | App caches (`~/Library/Caches`, Apple's own left alone), temporary files (`$TMPDIR`), logs, crash reports, Quick Look thumbnails, saved app state (off), iPhone & iPad backups (careful, off), Trash (off) |
| Browsers | Safari, Chrome, Edge, Brave, Arc, Vivaldi, Yandex, Opera / Opera GX, Firefox |
| Developer | ~/.cache tool caches, Ollama and LM Studio models (careful, off), Xcode DerivedData, device support, archives (off), Simulator caches, Homebrew, CocoaPods, SwiftPM, pip, uv, npm, Yarn, pnpm, Bun, NuGet, Gradle, Maven (off), Cargo, Go, Conda, Android, VS Code, JetBrains, Playwright (off), Hugging Face (careful, off) |
| Apps | Discord, Slack, Teams, Telegram Desktop, Spotify, iOS firmware downloads, Adobe media cache, old Claude Code builds (the newest is kept), Codex cache, Codex runtime (off), every other Electron app (Claude, Notion, Figma…) |
| Gaming | Metal shader cache, Steam, Epic Games Launcher, Battle.net |

Where Windows asks for administrator rights, macOS asks for **Full Disk Access**: Safari's cache, the Trash and iOS
backups are readable only with it. *Grant Full Disk Access* in the title bar opens the right page of System Settings;
targets that need it are marked. Other apps' sandbox containers are never opened, so macOS shows no privacy prompts.

*Also on this disk* reports purgeable space and local Time Machine snapshots, swap files, the sleep image and old
Simulator devices — with the command that deals with them.

## Linux

<p align="center">
  <img src="docs/linux-dashboard.png" width="900" alt="JunkCleanup on Linux">
</p>

| Targets, light theme | Cleaning |
|:--:|:--:|
| <img src="docs/linux-targets-light.png" width="440" alt="Targets on Linux"> | <img src="docs/linux-cleaning.png" width="440" alt="Cleaning on Linux"> |

| Disk map | Hermes Agent, part by part |
|:--:|:--:|
| <img src="docs/linux-disk.png" width="440" alt="Disk page on Linux"> | <img src="docs/linux-disk-parts.png" width="440" alt="Hermes split into Safe, Careful and Keep parts"> |

C# and [Avalonia](https://avaloniaui.net): the scan and clean engines are the Windows app's own
(`src/JunkCleanup/Core`, linked into `LinuxApp`), with a Linux path resolver, path guard, target catalog and Trash on
top. Avalonia draws the same cards, ring, counters, gradient buttons, toggles and entrances on any desktop (GNOME, KDE,
Xfce, tiling window managers) without depending on the GTK or Qt version; the window keeps the desktop's own title
bar. Icons are Material Design icons, the font is Inter, the theme follows the desktop's light or dark preference if
asked.

**44 Linux targets**, found through the XDG base directories (`$XDG_CACHE_HOME`, `$XDG_CONFIG_HOME`, `$XDG_DATA_HOME`
and their defaults) and the copies sandboxed apps keep (`~/.var/app/ID/…` for Flatpak, `~/snap/NAME/…` for Snap):

| Category | Targets |
|---|---|
| System | Thumbnail cache (`~/.cache/thumbnails`), your crash reports in `/var/crash`, Xorg / display-manager session logs, Trash (off) |
| Browsers | Chrome, Chromium, Edge, Brave, Vivaldi, Opera, Yandex, Firefox — native, Snap and Flatpak installs |
| Developer | pip, uv, npm, Yarn, pnpm, Bun, NuGet, NuGet packages (off), Gradle, Maven (off), Cargo, Go, Conda, Android, VS Code / VSCodium / Cursor / Windsurf, JetBrains, Playwright (off), Hugging Face, Ollama and LM Studio models (careful, off), `~/.cache` tool caches |
| Apps | Discord, Slack, Telegram Desktop, Spotify (native, Snap, Flatpak), Codex, every Flatpak app's cache, every Snap's cache, every other Electron app |
| Gaming | Steam (native, `~/.steam`, Flatpak, Snap), Mesa and NVIDIA GPU shader caches |

Files go to the **Trash** as the [freedesktop.org Trash spec](https://specifications.freedesktop.org/trash-spec/latest/)
describes, so Files, Dolphin, Thunar and Nemo show them and can restore them: an item is renamed into
`~/.local/share/Trash/files` with its `.trashinfo`, never copied. An item on another disk goes to that disk's own
`.Trash-UID` folder, and if there is none it is left in place and reported as skipped. Nothing is deleted on the way to
the Trash.

Not touched: the system journal, the package manager's downloads and anything else that belongs to root. *Also on this
disk* shows their size with the command that trims them (`journalctl --vacuum-size`, `apt clean`, `pacman -Sc`,
`dnf clean packages`). Snap's launcher-managed `gio-modules` / `immodules` caches are left alone.

The **Disk** page measures the home folder and the system's big places (`/usr`, `/opt`, Flatpak and Snap installs, the
journal and package caches, which come with their `sudo` command) the first time it opens.

`JunkCleanup --scan` prints every target, the folders it resolved to and its size without opening a window or
changing anything (`--files` lists each file).

**How it was tested.** No Linux machine was at hand, so everything ran in an Ubuntu 24.04 (arm64) virtual machine on
a Mac: the core tests, a real `--scan` after real pip, npm, Go, Firefox (Snap) and Chromium (Snap) use, a clean
through the GUI (889 files, 288 MB to the Trash, browser profiles and settings untouched), the tarball installer and
the AppImage. The screenshots above come from that VM. x86-64 is built and tested by CI on GitHub's Ubuntu runner.

## Download

Grab the latest build from the [Releases](https://github.com/Kreal-exe/JunkCleanup/releases) page:

- `JunkCleanup-Windows-v<version>.exe` — Windows, one file, no .NET needed.
- `JunkCleanup-macOS-v<version>.dmg` — universal (Apple Silicon and Intel), macOS 12 or later.
- `JunkCleanup-Linux-v<version>.AppImage` — Linux x86-64, one file: `chmod +x` and run.

**Windows:** run the exe. No installer, no services, no telemetry. Settings live in
`%AppData%\JunkCleanup\settings.json`. Requires Windows 10 1903 or later; Mica needs Windows 11 22H2+.

**macOS:** open the disk image and drag `JunkCleanup.app` onto *Applications*. The build is not notarized yet, so before
the first launch run **Allow JunkCleanup to open.command** from the disk image (right-click → *Open* the first time): it
copies the app to Applications if needed, clears the quarantine flag and opens it. Or by hand:

```bash
xattr -dr com.apple.quarantine /Applications/JunkCleanup.app
```

Or open it once from *System Settings → Privacy & Security → Open Anyway*. Settings live in
`~/Library/Application Support/JunkCleanup/settings.json`.

**Linux:** `chmod +x` the AppImage and run it (on distributions without FUSE 2, run it with
`APPIMAGE_EXTRACT_AND_RUN=1`). Self-contained, no .NET needed; it uses the system's ICU (`libicu`), which every desktop distribution ships. Settings
live in `~/.config/JunkCleanup/settings.json`.

## What it cleans

<details>
<summary><b>System</b> (13)</summary>

| Target | Location | Risk |
|---|---|---|
| User temp files | `%TEMP%` | Safe |
| Windows temp files | `%WINDIR%\Temp` | Safe · admin |
| Prefetch | `%WINDIR%\Prefetch\*.pf` | Moderate · admin · off by default |
| Windows Update cache | `SoftwareDistribution\Download` | Safe · admin |
| Delivery Optimization | DO cache | Safe · admin |
| Thumbnail & icon cache | `Explorer\thumbcache_*.db`, `iconcache_*.db` | Safe |
| Windows web cache | `INetCache` | Safe |
| Crash dumps | `%LOCALAPPDATA%\CrashDumps` | Safe |
| Error reports | WER queue and archive | Safe |
| Windows logs | CBS, DISM, Windows Update logs | Safe · admin |
| System memory dumps | `Minidump`, `LiveKernelReports` | Safe · admin |
| DirectX shader cache | `D3DSCache` | Safe |
| Recycle Bin | — | off by default |
</details>

<details>
<summary><b>Browsers</b> (7)</summary>

Chrome, Edge, Brave, Vivaldi, Yandex, Opera / Opera GX (all profiles: HTTP cache, code cache, GPU cache, service-worker cache, shader caches) and Firefox (cache2, startup cache, shader cache).
</details>

<details>
<summary><b>Developer</b> (22)</summary>

pip, uv, npm, Yarn, pnpm, NuGet HTTP cache, NuGet packages (off by default), Gradle (caches and downloaded distributions), Maven (off), Cargo, Go build cache, VS Code / Cursor / Windsurf caches, JetBrains IDE caches, Visual Studio caches, Playwright browsers (off), Hugging Face hub (off), Ollama models (off), LM Studio models (off), `~/.cache` tool caches, Android build cache, Conda packages, Unreal derived data.
</details>

<details>
<summary><b>Apps</b> (10)</summary>

Discord, Telegram Desktop, Spotify, Slack, Microsoft Teams, iTunes device firmware, Adobe media cache, leftover Squirrel/Electron updaters, Microsoft Store app caches, old Claude Code builds the Claude app downloaded (the newest is kept), Codex cache, Codex runtime (off: Codex downloads its ~1.6 GB again when needed), and the web caches of every other Electron / Chromium app (Claude, Notion, Figma, Obsidian…).

The *other app caches* catch-all never takes a folder a specific target already owns, so nothing is counted twice. `~/.cache` is not taken whole: next to real caches it holds model weights, installed runtimes and even database files, so only folders known to be regenerable caches are cleaned (fontconfig, Mesa shaders, gh, pip, pre-commit, node-gyp, TypeScript, Yarn, Puppeteer, Selenium, Black, mypy, Ruff, Pylint, Jedi, Matplotlib, Deno, leftover Codex runtime installers).
</details>

<details>
<summary><b>Gaming</b> (10)</summary>

NVIDIA shader cache, NVIDIA driver downloads, AMD shader cache, Intel shader cache, Steam caches, Epic Games Launcher, GOG Galaxy, Ubisoft Connect, Battle.net, EA app.
</details>

Targets that do not exist on your PC are shown dimmed and skipped. The full list with every path lives in [`TargetCatalog.cs`](src/JunkCleanup/Core/TargetCatalog.cs) — adding one is a ten-line change.

## Safety model

The same rules hold on all three systems (on Linux: `/`, `/usr`, `/etc`, `/var`, `/home`, your home folder, the XDG
base folders themselves, Documents, Downloads and the other user dirs — localized names included — `~/.ssh`,
`~/.mozilla`, `~/.var/app`, `~/snap` and any folder that holds one of them are protected, symlinks are judged by where
they point, and files go to the Trash; on macOS: the system folders, `/Applications`, your home folder, Documents,
Desktop, Downloads, `~/Library`, iCloud Drive and app containers are the protected set, and files go to the Trash).

1. **Scanned roots only.** The cleaner receives the exact file list the scanner produced and refuses anything that is not strictly underneath one of the resolved roots ([`PathGuard`](src/JunkCleanup/Core/PathGuard.cs)).
2. **Protected locations.** Drive roots, `Windows`, `System32`, `Program Files`, `ProgramData`, `AppData`, your profile, Documents, Pictures, Downloads, Desktop and OneDrive can never become a root — not even as a custom folder.
3. **Caches go for good, your picks to the Recycle Bin.** On Windows, caches and temporary files are deleted permanently, as CCleaner, BleachBit and Windows' own Disk Cleanup do: apps rebuild them, and in the Recycle Bin they would free nothing. What you remove by hand — a folder on the Disk page, one entry of a target — goes to the Recycle Bin (a switch in Settings). The Recycle Bin is a target of its own and is shown on its own line of the dashboard.
4. **Locked files are skipped**, never forced. The summary tells you how many were in use; running as administrator, they are marked for removal at the next restart.
5. **Administrator when needed.** When a clean leaves files that need administrator rights, JunkCleanup says so and offers to restart elevated; the elevated copy finishes the clean on its own.
6. **No overlap.** A unit test guarantees no two targets ever resolve to nested roots, so nothing is counted or deleted twice.
7. **Reparse points are never followed**, so OneDrive placeholders and junctions are left alone.

## Build from source

### Windows

PowerShell in the repository root, with the [.NET 10 SDK](https://dot.net):

```powershell
.\build.ps1         # → JunkCleanup.exe on the Desktop and opens it (one self-contained file)
.\build.ps1 -Test   # run the xunit suite first
.\build.ps1 -Exe    # also write dist\JunkCleanup-Windows-v<version>.exe
$env:INSTALL_DIR = "D:\Apps\JunkCleanup"; .\build.ps1   # install somewhere else
```

The script is one `dotnet publish`. It builds in a temporary folder and puts the exe straight on the Desktop, leaving
nothing inside the project. No other dependencies beyond `CommunityToolkit.Mvvm`.

Handy flags: `--scan` starts scanning immediately, `--page settings` opens on a given page. `tools/capture.ps1` produces the screenshots in this README.

### macOS

Terminal in the repository root, with only the Xcode Command Line Tools (`xcode-select --install`):

```bash
./build.sh           # → /Applications/JunkCleanup.app (universal), quarantine cleared, opened
./build.sh --test    # run the core tests first
./build.sh --dmg     # also write dist/JunkCleanup-macOS-v<version>.dmg
INSTALL_DIR=~/Applications ./build.sh   # install somewhere else
```

No Xcode project: one `clang` call builds the app outside the project folder and signs it ad hoc. The version is the
`<Version>` of `JunkCleanup.csproj`, and the translations are the Windows app's `Strings/*.json` with
`MacApp/Resources/Strings/*.json` laid over them for the macOS wording.

Handy flags: `--scan`, `--page settings`, `--theme light`, `--lang ru`; `--capture <dir>` scans and saves a PNG of
every page (`--capture-clean` also runs the clean) — the macOS screenshots in this README come from it.

### Linux

With the [.NET 10 SDK](https://dot.net), on Linux (or macOS for the tests):

```bash
./build-linux.sh                 # → dist/JunkCleanup-Linux-v<version>.AppImage (self-contained single file)
./build-linux.sh --test          # run the Linux core tests first
./build-linux.sh --arch arm64    # for 64-bit ARM
```

`dotnet test tests/JunkCleanup.Linux.Tests` runs the Linux core tests — XDG resolution, the path guard, the catalog
against a fake home folder, the freedesktop Trash and scan + clean — on Linux or macOS. Linux-only translations live in
`LinuxApp/Resources/Strings/*.json`, written by `tools/linux-strings.py`.

### Releases

Every push to `main` builds and tests all three apps on GitHub Actions with these same scripts and publishes them as
release `v<Version>`: the exe, the disk image and the AppImage. While the
version stays the same, each push replaces that release's files; a new `<Version>` makes a new release.

## Project layout

```
src/JunkCleanup
├─ Core/           scan & clean engines, disk map (DiskMap.cs, shared with Linux), target and space catalogs, path guard, shell interop
├─ Controls/       animation primitives (Counter, Entrance, Smooth, Arc, SegmentBar, Collapsible, PageHost …)
├─ Localization/   LocalizationManager + Strings/*.json (one flat dictionary per language)
├─ ViewModels/     MVVM layer (CommunityToolkit.Mvvm)
├─ Views/          MainWindow, Dashboard, Targets, Settings, About, overlays
└─ Themes/         Dark.xaml, Light.xaml, Styles.xaml (every control template lives here)
tests/JunkCleanup.Tests   xunit: formatter, path guard, resolver, catalog invariants, localization parity, scan/clean behaviour

MacApp                     the macOS app (Objective-C, AppKit, Core Animation)
├─ Sources/        CCCore (catalog, path guard), CCEngine (scan & clean), CCModel, CCControls, CCPages, CCWindow …
├─ Resources/      Info.plist, AppIcon.icns, Strings/*.json (macOS wording over the shared translations)
├─ Tests/          CoreTests.m: formatter, path guard, catalog, localization parity, scan/clean behaviour
└─ Tools/          make_icon.m

LinuxApp                   the Linux app (C#, Avalonia); Core/Shared links the engines from src/JunkCleanup/Core
├─ Core/           PathResolver (XDG), PathGuard, TargetCatalog, Trash (freedesktop spec), Platform (xdg-open, disks)
├─ Controls/       CounterText, SmoothBar, RingArc, SegmentBar, SettingRow, converters
├─ ViewModels/     the Windows view models, adapted
├─ Views/          MainWindow, Dashboard, Targets, Settings, About, overlays (.axaml)
├─ Themes/         Palette.axaml (the Windows palette per theme), Styles.axaml
├─ Resources/      Strings/*.json (Linux wording over the shared translations)
└─ packaging/      .desktop entry for the AppImage
tests/JunkCleanup.Linux.Tests   xunit: XDG paths, path guard, catalog, Trash, scan/clean (runs on Linux and macOS)
```

How the two map onto each other:

| Windows | macOS | Linux |
|---|---|---|
| WPF styles and storyboards | `CCControls` / `CCMotion` on Core Animation, same easing and timings | Avalonia styles, transitions and keyframe animations |
| Mica backdrop | `NSVisualEffectView` vibrancy | the desktop's own window frame |
| Segoe Fluent Icons | SF Symbols | Material Design icons |
| Recycle Bin (`SHFileOperation`) | Trash (`NSFileManager trashItemAtURL`) | freedesktop Trash (rename + `.trashinfo`) |
| Run as administrator | Full Disk Access | root-owned locations are insights with a command |
| `TargetCatalog.cs` | `CCCatalog` in `CCCore.m` | `LinuxApp/Core/TargetCatalog.cs` (shared ids, so translations are shared) |

## Contributing

Issues and pull requests are welcome. The most useful contributions:

- **New targets** — add an entry to `TargetCatalog.cs` (or `CCCatalog` in `MacApp/Sources/CCCore.m`) plus `target.<id>.name` / `.desc` in `Strings/en.json` (other languages fall back to English until translated).
- **Translations** — copy `en.json`, translate, keep keys and `{0}` placeholders; the localization tests will tell you if anything is missing.
- **Bug reports** with the target id and the path involved.

## License

[MIT](LICENSE) © 2026 Kreal-exe
