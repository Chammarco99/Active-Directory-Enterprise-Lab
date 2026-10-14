
# ============================================================
# Marcotech Ltd - Active Directory User Provisioning
# ============================================================
# Description:
# Automates employee account creation from a CSV dataset.
#
# Features:
# - Imports employee data from CSV
# - Creates users in departmental Organizational Units
# - Assigns users to departmental security groups
# - Skips existing user accounts
# - Prevents duplicate group membership attempts
# - Prompts securely for a temporary password
# - Requires password change at first logon
# - Handles errors during provisioning
#
# Domain: Marcotech.ltd
# Environment: Windows Server 2022 / Active Directory
# ============================================================

# Stop if the Active Directory module cannot be loaded
Import-Module ActiveDirectory -ErrorAction Stop

# CSV file location relative to this script
$CsvPath = Join-Path $PSScriptRoot "..\data\employees.csv"

# Verify that the CSV file exists
if (-not (Test-Path -LiteralPath $CsvPath)) {
    throw "Employee CSV file not found: $CsvPath"
}

# Import employee records
$Users = @(Import-Csv -LiteralPath $CsvPath)

if ($Users.Count -eq 0) {
    throw "The employee CSV file contains no records."
}

# Verify required CSV columns
$RequiredColumns = @(
    "FirstName",
    "LastName",
    "Username",
    "Department"
)

foreach ($Column in $RequiredColumns) {
    if ($Column -notin $Users[0].PSObject.Properties.Name) {
        throw "Missing required CSV column: $Column"
    }
}

# Prompt administrator for a temporary password
# The password is not stored in plaintext in the script
$Password = Read-Host `
    "Enter temporary password for new users" `
    -AsSecureString

# Track provisioning results
$Created = 0
$Skipped = 0
$Failed = 0

foreach ($User in $Users) {

    $Username = $User.Username.Trim()
    $Department = $User.Department.Trim()

    # Construct departmental OU and security group
    $OU = "OU=$Department,OU=Users,OU=Company,DC=Marcotech,DC=ltd"
    $GroupName = "SG_$Department"

    Write-Host "`nProcessing: $Username" -ForegroundColor Cyan

    try {

        # Validate employee information
        if (
            [string]::IsNullOrWhiteSpace($Username) -or
            [string]::IsNullOrWhiteSpace($Department) -or
            [string]::IsNullOrWhiteSpace($User.FirstName) -or
            [string]::IsNullOrWhiteSpace($User.LastName)
        ) {
            throw "Employee record contains missing required values."
        }

        # Confirm that the departmental OU exists
        Get-ADOrganizationalUnit `
            -Identity $OU `
            -ErrorAction Stop | Out-Null

        # Confirm that the departmental group exists
        $Group = Get-ADGroup `
            -Identity $GroupName `
            -ErrorAction Stop

        # Check whether the user already exists
        $ExistingUser = Get-ADUser `
            -Identity $Username `
            -ErrorAction SilentlyContinue

        if ($ExistingUser) {

            Write-Host "SKIPPED: $Username already exists." `
                -ForegroundColor Yellow

            $Skipped++

            $ADUser = $ExistingUser

        }
        else {

            # Create the Active Directory account
            $ADUser = New-ADUser `
                -Name "$($User.FirstName) $($User.LastName)" `
                -GivenName $User.FirstName `
                -Surname $User.LastName `
                -SamAccountName $Username `
                -UserPrincipalName "$Username@Marcotech.ltd" `
                -Department $Department `
                -Path $OU `
                -AccountPassword $Password `
                -Enabled $true `
                -ChangePasswordAtLogon $true `
                -PassThru `
                -ErrorAction Stop

            Write-Host "CREATED: $Username in $Department OU" `
                -ForegroundColor Green

            $Created++
        }

        # Check whether the user is already a group member
        $IsMember = @(
            Get-ADPrincipalGroupMembership `
                -Identity $ADUser `
                -ErrorAction Stop |
            Where-Object {
                $_.DistinguishedName -eq $Group.DistinguishedName
            }
        ).Count -gt 0

        if (-not $IsMember) {

            Add-ADGroupMember `
                -Identity $Group `
                -Members $ADUser `
                -ErrorAction Stop

            Write-Host "GROUP ADDED: $Username -> $GroupName" `
                -ForegroundColor Green

        }
        else {

            Write-Host "GROUP VERIFIED: $Username already in $GroupName" `
                -ForegroundColor Yellow
        }

    }
    catch {

        $Failed++

        Write-Host "ERROR processing $Username" `
            -ForegroundColor Red

        Write-Host $_.Exception.Message `
            -ForegroundColor Red
    }
}

# Display final provisioning summary
Write-Host "`n========================================"
Write-Host "Marcotech AD Provisioning Summary"
Write-Host "========================================"
Write-Host "Created: $Created"
Write-Host "Existing users skipped: $Skipped"
Write-Host "Errors: $Failed"
Write-Host "========================================"
