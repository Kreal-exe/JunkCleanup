**Windows.** Download `JunkCleanup-Windows-v<version>.exe` and run it — one file, nothing to install, no .NET needed.
Windows 10 1903 or later. The app is not signed yet: if SmartScreen stops it, choose **More info → Run anyway**.

**macOS.** Open `JunkCleanup-macOS-v<version>.dmg` and drag `JunkCleanup.app` onto *Applications*. The build is not
notarized yet, so remove the quarantine flag before the first launch:

```bash
xattr -dr com.apple.quarantine /Applications/JunkCleanup.app
```

Or: *System Settings → Privacy & Security* → **Open Anyway**. macOS 12 or later, Apple Silicon or Intel.

**Linux.** `JunkCleanup-Linux-v<version>.AppImage`: make it executable (`chmod +x`) and run it. Self-contained, no .NET
needed; x86-64, any desktop (GNOME, KDE, Xfce…). `JunkCleanup --scan` lists what would be cleaned without a window.

---

**Windows.** Скачайте `JunkCleanup-Windows-v<version>.exe` и запустите — один файл, устанавливать ничего не нужно, .NET
не нужен. Windows 10 1903 или новее. Приложение пока не подписано: если SmartScreen его остановит, нажмите
**«Подробнее» → «Выполнить в любом случае»**.

**macOS.** Откройте `JunkCleanup-macOS-v<version>.dmg` и перетащите `JunkCleanup.app` в «Программы». Сборка пока не
нотаризована, поэтому перед первым запуском снимите карантинную пометку:

```bash
xattr -dr com.apple.quarantine /Applications/JunkCleanup.app
```

Или: «Системные настройки» → «Конфиденциальность и безопасность» → **«Всё равно открыть»**. macOS 12 или новее,
Apple Silicon или Intel.

**Linux.** `JunkCleanup-Linux-v<version>.AppImage`: сделайте файл исполняемым (`chmod +x`) и запустите. Всё своё внутри,
.NET не нужен; x86-64, любое окружение (GNOME, KDE, Xfce…). `JunkCleanup --scan` без окна покажет, что будет очищено.
