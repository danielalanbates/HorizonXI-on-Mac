<# : Batch portion
@echo off
setlocal

REM Run PowerShell with this same file
PowerShell.exe -ExecutionPolicy Bypass -NoProfile -Command "& {Invoke-Expression (Get-Content '%~f0' -Raw)}"

REM Always pause to see results
echo.
echo Press any key to close...
pause >nul

exit /b %ERRORLEVEL%
: End batch / Begin PowerShell #>

#Requires -Version 5.1

<#
.SYNOPSIS
    FFXIFriendList Installer - Downloads and installs the latest version from GitHub
.DESCRIPTION
    This script downloads the latest FFXIFriendList release from GitHub and installs it
    to your Ashita addons folder. It preserves your existing configuration and updates
    your scripts/default.txt file to auto-load the addon.
.PARAMETER Force
    Force reinstallation even if the latest version is already installed
.EXAMPLE
    .\Install-FFXIFriendList.bat
    Installs or updates FFXIFriendList to the latest version
#>

$ErrorActionPreference = "Stop"
$ProgressPreference = "Continue"

# Constants
$GITHUB_REPO = "Tanyrus/FFXIFriendList"
$ADDON_NAME = "FFXIFriendList"
$ADDON_LOAD_COMMAND = "/addon load ffxifriendlist"

#region Helper Functions

function Write-ColorOutput {
    param(
        [string]$Message,
        [ConsoleColor]$Color = [ConsoleColor]::White
    )
    $previousColor = $Host.UI.RawUI.ForegroundColor
    $Host.UI.RawUI.ForegroundColor = $Color
    Write-Host $Message
    $Host.UI.RawUI.ForegroundColor = $previousColor
}

function Test-AshitaEnvironment {
    param([string]$Path)
    
    $requiredFolders = @("addons", "scripts", "config")
    foreach ($folder in $requiredFolders) {
        if (-not (Test-Path (Join-Path $Path $folder))) {
            return $false
        }
    }
    return $true
}

function Get-AshitaRootPath {
    $currentPath = Get-Location
    
    if (Test-AshitaEnvironment -Path $currentPath) {
        return $currentPath.Path
    }
    
    Write-ColorOutput "`nAshita root directory not detected." -Color Yellow
    Write-ColorOutput "Required folders: addons, scripts, config" -Color Yellow
    Write-ColorOutput "`nPlease select your Ashita installation folder..." -Color Cyan
    Write-ColorOutput "This is the folder that CONTAINS the addons, scripts, and config folders. For Horizon, its called 'Game'." -Color Cyan
    Write-Host ""
    
    Add-Type -AssemblyName System.Windows.Forms
    $folderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
    $folderBrowser.Description = "Select your Ashita root directory`n`nThis folder should CONTAIN these subfolders:`n- addons`n- scripts`n- config"
    $folderBrowser.RootFolder = [System.Environment+SpecialFolder]::MyComputer
    $folderBrowser.ShowNewFolderButton = $false
    
    if ($folderBrowser.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $selectedPath = $folderBrowser.SelectedPath
        if (Test-AshitaEnvironment -Path $selectedPath) {
            return $selectedPath
        } else {
            Write-ColorOutput "`nSelected folder is not a valid Ashita root directory." -Color Red
            Write-ColorOutput "Missing required folders: addons, scripts, config" -Color Red
            return $null
        }
    }
    
    return $null
}

function Test-InternetConnection {
    try {
        $null = Invoke-WebRequest -Uri "https://api.github.com" -UseBasicParsing -TimeoutSec 5 -Method Head
        return $true
    } catch {
        return $false
    }
}

