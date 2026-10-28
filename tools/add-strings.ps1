# One-off helper: inserts the Insights / toast / theme-toggle strings into every non-English language file
# (before "common.cancel") and refreshes the VS target description. Idempotent.
$dir = "C:\JunkCleanup\src\JunkCleanup\Localization\Strings"
$utf8 = New-Object System.Text.UTF8Encoding $false

$t = @{
  ru = @{
    "insight.title" = 'Ещё на этом диске'
    "insight.subtitle" = 'Место, которое JunkCleanup не трогает, но о котором стоит знать.'
    "insight.copyCommand" = 'Скопировать команду'
    "insight.open" = 'Открыть'
    "insight.copied" = 'Скопировано: «{0}». Выполните в терминале от администратора.'
    "insight.hiberfil.title" = 'Файл гибернации'
    "insight.hiberfil.detail" = '{0} занимает hiberfil.sys. Если гибернация не нужна, «powercfg /h off» освободит это место (отключится и быстрый запуск).'
    "insight.pagefile.title" = 'Файл подкачки'
    "insight.pagefile.detail" = '{0} занимает pagefile.sys. Управляется Windows; менять размер стоит только в дополнительных параметрах системы.'
    "insight.windowsold.title" = 'Предыдущая установка Windows'
    "insight.windowsold.detail" = '{0} в Windows.old. Удалите через Параметры → Память → Временные файлы, если откат точно не понадобится.'
    "insight.recyclebin.title" = 'Корзина'
    "insight.recyclebin.detail" = '{0} лежит в корзине. Включите цель «Корзина», чтобы очистить её.'
    "toast.freed" = 'Освобождено {0}'
    "titlebar.theme" = 'Переключить тему'
    "target.dev.visualstudio.desc" = 'Кэш компонентов и расширений.'
  }
  uk = @{
    "insight.title" = 'Ще на цьому диску'
    "insight.subtitle" = 'Місце, яке JunkCleanup не чіпає, але про яке варто знати.'
    "insight.copyCommand" = 'Скопіювати команду'
    "insight.open" = 'Відкрити'
    "insight.copied" = 'Скопійовано: «{0}». Виконайте в терміналі від імені адміністратора.'
    "insight.hiberfil.title" = 'Файл глибокого сну'
    "insight.hiberfil.detail" = '{0} займає hiberfil.sys. Якщо глибокий сон не потрібен, «powercfg /h off» звільнить це місце (вимкнеться і швидкий запуск).'
    "insight.pagefile.title" = 'Файл підкачки'
    "insight.pagefile.detail" = '{0} займає pagefile.sys. Керується Windows; змінюйте розмір лише в додаткових параметрах системи.'
    "insight.windowsold.title" = 'Попередня інсталяція Windows'
    "insight.windowsold.detail" = '{0} у Windows.old. Видаліть через Налаштування → Сховище → Тимчасові файли, якщо відкат точно не знадобиться.'
    "insight.recyclebin.title" = 'Кошик'
    "insight.recyclebin.detail" = '{0} лежить у кошику. Увімкніть ціль «Кошик», щоб очистити його.'
    "toast.freed" = 'Звільнено {0}'
    "titlebar.theme" = 'Перемкнути тему'
    "target.dev.visualstudio.desc" = 'Кеш компонентів і розширень.'
  }
  de = @{
    "insight.title" = 'Außerdem auf diesem Laufwerk'
    "insight.subtitle" = 'Speicher, den JunkCleanup nicht anfasst, den du aber kennen solltest.'
    "insight.copyCommand" = 'Befehl kopieren'
    "insight.open" = 'Öffnen'
    "insight.copied" = '„{0}“ kopiert. Führe den Befehl in einem Terminal mit Administratorrechten aus.'
    "insight.hiberfil.title" = 'Ruhezustandsdatei'
    "insight.hiberfil.detail" = '{0} belegt hiberfil.sys. Wenn du den Ruhezustand nie nutzt, gibt „powercfg /h off“ den Platz frei (deaktiviert auch den Schnellstart).'
    "insight.pagefile.title" = 'Auslagerungsdatei'
    "insight.pagefile.detail" = '{0} belegt pagefile.sys. Wird von Windows verwaltet; Größe nur in den erweiterten Systemeinstellungen ändern.'
    "insight.windowsold.title" = 'Vorherige Windows-Installation'
    "insight.windowsold.detail" = '{0} in Windows.old. Entferne sie unter Einstellungen → Speicher → Temporäre Dateien, sobald du sicher nicht zurückwechseln willst.'
    "insight.recyclebin.title" = 'Papierkorb'
    "insight.recyclebin.detail" = '{0} liegen im Papierkorb. Aktiviere das Ziel „Papierkorb“, um ihn zu leeren.'
    "toast.freed" = '{0} freigegeben'
    "titlebar.theme" = 'Design wechseln'
    "target.dev.visualstudio.desc" = 'Komponentenmodell- und Erweiterungscaches.'
  }
  fr = @{
    "insight.title" = 'Également sur ce disque'
    "insight.subtitle" = 'De l''espace que JunkCleanup ne touche pas, mais que vous devriez connaître.'
    "insight.copyCommand" = 'Copier la commande'
    "insight.open" = 'Ouvrir'
    "insight.copied" = '« {0} » copié. Exécutez-le dans un terminal administrateur.'
    "insight.hiberfil.title" = 'Fichier de veille prolongée'
    "insight.hiberfil.detail" = '{0} réservés par hiberfil.sys. Si vous n''utilisez jamais la veille prolongée, « powercfg /h off » libère cet espace (désactive aussi le démarrage rapide).'
    "insight.pagefile.title" = 'Fichier d''échange'
    "insight.pagefile.detail" = '{0} utilisés par pagefile.sys. Géré par Windows ; ne le redimensionnez que depuis les paramètres système avancés.'
    "insight.windowsold.title" = 'Installation Windows précédente'
    "insight.windowsold.detail" = '{0} dans Windows.old. Supprimez-le via Paramètres → Stockage → Fichiers temporaires une fois sûr de ne pas revenir en arrière.'
    "insight.recyclebin.title" = 'Corbeille'
    "insight.recyclebin.detail" = '{0} attendent dans la Corbeille. Activez la cible « Corbeille » pour la vider.'
    "toast.freed" = '{0} libérés'
    "titlebar.theme" = 'Changer de thème'
    "target.dev.visualstudio.desc" = 'Caches du modèle de composants et des extensions.'
  }
  es = @{
    "insight.title" = 'También en este disco'
    "insight.subtitle" = 'Espacio que JunkCleanup no toca, pero que conviene conocer.'
    "insight.copyCommand" = 'Copiar comando'
    "insight.open" = 'Abrir'
    "insight.copied" = 'Se copió «{0}». Ejecútalo en un terminal con permisos de administrador.'
    "insight.hiberfil.title" = 'Archivo de hibernación'
    "insight.hiberfil.detail" = '{0} reservados por hiberfil.sys. Si nunca hibernas, «powercfg /h off» libera ese espacio (también desactiva el inicio rápido).'
    "insight.pagefile.title" = 'Archivo de paginación'
    "insight.pagefile.detail" = '{0} usados por pagefile.sys. Lo administra Windows; cámbialo solo desde la configuración avanzada del sistema.'
    "insight.windowsold.title" = 'Instalación anterior de Windows'
    "insight.windowsold.detail" = '{0} en Windows.old. Elimínalo desde Configuración → Almacenamiento → Archivos temporales cuando estés seguro de no volver atrás.'
    "insight.recyclebin.title" = 'Papelera de reciclaje'
    "insight.recyclebin.detail" = '{0} esperan en la Papelera de reciclaje. Activa el objetivo «Papelera de reciclaje» para vaciarla.'
    "toast.freed" = '{0} liberados'
    "titlebar.theme" = 'Cambiar tema'
    "target.dev.visualstudio.desc" = 'Cachés del modelo de componentes y de extensiones.'
  }
  pl = @{
    "insight.title" = 'Również na tym dysku'
    "insight.subtitle" = 'Miejsce, którego JunkCleanup nie rusza, ale o którym warto wiedzieć.'
    "insight.copyCommand" = 'Kopiuj polecenie'
    "insight.open" = 'Otwórz'
    "insight.copied" = 'Skopiowano „{0}”. Uruchom je w terminalu z uprawnieniami administratora.'
    "insight.hiberfil.title" = 'Plik hibernacji'
    "insight.hiberfil.detail" = '{0} zajmuje hiberfil.sys. Jeśli nie używasz hibernacji, „powercfg /h off” zwolni to miejsce (wyłączy też szybkie uruchamianie).'
    "insight.pagefile.title" = 'Plik stronicowania'
    "insight.pagefile.detail" = '{0} zajmuje pagefile.sys. Zarządzany przez Windows; zmieniaj rozmiar tylko w zaawansowanych ustawieniach systemu.'
    "insight.windowsold.title" = 'Poprzednia instalacja Windows'
    "insight.windowsold.detail" = '{0} w Windows.old. Usuń przez Ustawienia → Pamięć → Pliki tymczasowe, gdy masz pewność, że nie wrócisz do poprzedniej wersji.'
    "insight.recyclebin.title" = 'Kosz'
    "insight.recyclebin.detail" = '{0} czeka w Koszu. Włącz cel „Kosz”, aby go opróżnić.'
    "toast.freed" = 'Zwolniono {0}'
    "titlebar.theme" = 'Przełącz motyw'
    "target.dev.visualstudio.desc" = 'Pamięć podręczna modelu komponentów i rozszerzeń.'
  }
  "zh-Hans" = @{
    "insight.title" = '此磁盘上的其他占用'
    "insight.subtitle" = 'JunkCleanup 不会触碰这些空间，但你可能想了解它们。'
    "insight.copyCommand" = '复制命令'
    "insight.open" = '打开'
    "insight.copied" = '已复制“{0}”。请在管理员终端中运行。'
    "insight.hiberfil.title" = '休眠文件'
    "insight.hiberfil.detail" = 'hiberfil.sys 占用 {0}。如果从不使用休眠，运行“powercfg /h off”即可释放（同时会关闭快速启动）。'
    "insight.pagefile.title" = '页面文件'
    "insight.pagefile.detail" = 'pagefile.sys 占用 {0}。由 Windows 管理，仅在高级系统设置中调整大小。'
    "insight.windowsold.title" = '旧版 Windows 安装'
    "insight.windowsold.detail" = 'Windows.old 占用 {0}。确定不再回退后，可在“设置 → 存储 → 临时文件”中删除。'
    "insight.recyclebin.title" = '回收站'
    "insight.recyclebin.detail" = '回收站中有 {0}。启用“回收站”清理项即可清空。'
    "toast.freed" = '已释放 {0}'
    "titlebar.theme" = '切换主题'
    "target.dev.visualstudio.desc" = '组件模型与扩展缓存。'
  }
  ja = @{
    "insight.title" = 'このディスクのその他の項目'
    "insight.subtitle" = 'JunkCleanup は変更しませんが、知っておくと役立つ領域です。'
    "insight.copyCommand" = 'コマンドをコピー'
    "insight.open" = '開く'
    "insight.copied" = '「{0}」をコピーしました。管理者権限のターミナルで実行してください。'
    "insight.hiberfil.title" = '休止状態ファイル'
    "insight.hiberfil.detail" = 'hiberfil.sys が {0} を占有しています。休止状態を使わないなら「powercfg /h off」で解放できます（高速スタートアップも無効になります）。'
    "insight.pagefile.title" = 'ページ ファイル'
    "insight.pagefile.detail" = 'pagefile.sys が {0} を使用しています。Windows が管理するため、サイズ変更はシステムの詳細設定からのみ行ってください。'
    "insight.windowsold.title" = '以前の Windows インストール'
    "insight.windowsold.detail" = 'Windows.old に {0} があります。元に戻さないと確信できたら、設定 → ストレージ → 一時ファイルから削除してください。'
    "insight.recyclebin.title" = 'ごみ箱'
    "insight.recyclebin.detail" = 'ごみ箱に {0} があります。「ごみ箱」の対象を有効にすると空にできます。'
    "toast.freed" = '{0} を解放しました'
    "titlebar.theme" = 'テーマを切り替え'
    "target.dev.visualstudio.desc" = 'コンポーネント モデルと拡張機能のキャッシュ。'
  }
}

