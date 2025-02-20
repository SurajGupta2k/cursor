# Set output encoding to UTF-8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# Clear the screen before displaying anything
Clear-Host

# Configuration file paths
$STORAGE_FILE = "$env:APPDATA\Cursor\User\globalStorage\storage.json"
$BACKUP_DIR = "$env:APPDATA\Cursor\User\globalStorage\backups"

# Add version checking function
function Get-CursorVersion {
    try {
        # Primary path check
        $packagePath = "$env:LOCALAPPDATA\Programs\cursor\resources\app\package.json"
        
        if (Test-Path $packagePath) {
            $packageJson = Get-Content $packagePath -Raw | ConvertFrom-Json
            if ($packageJson.version) {
                Write-Host "Current Cursor version: v$($packageJson.version)"
                return $packageJson.version
            }
        }

        # Alternative path check
        $altPath = "$env:LOCALAPPDATA\cursor\resources\app\package.json"
        if (Test-Path $altPath) {
            $packageJson = Get-Content $altPath -Raw | ConvertFrom-Json
            if ($packageJson.version) {
                Write-Host "Current Cursor version: v$($packageJson.version)"
                return $packageJson.version
            }
        }

        Write-Host "Warning: Could not detect Cursor version"
        Write-Host "Please ensure Cursor is properly installed"
        return $null
    }
    catch {
        Write-Host "Error getting Cursor version: $_"
        return $null
    }
}

# Modify the ASCII art section to use simpler characters
Write-Host @"
+------------------------------------------+
|              CURSOR TOOL                  |
|         Device ID Modifier v1.0           |
+------------------------------------------+
"@
Write-Host ""

# Check Cursor version
$cursorVersion = Get-CursorVersion
if ($cursorVersion) {
    if ([version]($cursorVersion -replace '[^\d\.].*$') -ge [version]"0.45.0") {
        Write-Host "Warning: Current version ($cursorVersion) may have limited compatibility"
        Write-Host "Recommended version: v0.44.11 or lower"
        Write-Host "You can download supported versions from:"
        Write-Host "Windows: https://download.todesktop.com/230313mzl4w4u92/Cursor%20Setup%200.44.11%20-%20Build%20250103fqxdt5u9z-x64.exe"
        Write-Host "Mac ARM64: https://dl.todesktop.com/230313mzl4w4u92/versions/0.44.11/mac/zip/arm64"
        Write-Host ""
        $continue = Read-Host "Do you want to continue anyway? (y/N)"
        if ($continue -ne "y") {
            exit 0
        }
    }
}

# Add color definitions
$RED = "`e[31m"
$GREEN = "`e[32m"
$YELLOW = "`e[33m"
$BLUE = "`e[34m"
$NC = "`e[0m"  # No Color

# Add process checking function
function Close-CursorProcess {
    param($processName)
    
    $process = Get-Process -Name $processName -ErrorAction SilentlyContinue
    if ($process) {
        Write-Host "$YELLOW[Warning]$NC Found running $processName process"
        
        # Get process details
        Write-Host "$BLUE[Info]$NC Process details:"
        Get-WmiObject Win32_Process -Filter "name='$processName'" | 
            Select-Object ProcessId, ExecutablePath, CommandLine | 
            Format-List
        
        Write-Host "$YELLOW[Warning]$NC Attempting to close $processName..."
        Stop-Process -Name $processName -Force
        
        # Wait and verify
        $maxRetries = 5
        $retryCount = 0
        while ($retryCount -lt $maxRetries) {
            $process = Get-Process -Name $processName -ErrorAction SilentlyContinue
            if (-not $process) { 
                Write-Host "$GREEN[Success]$NC $processName has been closed"
                break 
            }
            
            $retryCount++
            if ($retryCount -ge $maxRetries) {
                Write-Host "$RED[Error]$NC Failed to close $processName after $maxRetries attempts"
                Write-Host "Please close the process manually and try again"
                Read-Host "Press Enter to exit"
                exit 1
            }
            Write-Host "$YELLOW[Warning]$NC Waiting for process to close, attempt $retryCount/$maxRetries..."
            Start-Sleep -Seconds 1
        }
    }
}

