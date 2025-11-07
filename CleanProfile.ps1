#This script is equivalent to manually clean up user profile in System > Advanced > User Profiles
#Uses Win32_UserProfile WMI class to programmatically remove profiles
#Uses Remove-CimInstance = safe cleanup = removes registry and files

# CONFIGURATION
$daysInactive = 1
$excludedUsers = @('Administrator', 'Default', 'Default User', 'Public', 'SAdmin', 'All Users')  # Add any accounts to exclude

# Get current user session names to avoid deleting logged-in profiles
$currentUsers = quser | ForEach-Object { ($_ -split '\s+')[0] }

# Get all profiles
$profiles = Get-CimInstance Win32_UserProfile | Where-Object {
    -not $_.Special -and
    $_.LocalPath -like 'C:\Users\*' -and
    !(($excludedUsers + $currentUsers) -contains ($_.LocalPath -split '\\')[-1]) -and
    $_.LastUseTime -lt (Get-Date).AddDays(-$daysInactive)
}

# Delete profiles
foreach ($profile in $profiles) {
    try {
        Write-Host "Deleting profile: $($profile.LocalPath)"
        $profile | Remove-CimInstance
    } catch {
        Write-Warning "Failed to delete profile: $($profile.LocalPath) - $_"
    }
}
