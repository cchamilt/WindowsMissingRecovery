# Module metadata
$ModuleName = "WindowsMissingRecovery"
$ModuleVersion = "1.0.0"

# Module configuration (in-memory state)
$script:Config = @{
    BackupRoot = $null
    MachineName = $env:COMPUTERNAME
    WindowsMissingRecoveryPath = Join-Path $PSScriptRoot "Config"
    CloudProvider = $null
    ModuleVersion = $ModuleVersion
    LastConfigured = $null
    IsInitialized = $false
    EmailSettings = @{
        FromAddress = $null
        ToAddress = $null
        Password = $null
        SmtpServer = $null
        SmtpPort = 587
        EnableSsl = $true
    }
    BackupSettings = @{
        RetentionDays = 30
        ExcludePaths = @()
        IncludePaths = @()
    }
    ScheduleSettings = @{
        BackupSchedule = $null
        UpdateSchedule = $null
    }
    NotificationSettings = @{
        EnableEmail = $false
        NotifyOnSuccess = $false
        NotifyOnFailure = $true
    }
    RecoverySettings = @{
        Mode = "Selective"
        ForceOverwrite = $false
    }
    LoggingSettings = @{
        Path = $null
        Level = "Information"
    }
    UpdateSettings = @{
        AutoUpdate = $true
        ExcludePackages = @()
    }
}

# Define core functions first
function Get-WindowsMissingRecovery {
    return $script:Config
}

function Set-WindowsMissingRecovery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [hashtable]$Config,
        
        [Parameter(Mandatory=$false)]
        [string]$BackupRoot,
        
        [Parameter(Mandatory=$false)]
        [string]$MachineName,
        
        [Parameter(Mandatory=$false)]
        [string]$WindowsMissingRecoveryPath,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet('OneDrive', 'GoogleDrive', 'Dropbox', 'Box', 'Custom')]
        [string]$CloudProvider
    )
    
    if ($Config) {
        $script:Config = $Config
    } else {
        if ($BackupRoot) { $script:Config.BackupRoot = $BackupRoot }
        if ($MachineName) { $script:Config.MachineName = $MachineName }
        if ($WindowsMissingRecoveryPath) { $script:Config.WindowsMissingRecoveryPath = $WindowsMissingRecoveryPath }
        if ($CloudProvider) { $script:Config.CloudProvider = $CloudProvider }
    }
    
    $script:Config.LastConfigured = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
}

# Helper function to load private scripts on demand
function Import-PrivateScripts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet('backup', 'restore', 'setup', 'tasks', 'scripts')]
        [string]$Category
    )
    
    $categoryPath = Join-Path $PSScriptRoot "Private\$Category"
    Write-Verbose "Looking for $Category scripts in: $categoryPath"
    
    if (Test-Path $categoryPath) {
        $scripts = Get-ChildItem -Path "$categoryPath\*.ps1" -ErrorAction SilentlyContinue
        Write-Verbose "Found $($scripts.Count) $Category scripts"
        
        foreach ($script in $scripts) {
            try {
                Write-Verbose "Loading script: $($script.FullName)"
                . $script.FullName
                Write-Host "Successfully loaded $Category script: $($script.Name)" -ForegroundColor Green
            } catch {
                Write-Warning "Failed to load $Category script $($script.Name): $_"
            }
        }
    } else {
        Write-Warning "$Category scripts directory not found at: $categoryPath"
    }
}

# Load core utilities first (always needed)
$CorePath = Join-Path $PSScriptRoot "Private\Core\WindowsMissingRecovery.Core.ps1"
if (Test-Path $CorePath) {
    try {
        . $CorePath
        Write-Verbose "Successfully loaded core utilities from: $CorePath"
        
        # Try to initialize module configuration from config file
        Initialize-ModuleFromConfig
    } catch {
        Write-Warning "Failed to load core utilities from: $CorePath"
        Write-Warning $_.Exception.Message
    }
} else {
    Write-Warning "Core utilities not found at: $CorePath"
}

# Load only public functions at module import time
$PublicPath = Join-Path $PSScriptRoot "Public"
if (-not (Test-Path $PublicPath)) {
    Write-Warning "Public functions directory not found at: $PublicPath"
    $Public = @()
} else {
    $Public = @(Get-ChildItem -Path "$PublicPath\*.ps1" -ErrorAction SilentlyContinue)
}

# Load public functions and track successfully loaded ones
$LoadedFunctions = @()
foreach ($import in $Public) {
    $functionName = $import.BaseName
    Write-Verbose "Attempting to load: $functionName from $($import.FullName)"
    
    try {
        . $import.FullName
        
        # Small delay to ensure function is registered
        Start-Sleep -Milliseconds 10
        
        # Verify the function was actually loaded
        if (Get-Command $functionName -ErrorAction SilentlyContinue) {
            $LoadedFunctions += $functionName
            Write-Verbose "Successfully loaded public function: $functionName"
        } else {
            Write-Warning "Function $functionName not found after loading $($import.FullName)"
        }
    } catch {
        Write-Warning "Failed to import public function $($import.FullName): $($_.Exception.Message)"
        Write-Verbose "Stack trace: $($_.ScriptStackTrace)"
    }
}

# Export all functions together
$ModuleFunctions = @('Import-PrivateScripts', 'Get-WindowsMissingRecovery', 'Set-WindowsMissingRecovery')
$AllFunctions = $LoadedFunctions + $ModuleFunctions

# Only export functions that actually exist
$ExistingFunctions = @()
foreach ($funcName in $AllFunctions) {
    if (Get-Command $funcName -ErrorAction SilentlyContinue) {
        $ExistingFunctions += $funcName
    } else {
        Write-Warning "Function $funcName not found, skipping export"
    }
}

if ($ExistingFunctions.Count -gt 0) {
    Export-ModuleMember -Function $ExistingFunctions
    Write-Verbose "Exported $($ExistingFunctions.Count) functions: $($ExistingFunctions -join ', ')"
} else {
    Write-Warning "No functions were successfully loaded to export"
} 