# Check and close Cursor processes
Write-Host "$GREEN[Info]$NC Checking for running Cursor processes..."
Close-CursorProcess "Cursor"
Close-CursorProcess "cursor"

# Check administrator privileges
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Please run this script as Administrator"
    Write-Host "Right-click the script and select 'Run as Administrator'"
    Read-Host "Press Enter to exit"
    exit 1
}

# Create backup directory
if (-not (Test-Path $BACKUP_DIR)) {
    New-Item -ItemType Directory -Path $BACKUP_DIR | Out-Null
}

# Backup existing configuration
if (Test-Path $STORAGE_FILE) {
    Write-Host "Backing up configuration file..."
    $backupName = "storage.json.backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    Copy-Item $STORAGE_FILE "$BACKUP_DIR\$backupName"
}

# Generate new IDs
$MAC_MACHINE_ID = [System.Guid]::NewGuid().ToString()
$UUID = [System.Guid]::NewGuid().ToString()
$prefixBytes = [System.Text.Encoding]::UTF8.GetBytes("auth0|user_")
$prefixHex = -join ($prefixBytes | ForEach-Object { '{0:x2}' -f $_ })
$randomBytes = New-Object byte[] 32
$rng = [System.Security.Cryptography.RNGCryptoServiceProvider]::new()
$rng.GetBytes($randomBytes)
$randomHex = [System.BitConverter]::ToString($randomBytes) -replace '-',''
$MACHINE_ID = "$prefixHex$randomHex"
$SQM_ID = "{$([System.Guid]::NewGuid().ToString().ToUpper())}"

