# ==============================================================================
# Script Name: cleanprofile.ps1
# Description: Safely deletes inactive user profiles via CIM/WMI while a live 
#              user is logged in. Only kills locking processes belonging to 
#              INACTIVE users; ignores the active user's processes.
# Run Level:   Must be run as an Administrator (or via PsExec -s)
# ==============================================================================

# --- CONFIGURATION ---
$daysInactive = 0
$excludedUsers = @('Administrator', 'Default', 'Default User', 'Public', 'SAdmin', 'All Users')

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "   STARTING USER PROFILE CLEANUP (LIVE USER SAFE)   " -ForegroundColor Cyan
Write-Host "====================================================`n" -ForegroundColor Cyan

# --- STEP 1: PARSE USER SESSIONS ---
Write-Host "[1/4] Identifying active and inactive user profiles..." -ForegroundColor Cyan

# Get active user sessions via quser to ensure we protect the current user
$currentUsers = quser 2>$null | ForEach-Object { 
    if ($_ -match '^\s*([a-zA-Z0-9\._-]+)') { $Matches[1] } 
}

if ($currentUsers) {
    Write-Host "Detected active logged-in user(s): $($currentUsers -join ', ')" -ForegroundColor Green
} else {
    Write-Host "No active users detected. Proceeding with standard machine cleanup." -ForegroundColor Yellow
}

# Query all eligible profiles for deletion (excludes active and system users)
$profiles = Get-CimInstance Win32_UserProfile | Where-Object {
    -not $_.Special -and
    $_.LocalPath -like 'C:\Users\*' -and
    !(($excludedUsers + $currentUsers) -contains ($_.LocalPath -split '\\')[-1]) -and
    $_.LastUseTime -lt (Get-Date).AddDays(-$daysInactive)
}

Write-Host "Found $($profiles.Count) profile(s) targeted for removal." -ForegroundColor Yellow


# --- STEP 2: TARGETED LOCK BREAKING ---
Write-Host "[2/4] Selectively clearing background locks for targeted profiles..." -ForegroundColor Cyan

# Safe to stop machine-wide search engine (will briefly pause indexing for the active user, but won't crash apps)
Stop-Service -Name "WSearch" -Force -ErrorAction SilentlyContinue

# Identify the folder names of the users we WANT to delete
$targetedUsernames = $profiles | ForEach-Object { ($_.LocalPath -split '\\')[-1] }

# Safely kill processes ONLY if they are running out of a targeted user's profile folder
$LockingProcesses = @('OneDrive', 'MicrosoftEdgeUpdate', 'msedge', 'Teams', 'ms-teams')
foreach ($proc in $LockingProcesses) {
    Get-Process -Name $proc -ErrorAction SilentlyContinue | Where-Object {
        $path = $_.Path
        # If the process executable path contains an inactive user's folder name, kill it
        $isTargeted = $false
        foreach ($username in $targetedUsernames) {
            if ($path -like "*\Users\$username\*") { $isTargeted = $true; break }
        }
        $isTargeted
    } | Stop-Process -Force -ErrorAction SilentlyContinue
}

# Allow a split second for the file handles to drop
Start-Sleep -Seconds 2


# --- STEP 3: AUTOMATED REGISTRY UNLOAD ROUTINE ---
Write-Host "[3/4] Sweeping for loaded registry hives (Loaded = True)..." -ForegroundColor Cyan

foreach ($profile in $profiles) {
    if ($profile.Loaded -eq $true) {
        $sid = $profile.SID
        Write-Host " -> Profile active in memory: $($profile.LocalPath). Unloading SID: $sid..." -ForegroundColor Yellow
        
        # Force garbage collection to ensure PowerShell dropped its own internal handles
        [System.GC]::Collect()
        [System.GC]::WaitForPendingFinalizers()
        
        # Force the registry hive to detach from HKEY_USERS
        reg unload "HKU\$sid" 2>&1 | Out-Null
    }
}

Start-Sleep -Seconds 1


# --- STEP 4: PROFILE DELETION LOOP ---
Write-Host "[4/4] Executing profile deletion queue..." -ForegroundColor Cyan
Write-Host "----------------------------------------------------" -ForegroundColor Gray

$successCount = 0
$failCount = 0

foreach ($profile in $profiles) {
    try {
        Write-Host "Deleting profile directory and keys: $($profile.LocalPath)" -ForegroundColor White
        
        # Native, safe CIM pipeline cleanup
        $profile | Remove-CimInstance
        
        Write-Host "Successfully removed: $($profile.LocalPath)" -ForegroundColor Green
        $successCount++
    } catch {
        Write-Warning "Failed to delete profile: $($profile.LocalPath) - $_"
        $failCount++
    }
}


# --- POST-CLEANUP RESTORATION ---
Write-Host "----------------------------------------------------" -ForegroundColor Gray
Write-Host "Restoring Windows background services..." -ForegroundColor Cyan
Start-Service -Name "WSearch" -ErrorAction SilentlyContinue

Write-Host "`n====================================================" -ForegroundColor Green
Write-Host "   CLEANUP COMPLETE: $successCount Succeeded, $failCount Failed" -ForegroundColor Green
Write-Host "====================================================" -ForegroundColor Green
