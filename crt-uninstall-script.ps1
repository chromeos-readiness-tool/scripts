# Check if the script is running with Administrator privileges
$IsAdmin = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
$IsAdminRole = $IsAdmin.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $IsAdminRole) {
    Write-Host "This script requires Administrator privileges. Restarting with elevated permissions..."
    
    # Restart the script with administrator privileges only if it hasn't already been elevated
    Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    Exit
}

# Task name to check and run
$TaskNameToRun = "ChromeOS Readiness Tool - Uninstall"

# Check if the task exists
try {
    $TaskExists = schtasks /Query /TN "$TaskNameToRun" /FO LIST /V 2>&1 | Out-String
    if ($TaskExists -match "$TaskNameToRun") {
        Write-Host "Task '$TaskNameToRun' exists. Running it now..."

        # Run the task
        schtasks /Run /TN "$TaskNameToRun" | Out-Host

        # Wait for the task to complete
        Write-Host "Waiting for task '$TaskNameToRun' to complete..."
        do {
            Start-Sleep -Seconds 5  # Poll every 5 seconds
            $TaskStatus = schtasks /Query /TN "$TaskNameToRun" /FO LIST /V 2>&1 | Select-String "Status"
            Write-Host "Current Status: $($TaskStatus -replace 'Status:\s+', '')"
        } while ($TaskStatus -match "Running")

        Write-Host "Task '$TaskNameToRun' has completed."
    } else {
        Write-Host "Task '$TaskNameToRun' does not exist. Skipping..."
    }
} catch {
    Write-Warning "An error occurred while checking for the task: $($_.Exception.Message)"
}

# List of process names to stop
$PartialNames = @(
    "Status Monitor - ChromeOS Readiness Tool"
)

$ProcessNamesToStop = @(
    "Data Collector - ChromeOS Readiness Tool",
    "Data Service - ChromeOS Readiness Tool",
    "Background Data Collector  - ChromeOS Readiness Tool", 
    "Foreground Data Collector - ChromeOS Readiness Tool"
)

foreach ($PartialName in $PartialNames) {
    Write-Host "Checking for processes matching: $PartialName"
    
    # Get processes matching the partial name
    $ProcessesToStop = Get-Process | Where-Object { $_.Name -like "*$PartialName*" } -ErrorAction SilentlyContinue

    if ($ProcessesToStop) {
        Write-Host "Found processe: $PartialName. Stopping them now..."
        foreach ($Process in $ProcessesToStop) {
            Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
            Write-Host "Stopped process: $($Process.Name) (PID: $($Process.Id))"
        }
    } else {
        Write-Host "No running processes found for: $PartialName. Skipping..."
    }
}

foreach ($ProcessName in $ProcessNamesToStop) {
    Write-Host "Checking for process: $ProcessName"
    
    # Get the process if it exists
    $ProcessesToStop = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue

    if ($ProcessesToStop) {
        Write-Host "Found process: $ProcessName. Stopping it now..."
        foreach ($Process in $ProcessesToStop) {
            Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
            Write-Host "Stopped process: $($Process.Name) (PID: $($Process.Id))"
        }
    } else {
        Write-Host "No running process found for: $ProcessName. Skipping..."
    }
}

Write-Host "All specified processes have been checked and stopped if they were running."

# List of application names to search and uninstall
$AppNames = @(
    "ChromeOS Readiness Tool - Installer",
    "ChromeOS Readiness Tool - Report Generator",  
    "ChromeOS Readiness Tool Hybrid",  
    "ChromeOS Readiness Tool"
    
)

foreach ($AppName in $AppNames) {
    Write-Host "Searching for application: $AppName"
    
    # Search in both 32-bit and 64-bit registry paths
    $App = Get-ItemProperty -Path "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" `
                            -ErrorAction SilentlyContinue |
           Where-Object { $_.DisplayName -like "*$AppName*" }

    if (-not $App) {
        $App = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" `
                                -ErrorAction SilentlyContinue |
               Where-Object { $_.DisplayName -like "*$AppName*" }
    }

    if ($App) {
        Write-Host "Found application: $($App.DisplayName)"
        Write-Host "Registry Details: $($App | Format-List | Out-String)"

        if ($App.PSChildName) {
            # Ensure that $App.PSChildName is a single string (handling multiple GUIDs)
            $ProductCode = $App.PSChildName -join ','

            Write-Host "Attempting MSI uninstallation with ProductCode: $ProductCode"
            Start-Process msiexec -ArgumentList "/x", $ProductCode, "/quiet", "/norestart" -NoNewWindow -Wait
            Write-Host "$AppName has been uninstalled successfully."
        } elseif ($App.UninstallString) {
            # Uninstall using UninstallString
            Write-Host "No MSI ProductCode found. Attempting uninstallation using UninstallString: $($App.UninstallString)"
            Start-Process -FilePath "cmd.exe" -ArgumentList "/c $($App.UninstallString)" -NoNewWindow -Wait
            Write-Host "$AppName has been uninstalled successfully."
        } else {
            # Log if no valid uninstall method is found
            Write-Host "No valid uninstall method found for application: $($App.DisplayName)"
            Write-Host "Please check the application manually."
        }
    } else {
        Write-Host "$AppName not found in installed applications. Skipping..."
    }
}