function Get-LatestRelease {
    param([string]$Repository)
    
    $apiUrl = "https://api.github.com/repos/$Repository/releases/latest"
    $headers = @{
        "Accept" = "application/vnd.github+json"
        "User-Agent" = "FFXIFriendList-Installer"
    }
    
    try {
        $release = Invoke-RestMethod -Uri $apiUrl -Headers $headers -ErrorAction Stop
        
        $asset = $release.assets | Where-Object { $_.name -match '^FFXIFriendList.*\.zip$' } | Select-Object -First 1
        
        if (-not $asset) {
            throw "No ZIP asset found in latest release"
        }
        
        return @{
            Version = $release.tag_name
            DownloadUrl = $asset.browser_download_url
            AssetName = $asset.name
            Size = $asset.size
        }
    } catch {
        if ($_.Exception.Response.StatusCode -eq 404) {
            throw "Repository not found or no releases available"
        } elseif ($_.Exception.Response.StatusCode -eq 403) {
            throw "GitHub API rate limit exceeded. Please try again later."
        } else {
            throw "Failed to fetch release information: $_"
        }
    }
}

function Get-InstalledVersion {
    param([string]$AddonPath)
    
    $versionFile = Join-Path $AddonPath ".version"
    if (Test-Path $versionFile) {
        return (Get-Content $versionFile -Raw).Trim()
    }
    return $null
}

function Test-FileLocked {
    param([string]$FilePath)
    
    if (-not (Test-Path $FilePath)) {
        return $false
    }
    
    try {
        $fileStream = [System.IO.File]::Open($FilePath, 'Open', 'ReadWrite', 'None')
        $fileStream.Close()
        return $false
    } catch {
        return $true
    }
}

function Wait-ForFileUnlock {
    param([string]$FilePath)
    
    while (Test-FileLocked -FilePath $FilePath) {
        Write-ColorOutput "`nAddon files are currently locked (Ashita is running)." -Color Yellow
        Write-ColorOutput "Please close Ashita and press Enter to continue..." -Color Cyan
        Read-Host
    }
}

function Update-DefaultScript {
    param(
        [string]$ScriptsPath,
        [string]$Command
    )
    
    $defaultTxtPath = Join-Path $ScriptsPath "default.txt"
    
    if (-not (Test-Path $defaultTxtPath)) {
        Write-ColorOutput "  Warning: scripts\default.txt not found" -Color Yellow
        Write-ColorOutput "  You'll need to manually add: $Command" -Color Yellow
        return $false
    }
    
    $content = Get-Content $defaultTxtPath -Raw
    
    # Check if command already exists (case-insensitive, allowing variations in spacing)
    if ($content -match "(?mi)^\s*/addon\s+load\s+ffxifriendlist\s*$") {
        return $true  # Already configured
    }
    
    # Strategy: Insert after the last /addon load command in the file
    # This works for both vanilla and Horizon XI formats
    $lines = Get-Content $defaultTxtPath
    $lastAddonLoadIndex = -1
    
    # Find the last /addon load command
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        if ($lines[$i] -match '^\s*/addon\s+load\s+') {
            $lastAddonLoadIndex = $i
            break
        }
    }
    
    if ($lastAddonLoadIndex -ne -1) {
        # Insert right after the last /addon load command
        $insertIndex = $lastAddonLoadIndex + 1
        $newLines = @($lines[0..$lastAddonLoadIndex]) + $Command + @($lines[$insertIndex..($lines.Count - 1)])
        $newLines | Set-Content -Path $defaultTxtPath -Encoding UTF8
        return $true
    }
    
    # Fallback: Try to find custom user section (Horizon XI style)
    $insertIndex = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '(?i)#.*custom.*user.*(plugins|addons)') {
            # Found section header, skip comment lines to find insertion point
            for ($j = $i + 1; $j -lt $lines.Count; $j++) {
                if ($lines[$j] -match '^#' -or $lines[$j] -match '^\s*$') {
                    continue  # Skip comments and blank lines
                }
                $insertIndex = $j
                break
            }
            break
        }
    }
    
    if ($insertIndex -eq -1) {
        # Last resort: append to end
        Add-Content -Path $defaultTxtPath -Value "`n$Command"
    } else {
        # Insert at found position
        $newLines = @($lines[0..($insertIndex - 1)]) + $Command + @($lines[$insertIndex..($lines.Count - 1)])
        $newLines | Set-Content -Path $defaultTxtPath -Encoding UTF8
    }
    
    return $true
}