# Read and update configuration
try {
    if (-not (Test-Path $STORAGE_FILE)) {
        Write-Host "Configuration file not found: $STORAGE_FILE"
        Write-Host "Please install and run Cursor once before using this script"
        Read-Host "Press Enter to exit"
        exit 1
    }

    $originalContent = Get-Content $STORAGE_FILE -Raw -Encoding UTF8
    $config = $originalContent | ConvertFrom-Json

    # Show current values
    Write-Host "`nCurrent values:"
    Write-Host "machineId: $($config.'telemetry.machineId')"
    Write-Host "macMachineId: $($config.'telemetry.macMachineId')"
    Write-Host "devDeviceId: $($config.'telemetry.devDeviceId')"
    Write-Host "sqmId: $($config.'telemetry.sqmId')"

    # Update values
    $config.'telemetry.machineId' = $MACHINE_ID
    $config.'telemetry.macMachineId' = $MAC_MACHINE_ID
    $config.'telemetry.devDeviceId' = $UUID
    $config.'telemetry.sqmId' = $SQM_ID

    # Save changes
    $updatedJson = $config | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText(
        [System.IO.Path]::GetFullPath($STORAGE_FILE), 
        $updatedJson, 
        [System.Text.Encoding]::UTF8
    )

    # Show new values
    Write-Host "`nNew values:"
    Write-Host "machineId: $MACHINE_ID"
    Write-Host "macMachineId: $MAC_MACHINE_ID"
    Write-Host "devDeviceId: $UUID"
    Write-Host "sqmId: $SQM_ID"

    Write-Host "`nConfiguration updated successfully"
    Write-Host "Backup saved to: $BACKUP_DIR\$backupName"
    Write-Host "Please restart Cursor to apply changes"

    # Ask about disabling auto-updates
    Write-Host "`nWould you like to disable Cursor auto-updates?"
    Write-Host "0) No - Keep default settings (press Enter)"
    Write-Host "1) Yes - Disable auto-updates"
    $choice = Read-Host "Please enter your choice (0)"

    if ($choice -eq "1") {
        Write-Host "`nProcessing auto-update settings..."
        $updaterPath = "$env:LOCALAPPDATA\cursor-updater"

        try {
            # Take ownership and grant full permissions first
            $takeown = Start-Process "takeown.exe" -ArgumentList "/f `"$updaterPath`"" -Wait -NoNewWindow -PassThru
            if ($takeown.ExitCode -eq 0) {
                Write-Host "Successfully took ownership of the directory"
            }

            # Grant administrators full control
            $cacls = Start-Process "icacls.exe" -ArgumentList "`"$updaterPath`" /grant administrators:F" -Wait -NoNewWindow -PassThru
            if ($cacls.ExitCode -eq 0) {
                Write-Host "Successfully granted permissions"
            }

            # Remove existing directory if it exists
            if (Test-Path $updaterPath) {
                # Try using Remove-Item with -Force first
                try {
                    Remove-Item -Path $updaterPath -Force -Recurse -ErrorAction Stop
                    Write-Host "Successfully removed cursor-updater directory"
                } catch {
                    # If Remove-Item fails, try using rd command
                    $rd = Start-Process "cmd.exe" -ArgumentList "/c rd /s /q `"$updaterPath`"" -Wait -NoNewWindow -PassThru
                    if ($rd.ExitCode -eq 0) {
                        Write-Host "Successfully removed cursor-updater directory using rd command"
                    } else {
                        throw "Failed to remove directory using both methods"
                    }
                }
            }

            # Create blocking file
            New-Item -Path $updaterPath -ItemType File -Force -ErrorAction Stop | Out-Null
            Write-Host "Successfully created blocking file"

            # Set file permissions using both methods for redundancy
            Set-ItemProperty -Path $updaterPath -Name IsReadOnly -Value $true -ErrorAction Stop
            
            # Use icacls to set restrictive permissions
            $icacls = Start-Process "icacls.exe" -ArgumentList "`"$updaterPath`" /inheritance:r /grant:r `"$($env:USERNAME):(R)`" `"SYSTEM:(R)`"" -Wait -NoNewWindow -PassThru
            
            if ($icacls.ExitCode -eq 0) {
                Write-Host "Successfully set file permissions"
                Write-Host "Auto-updates have been disabled"
            } else {
                Write-Host "Warning: Permission setting may have failed, attempting alternate method..."
                
                # Alternate method using cacls
                $cacls = Start-Process "cacls.exe" -ArgumentList "`"$updaterPath`" /E /P $($env:USERNAME):R" -Wait -NoNewWindow -PassThru
                if ($cacls.ExitCode -eq 0) {
                    Write-Host "Successfully set file permissions using alternate method"
                } else {
                    Write-Host "Warning: Both permission setting methods failed"
                }
            }

            # Verify settings
            if (Test-Path $updaterPath) {
                $fileInfo = Get-ItemProperty $updaterPath
                if ($fileInfo.IsReadOnly) {
                    Write-Host "Verification successful: File is read-only"
                } else {
                    Write-Host "Warning: File is not read-only, but may still block updates"
                }
            } else {
                Write-Host "Warning: Could not verify settings - file not found"
            }
        } catch {
            Write-Host "`nError occurred while disabling auto-updates: $_"
            Write-Host "`nTrying alternative approach..."
            
            try {
                # Alternative approach using cmd.exe with elevated privileges
                $cmdArgs = "/c takeown /f `"$updaterPath`" && icacls `"$updaterPath`" /grant administrators:F && rd /s /q `"$updaterPath`" && echo. > `"$updaterPath`" && icacls `"$updaterPath`" /inheritance:r /grant:r `"$($env:USERNAME):(R)`""
                $altMethod = Start-Process "cmd.exe" -ArgumentList $cmdArgs -Wait -NoNewWindow -PassThru
                
                if ($altMethod.ExitCode -eq 0) {
                    Write-Host "Successfully disabled auto-updates using alternative method"
                } else {
                    throw "Alternative method also failed"
                }
            } catch {
                Write-Host "`nBoth automatic methods failed. Please try these manual steps:"
                Write-Host "1. Open Command Prompt as Administrator"
                Write-Host "2. Run these commands one by one:"
                Write-Host "   takeown /f `"$updaterPath`""
                Write-Host "   icacls `"$updaterPath`" /grant administrators:F"
                Write-Host "   rd /s /q `"$updaterPath`""
                Write-Host "   echo. > `"$updaterPath`""
                Write-Host "   icacls `"$updaterPath`" /inheritance:r /grant:r `"%USERNAME%:(R)`""
            }
        }
    } else {
        Write-Host "Keeping default settings, no changes made to auto-update"
    }

    # Add backup management
    Write-Host "`n$GREEN[Info]$NC Managing backups..."
    try {
        # Keep only last 5 backups
        $maxBackups = 5
        $backups = Get-ChildItem -Path $BACKUP_DIR -Filter "storage.json.backup_*" | Sort-Object LastWriteTime -Descending
        
        if ($backups.Count -gt $maxBackups) {
            Write-Host "$YELLOW[Cleanup]$NC Removing old backups (keeping last $maxBackups)..."
            $backups | Select-Object -Skip $maxBackups | ForEach-Object {
                Remove-Item $_.FullName -Force
                Write-Host "Removed: $($_.Name)"
            }
        }

        # Show backup status
        Write-Host "`n$GREEN[Backup Status]$NC"
        Write-Host "Backup Directory: $BACKUP_DIR"
        Write-Host "Total Backups: $($backups.Count)"
        Write-Host "Latest Backups:"
        $backups | Select-Object -First 3 | ForEach-Object {
            Write-Host "  - $($_.Name) ($(Get-Date $_.LastWriteTime -Format 'yyyy-MM-dd HH:mm:ss'))"
        }
    } catch {
        Write-Host "$RED[Error]$NC Failed to manage backups: $_"
    }

    # Show final status report
    Write-Host "`n$GREEN[Status Report]$NC"
    Write-Host "1. Configuration Changes:"
    Write-Host "   - Device ID: $($config.'telemetry.devDeviceId')"
    Write-Host "   - Machine ID: $($config.'telemetry.machineId')"
    Write-Host "   - Mac Machine ID: $($config.'telemetry.macMachineId')"
    Write-Host "   - SQM ID: $($config.'telemetry.sqmId')"
    
    Write-Host "`n2. Auto-Update Status:"
    if (Test-Path "$env:LOCALAPPDATA\cursor-updater") {
        $updateStatus = if ((Get-Item "$env:LOCALAPPDATA\cursor-updater") -is [System.IO.FileInfo]) {
            "Disabled (blocking file in place)"
        } else {
            "Enabled (directory exists)"
        }
    } else {
        $updateStatus = "Unknown"
    }
    Write-Host "   - Status: $updateStatus"
    
    Write-Host "`n3. Backup Information:"
    Write-Host "   - Latest Backup: $backupName"
    Write-Host "   - Backup Location: $BACKUP_DIR"
    
    Write-Host "`n$GREEN[Next Steps]$NC"
    Write-Host "1. Restart Cursor to apply changes"
    Write-Host "2. Verify changes in Cursor's settings"
    Write-Host "3. Keep this backup location safe: $BACKUP_DIR"

} catch {
    Write-Host "$RED[Error]$NC $_"
    if ($originalContent) {
        [System.IO.File]::WriteAllText(
            [System.IO.Path]::GetFullPath($STORAGE_FILE), 
            $originalContent, 
            [System.Text.Encoding]::UTF8
        )
        Write-Host "$GREEN[Recovery]$NC Original configuration restored"
    }
}

Read-Host "Press Enter to exit" 