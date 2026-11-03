# Builds JunkCleanup (C# / WPF) and puts it on the Desktop.
#
#   .\build.ps1          build, put JunkCleanup.exe on the Desktop and open it
#   .\build.ps1 -Test    run the xunit suite first
#   .\build.ps1 -Exe     also write dist\JunkCleanup-Windows-v<version>.exe for a release
#
# $env:INSTALL_DIR = "D:\Apps\JunkCleanup"; .\build.ps1   puts it somewhere else.
# Needs the .NET 10 SDK (https://dot.net).
param([switch]$Test, [switch]$Exe)
$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot
$Project = Join-Path $Root "src\JunkCleanup\JunkCleanup.csproj"
$Version = ([xml](Get-Content $Project)).Project.PropertyGroup.Version
$Dest = if ($env:INSTALL_DIR) { $env:INSTALL_DIR } else { [Environment]::GetFolderPath("Desktop") }
$Installed = Join-Path $Dest "JunkCleanup.exe"
$env:DOTNET_CLI_TELEMETRY_OPTOUT = "1"
$env:DOTNET_NOLOGO = "1"

if (-not ((& dotnet --list-sdks 2>$null) -match "^10\.")) {
    Write-Error "The .NET 10 SDK is needed: https://dot.net"
}

# Build outside the project, so no bin\ or obj\ folders are left in it.
$Out = Join-Path ([IO.Path]::GetTempPath()) ("junkcleanup-" + [guid]::NewGuid())
$App = Join-Path $Out "JunkCleanup"
try {
    if ($Test) {
        Write-Host "Running the tests..."
        & dotnet test (Join-Path $Root "JunkCleanup.slnx") -c Release --nologo -v quiet --artifacts-path (Join-Path $Out "artifacts")
        if ($LASTEXITCODE) { exit $LASTEXITCODE }
    }

    Write-Host "Building JunkCleanup $Version..."
    # One self-contained exe: no .NET needed on the user's PC.
    & dotnet publish $Project -c Release -r win-x64 --self-contained true -o $App --artifacts-path (Join-Path $Out "artifacts") `
        --nologo -v quiet -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true `
        -p:EnableCompressionInSingleFile=true -p:DebugType=none
    if ($LASTEXITCODE) { exit $LASTEXITCODE }

    if ($Exe) {
        $Dist = Join-Path $Root "dist"
        New-Item -ItemType Directory -Force $Dist | Out-Null
        $Release = Join-Path $Dist "JunkCleanup-Windows-v$Version.exe"
        Copy-Item (Join-Path $App "JunkCleanup.exe") $Release -Force
        Write-Host "Release exe: $Release"
    }

    # Close a running copy first; if it stays open (a clean in progress), leave the installed version alone.
    $running = @(Get-Process JunkCleanup -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $Installed })
    if ($running) {
        Write-Host "Closing the running JunkCleanup..."
        $running | ForEach-Object { $_.CloseMainWindow() | Out-Null }
        $running | ForEach-Object { $_.WaitForExit(10000) | Out-Null }
        if (Get-Process JunkCleanup -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $Installed }) {
            Write-Error "JunkCleanup is still running. Close it and run the build again."
        }
    }

    # Only the app's own files are replaced: the folder (the Desktop) keeps everything else.
    New-Item -ItemType Directory -Force $Dest | Out-Null
    Copy-Item -Recurse -Force (Join-Path $App "*") $Dest
    Write-Host "Installed: $Installed"
    if (-not $env:CI) { Start-Process $Installed }   # opened right away, except on a CI runner
}
finally {
    Remove-Item -Recurse -Force $Out -ErrorAction SilentlyContinue
}