#endregion

#region Main Execution

try {
    Write-ColorOutput "========================================" -Color Cyan
    Write-ColorOutput "  FFXIFriendList Installer" -Color Cyan
    Write-ColorOutput "========================================" -Color Cyan
    Write-Host ""
    
    # Step 1: Validate environment
    Write-Progress -Activity "Installing FFXIFriendList" -Status "Validating environment..." -PercentComplete 0
    
    $ashitaRoot = Get-AshitaRootPath
    if (-not $ashitaRoot) {
        Write-ColorOutput "`nInstallation cancelled." -Color Red
        exit 1
    }
    
    Write-ColorOutput "Ashita root: $ashitaRoot" -Color Green
    
    # Step 2: Check internet connection
    Write-Progress -Activity "Installing FFXIFriendList" -Status "Checking internet connection..." -PercentComplete 5
    
    if (-not (Test-InternetConnection)) {
        throw "No internet connection or GitHub is unreachable."
    }
    
    # Step 3: Get latest release info
    Write-Progress -Activity "Installing FFXIFriendList" -Status "Fetching latest release..." -PercentComplete 10
    
    $release = Get-LatestRelease -Repository $GITHUB_REPO
    $latestVersion = $release.Version
    
    # Step 4: Check installed version
    $addonPath = Join-Path $ashitaRoot "addons\$ADDON_NAME"
    $installedVersion = Get-InstalledVersion -AddonPath $addonPath
    
    Write-Host ""
    Write-ColorOutput "Current version: $(if ($installedVersion) { $installedVersion } else { 'Not installed' })" -Color $(if ($installedVersion) { [ConsoleColor]::Gray } else { [ConsoleColor]::Yellow })
    Write-ColorOutput "Latest version:  $latestVersion" -Color Cyan
    Write-Host ""
    
    # Check if update needed
    if ($installedVersion -eq $latestVersion) {
        Write-ColorOutput "Already up-to-date!" -Color Green
        exit 0
    }
    
    # Step 5: Download release
    $zipPath = Join-Path $env:TEMP "$($release.AssetName)"
    $extractPath = Join-Path $env:TEMP "FFXIFriendList-extract"
    
    Write-Progress -Activity "Installing FFXIFriendList" -Status "Downloading $latestVersion..." -PercentComplete 15
    
    try {
        # Download with progress
        $webClient = New-Object System.Net.WebClient
        $webClient.Headers.Add("User-Agent", "FFXIFriendList-Installer")
        
        Register-ObjectEvent -InputObject $webClient -EventName DownloadProgressChanged -SourceIdentifier WebClient.DownloadProgressChanged -Action {
            $percent = 15 + ($EventArgs.ProgressPercentage * 0.35)  # 15% to 50%
            Write-Progress -Activity "Installing FFXIFriendList" -Status "Downloading..." -PercentComplete $percent
        } | Out-Null
        
        $downloadTask = $webClient.DownloadFileTaskAsync($release.DownloadUrl, $zipPath)
        $downloadTask.Wait()
        
        Unregister-Event -SourceIdentifier WebClient.DownloadProgressChanged -ErrorAction SilentlyContinue
        $webClient.Dispose()
        
    } catch {
        throw "Failed to download release: $_"
    }
    
    # Step 6: Extract
    Write-Progress -Activity "Installing FFXIFriendList" -Status "Extracting files..." -PercentComplete 50
    
    if (Test-Path $extractPath) {
        Remove-Item $extractPath -Recurse -Force
    }
    
    Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force
    
    # Find the addon folder in extracted files
    $extractedAddonPath = Get-ChildItem -Path $extractPath -Recurse -Filter "FFXIFriendList.lua" | Select-Object -First 1
    
    if (-not $extractedAddonPath) {
        throw "Downloaded archive is invalid - FFXIFriendList.lua not found"
    }
    
    $sourceAddonPath = $extractedAddonPath.Directory.FullName
    
    # Verify critical files
    $criticalFiles = @("FFXIFriendList.lua", "app\App.lua", "core\models.lua")
    foreach ($file in $criticalFiles) {
        if (-not (Test-Path (Join-Path $sourceAddonPath $file))) {
            throw "Downloaded archive is incomplete - missing $file"
        }
    }
    
    # Step 7: Check for file locks and remove old installation
    Write-Progress -Activity "Installing FFXIFriendList" -Status "Preparing installation..." -PercentComplete 70
    
    if (Test-Path $addonPath) {
        $testFile = Join-Path $addonPath "FFXIFriendList.lua"
        Wait-ForFileUnlock -FilePath $testFile
        
        Write-Progress -Activity "Installing FFXIFriendList" -Status "Removing old version..." -PercentComplete 75
        Remove-Item $addonPath -Recurse -Force
    }
    
    # Step 8: Install new version
    Write-Progress -Activity "Installing FFXIFriendList" -Status "Installing files..." -PercentComplete 80
    
    $addonsFolder = Join-Path $ashitaRoot "addons"
    if (-not (Test-Path $addonsFolder)) {
        New-Item -Path $addonsFolder -ItemType Directory | Out-Null
    }
    
    Copy-Item -Path $sourceAddonPath -Destination $addonPath -Recurse -Force
    
    # Write version file
    $versionFile = Join-Path $addonPath ".version"
    Set-Content -Path $versionFile -Value $latestVersion -NoNewline
    
    # Step 9: Update scripts/default.txt
    Write-Progress -Activity "Installing FFXIFriendList" -Status "Updating configuration..." -PercentComplete 90
    
    $scriptsPath = Join-Path $ashitaRoot "scripts"
    $wasAlreadyConfigured = Update-DefaultScript -ScriptsPath $scriptsPath -Command $ADDON_LOAD_COMMAND
    
    # Step 10: Cleanup
    Write-Progress -Activity "Installing FFXIFriendList" -Status "Cleaning up..." -PercentComplete 95
    
    Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
    Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue
    
    Write-Progress -Activity "Installing FFXIFriendList" -Status "Complete!" -PercentComplete 100 -Completed
    
    # Step 11: Display summary
    Write-Host ""
    Write-ColorOutput "========================================" -Color Green
    Write-ColorOutput "  Installation Complete!" -Color Green
    Write-ColorOutput "========================================" -Color Green
    Write-Host ""
    
    if ($installedVersion) {
        Write-ColorOutput "Updated: $installedVersion → $latestVersion" -Color Cyan
    } else {
        Write-ColorOutput "Installed: $latestVersion" -Color Cyan
    }
    
    Write-Host ""
    Write-ColorOutput "Installation path:" -Color Gray
    Write-ColorOutput "  $addonPath" -Color White
    Write-Host ""
    
    $configPath = Join-Path $ashitaRoot "config\addons\$ADDON_NAME"
    if (Test-Path $configPath) {
        Write-ColorOutput "Configuration preserved:" -Color Gray
        Write-ColorOutput "  $configPath" -Color White
        Write-Host ""
    }
    
    Write-ColorOutput "Auto-load configuration:" -Color Gray
    if ($wasAlreadyConfigured) {
        Write-ColorOutput "  Already configured in scripts\default.txt" -Color White
    } else {
        Write-ColorOutput "  Added to scripts\default.txt" -Color White
    }
    Write-Host ""
    
    Write-ColorOutput "Start Ashita to use FFXIFriendList!" -Color Green
    Write-Host ""
    
} catch {
    Write-Progress -Activity "Installing FFXIFriendList" -Completed
    Write-Host ""
    Write-ColorOutput "========================================" -Color Red
    Write-ColorOutput "  Installation Failed" -Color Red
    Write-ColorOutput "========================================" -Color Red
    Write-Host ""
    Write-ColorOutput "Error: $_" -Color Red
    Write-Host ""
    exit 1
}

#endregion
