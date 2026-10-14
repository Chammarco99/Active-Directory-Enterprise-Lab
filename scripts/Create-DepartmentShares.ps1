
# ============================================================
# Marcotech Ltd - Department File Share Automation
# ============================================================
# Description:
# Creates departmental folders, configures NTFS permissions,
# and creates SMB network shares.
#
# Departments:
# HR, Finance, IT, Management, Operations
#
# Sales was configured manually during the lab.
#
# Domain: Marcotech.ltd
# Server: DC01 - Windows Server 2022
#
# Run in an elevated PowerShell session on DC01.
# Intended for a controlled lab environment.
# ============================================================

#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

Import-Module ActiveDirectory -ErrorAction Stop
Import-Module SmbShare -ErrorAction Stop

$Departments = @(
    "HR",
    "Finance",
    "IT",
    "Management",
    "Operations"
)

$BasePath = "C:\CompanyShares"
$Domain = "MARCOTECH"
$Admins = "$Domain\Domain Admins"

# Safety setting:
# Existing folders are not modified automatically.
# Set to $true only after reviewing their existing permissions.
$ModifyExistingFolders = $false

$Succeeded = 0
$Failed = 0
$Skipped = 0

# Create base directory if required
if (-not (Test-Path -LiteralPath $BasePath)) {
    New-Item -Path $BasePath -ItemType Directory -Force |
        Out-Null
}

foreach ($Department in $Departments) {

    $FolderPath = Join-Path $BasePath $Department
    $GroupName = "SG_$Department"
    $Group = "$Domain\$GroupName"

    Write-Host "`nConfiguring $Department..." -ForegroundColor Cyan

    try {

        # Verify departmental security group
        Get-ADGroup -Identity $GroupName -ErrorAction Stop |
            Out-Null

        # Check for an existing SMB share
        $ExistingShare = Get-SmbShare `
            -Name $Department `
            -ErrorAction SilentlyContinue

        if ($ExistingShare) {

            if ($ExistingShare.Path -ne $FolderPath) {
                throw "Share $Department points to a different folder."
            }

            Write-Host "Share already exists: $Department" `
                -ForegroundColor Yellow
        }

        # Avoid unexpected changes to existing folders
        if (Test-Path -LiteralPath $FolderPath) {

            if (-not $ModifyExistingFolders) {

                Write-Host "SKIPPED: Existing folder requires review." `
                    -ForegroundColor Yellow

                Write-Host "Folder: $FolderPath"

                $Skipped++
                continue
            }

        }
        else {

            New-Item `
                -Path $FolderPath `
                -ItemType Directory `
                -ErrorAction Stop |
                Out-Null

            Write-Host "Folder created: $FolderPath" `
                -ForegroundColor Green
        }

        # Disable NTFS inheritance and remove inherited ACEs
        & icacls.exe $FolderPath /inheritance:r | Out-Null

        if ($LASTEXITCODE -ne 0) {
            throw "Failed to disable NTFS inheritance."
        }

        # Grant SYSTEM Full Control
        & icacls.exe $FolderPath /grant:r `
            "SYSTEM:(OI)(CI)F" | Out-Null

        if ($LASTEXITCODE -ne 0) {
            throw "Failed to grant SYSTEM permissions."
        }

        # Grant Domain Admins Full Control
        & icacls.exe $FolderPath /grant:r `
            "${Admins}:(OI)(CI)F" | Out-Null

        if ($LASTEXITCODE -ne 0) {
            throw "Failed to grant Domain Admins permissions."
        }

        # Grant department group Modify permissions
        & icacls.exe $FolderPath /grant:r `
            "${Group}:(OI)(CI)M" | Out-Null

        if ($LASTEXITCODE -ne 0) {
            throw "Failed to grant departmental permissions."
        }

        # Create SMB share if it does not exist
        if (-not $ExistingShare) {

            New-SmbShare `
                -Name $Department `
                -Path $FolderPath `
                -ChangeAccess $Group `
                -FullAccess $Admins `
                -ErrorAction Stop |
                Out-Null

            Write-Host "SMB share created: \\DC01\$Department" `
                -ForegroundColor Green
        }

        Write-Host "NTFS and SMB configuration completed." `
            -ForegroundColor Green

        $Succeeded++

    }
    catch {

        $Failed++

        Write-Host "ERROR configuring $Department" `
            -ForegroundColor Red

        Write-Host $_.Exception.Message `
            -ForegroundColor Red
    }
}

# Display results
Write-Host "`n========================================"
Write-Host "Marcotech Department Share Summary"
Write-Host "========================================"
Write-Host "Completed: $Succeeded"
Write-Host "Skipped: $Skipped"
Write-Host "Failed: $Failed"
Write-Host "========================================"