# Get the base user profile path dynamically
$UserProfilePath = "$env:USERPROFILE"

# Folders to remove share
$FoldersToRemoveShare = @(
    @{ FolderPath = "$UserProfilePath\AppData\Local\CRT\CRT Logs"; ShareName = "CRT Logs" },
    @{ FolderPath = "$UserProfilePath\AppData\Local\CRT\Installation\SetupFiles\Setup"; ShareName = "CRTSetup" }
)

# Remove share for specified folders
foreach ($folder in $FoldersToRemoveShare) {
    $folderPath = $folder.FolderPath
    $shareName = $folder.ShareName

    try {
        # Check if the share exists
        $share = Get-SmbShare -Name $shareName -ErrorAction SilentlyContinue
        if ($share) {
            # Remove the SMB share
            Remove-SmbShare -Name $shareName -Force
            Write-Host "Successfully removed sharing for folder: $folderPath"
        } else {
            Write-Host "The folder '$folderPath' is not shared. Skipping..."
        }
    } catch {
        # Handle any errors
        Write-Host "Error removing the shared folder: $folderPath"
        Write-Host "Error details: $($_.Exception.Message)"
    }
}

# Registry folders to delete
$RegistryPaths = @(
    "HKLM:\SOFTWARE\CRTApplication",         
    "HKLM:\SOFTWARE\WOW6432Node\CRTApplication" 
)

# Delete registry folders
foreach ($Path in $RegistryPaths) {
    try {
        if (Test-Path -Path $Path) {
            # Remove the registry folder
            Remove-Item -Path $Path -Recurse -Force

            # Custom success message for each path
            Write-Host "Registry folder at '$Path' was successfully deleted!"
        } else {
            Write-Host "Registry folder not found at '$Path'. Skipping..."
        }
    } catch {
        # Error handling for each path
        Write-Host "Error deleting registry folder at '$Path'."
        Write-Host "Error details: $($_.Exception.Message)"
    }
}


# Get the base user profile path dynamically
$UserProfilePath = "$env:USERPROFILE"

# Folder paths to delete
$FileSystemPaths = @(
    "C:\Program Files\ChromeOS Readiness Tool",
    "C:\Program Files (x86)\ChromeOS Readiness Tool Hybrid",                   
    "C:\Program Files (x86)\ChromeOS Readiness Tool",
    "C:\ProgramData\CRT_Report",
    "C:\Users\Public\Documents\CRT",                              
    "$UserProfilePath\AppData\Local\CRT"          
)

# Delete normal file system folders
foreach ($Folder in $FileSystemPaths) {
    try {
        if (Test-Path -Path $Folder) {
            Remove-Item -Path $Folder -Recurse -Force
            Write-Host "Folder at '$Folder' was successfully deleted!"
        } else {
            Write-Host "Folder not found at '$Folder'. Skipping..."
        }
    } catch {
        Write-Host "Error deleting folder at '$Folder'."
        Write-Host "Error details: $($_.Exception.Message)"
    }
}

# Tasks to delete
$TaskNames = @(
    "ChromeOS Readiness Tool - Device Count Update",
    "ChromeOS Readiness Tool - GCP Logs Upload",
    "ChromeOS Readiness Tool - Report Generation",
    "ChromeOS Readiness Tool - Uninstall",
    "CRT Data Service H",
    "CRT Status Monitor H"
)

# Delete tasks
foreach ($TaskName in $TaskNames) {
    try {
        # Check if the task exists
        $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        if ($task) {
            # Unregister the scheduled task
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
            Write-Host "Successfully deleted task: $TaskName"
        } else {
            Write-Host "Task '$TaskName' not found. Skipping..."
        }
    } catch {
        Write-Host "Error deleting task '$TaskName'."
        Write-Host "Error details: $($_.Exception.Message)"
    }
}

Write-Host "Press Enter to exit."
Read-Host
