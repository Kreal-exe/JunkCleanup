**Windows.** `JunkCleanup-win-x64.zip` needs the [.NET 10 Desktop Runtime](https://dotnet.microsoft.com/download/dotnet/10.0);
`JunkCleanup-win-x64-selfcontained.zip` runs anywhere. Unzip and run `JunkCleanup.exe` — nothing to install.
Windows 10 1903 or later. The app is not signed yet: if SmartScreen stops it, choose **More info → Run anyway**.

**macOS.** Download `JunkCleanup-macOS.zip`, unzip it and drag `JunkCleanup.app` to *Applications*. The build is not
notarized yet, so remove the quarantine flag before the first launch:

```bash
xattr -dr com.apple.quarantine /Applications/JunkCleanup.app
```

Or: *System Settings → Privacy & Security* → **Open Anyway**. macOS 12 or later, Apple Silicon or Intel.

**Linux.** `JunkCleanup-x86_64.AppImage`: make it executable (`chmod +x`) and run it. Or unpack
`JunkCleanup-linux-x64.tar.gz` and run `./JunkCleanup/install.sh` to add it to the app menu. Self-contained, no .NET
needed; x86-64, any desktop (GNOME, KDE, Xfce…). `JunkCleanup --scan` lists what would be cleaned without a window.

---

**Windows.** `JunkCleanup-win-x64.zip` требует [.NET 10 Desktop Runtime](https://dotnet.microsoft.com/download/dotnet/10.0);
`JunkCleanup-win-x64-selfcontained.zip` работает везде. Распакуйте и запустите `JunkCleanup.exe` — устанавливать ничего
не нужно. Windows 10 1903 или новее. Приложение пока не подписано: если SmartScreen его остановит, нажмите
**«Подробнее» → «Выполнить в любом случае»**.

**macOS.** Скачайте `JunkCleanup-macOS.zip`, распакуйте и перетащите `JunkCleanup.app` в «Программы». Сборка пока не
нотаризована, поэтому перед первым запуском снимите карантинную пометку:

```bash
xattr -dr com.apple.quarantine /Applications/JunkCleanup.app
```

Или: «Системные настройки» → «Конфиденциальность и безопасность» → **«Всё равно открыть»**. macOS 12 или новее,
Apple Silicon или Intel.

**Linux.** `JunkCleanup-x86_64.AppImage`: сделайте файл исполняемым (`chmod +x`) и запустите. Или распакуйте
`JunkCleanup-linux-x64.tar.gz` и выполните `./JunkCleanup/install.sh`, чтобы приложение появилось в меню. Всё своё
внутри, .NET не нужен; x86-64, любое окружение (GNOME, KDE, Xfce…). `JunkCleanup --scan` без окна покажет, что будет
очищено.
