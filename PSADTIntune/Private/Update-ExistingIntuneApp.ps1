function Update-ExistingIntuneApp {
    <#
    .SYNOPSIS
        Replaces the package content of an existing Intune Win32 app and bumps its version.
    .DESCRIPTION
        Uploads the new .intunewin to the existing app and, when the PSADT AppVersion differs,
        sets the app's version to match. Detection rules, assignments and other settings are
        NOT changed - IntuneWin32App has no cmdlet to update detection rules in place.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)][string]$AppId,
        [Parameter(Mandatory)][hashtable]$Paths,
        [Parameter(Mandatory)][pscustomobject]$Config,
        [Parameter(Mandatory)][pscustomobject]$Metadata
    )

    try {
        Connect-IntuneSession -Config $Config

        Write-Host "Retrieving existing application..." -ForegroundColor Cyan
        $existingApp = Get-IntuneWin32App -ID $AppId -ErrorAction Stop
        if ($null -eq $existingApp) {
            throw "No application found with ID: $AppId"
        }

        $newVersion = $Metadata.AppVersion
        $versionChanged = $existingApp.displayVersion -ne $newVersion

        # Display confirmation information
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Green
        Write-Host "Update existing Intune application" -ForegroundColor Green
        Write-Host "========================================" -ForegroundColor Green
        Write-Host "Display Name: $($existingApp.displayName)" -ForegroundColor White
        Write-Host "Version     : $($existingApp.displayVersion) -> $newVersion" -ForegroundColor White
        Write-Host "Publisher   : $($existingApp.publisher)" -ForegroundColor White
        Write-Host "New Package : $(Split-Path -Path $Paths.intunewinFile -Leaf)" -ForegroundColor White
        Write-Host "========================================`n" -ForegroundColor Green

        if ($versionChanged) {
            Write-Warning ("Detection rules are NOT updated by -AppId. If this app uses a version-based detection rule, " +
                "update it in Intune (or use -Supersede instead), otherwise the new version will fail detection.")
        }

        if (-not $PSCmdlet.ShouldProcess("$($existingApp.displayName) ($AppId)", 'Replace package content')) {
            Write-Host "Update cancelled." -ForegroundColor Yellow
            return
        }

        Write-Host "Uploading new package to Intune..." -ForegroundColor Cyan
        Update-IntuneWin32AppPackageFile -ID $AppId -FilePath $Paths.intunewinFile -Verbose

        if ($versionChanged) {
            Write-Host "Setting app version to $newVersion..." -ForegroundColor Cyan
            Set-IntuneWin32App -ID $AppId -AppVersion $newVersion -Confirm:$false | Out-Null
        }

        Write-Host "`nSuccessfully updated application with new package!" -ForegroundColor Green
        Write-Host "Application ID: $AppId" -ForegroundColor Green
        Write-Host "New package filename: $(Split-Path -Path $Paths.intunewinFile -Leaf)" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to update application: $_"
        throw
    }
}