$order = "insight.title","insight.subtitle","insight.copyCommand","insight.open","insight.copied",
         "insight.hiberfil.title","insight.hiberfil.detail","insight.pagefile.title","insight.pagefile.detail",
         "insight.windowsold.title","insight.windowsold.detail","insight.recyclebin.title","insight.recyclebin.detail",
         "toast.freed","titlebar.theme"

function Esc([string]$s) { return $s.Replace('\', '\\').Replace('"', '\"') }

foreach ($code in $t.Keys) {
    $path = Join-Path $dir "$code.json"
    $text = [IO.File]::ReadAllText($path, $utf8)
    $strings = $t[$code]

    if ($text -notmatch '"insight\.title"') {
        $block = ($order | ForEach-Object { '  "' + $_ + '": "' + (Esc $strings[$_]) + '",' }) -join "`n"
        $text = $text -replace '(\r?\n)(\s*"common\.cancel")', ('$1' + $block + '$1$1$2')
    }

    $vs = Esc $strings["target.dev.visualstudio.desc"]
    $text = [regex]::Replace($text, '("target\.dev\.visualstudio\.desc":\s*)"[^"]*"', ('$1"' + $vs + '"'))

    [IO.File]::WriteAllText($path, $text, $utf8)
    $keys = (ConvertFrom-Json $text).PSObject.Properties.Name
    "{0,-8} {1} keys" -f $code, $keys.Count
}
$enKeys = (ConvertFrom-Json ([IO.File]::ReadAllText((Join-Path $dir "en.json"), $utf8))).PSObject.Properties.Name
"en       $($enKeys.Count) keys"
