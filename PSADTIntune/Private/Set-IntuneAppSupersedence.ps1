function Set-IntuneAppSupersedence {
    <#
    .SYNOPSIS
        Applies supersedence, name/description inheritance, and group exclusions
        from an old app to a newly created app.
    .DESCRIPTION
        Called after Invoke-IntuneUpload when -Supersede is used. Inherits
        DisplayName and Description from the old app, configures Update supersedence
        so the new app supersedes the old one, and copies all group assignments from
        the old app as exclusions (preserving intent). The config AADGroupId is
        skipped here to avoid an include/exclude conflict with the group already
        added by Invoke-IntuneUpload.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)][string]$NewAppId,
        [Parameter(Mandatory)][string]$OldAppId,
        [Parameter(Mandatory)][pscustomobject]$Config
    )

    Write-Host "`nConfiguring supersedence..." -ForegroundColor Cyan

    # Fetch old app metadata
    $oldApp = Get-IntuneWin32App -ID $OldAppId -ErrorAction Stop
    if ($null -eq $oldApp) {
        throw "No application found with supersede ID: $OldAppId"
    }

    if (-not $PSCmdlet.ShouldProcess($NewAppId, "Supersede '$($oldApp.displayName)' ($OldAppId)")) {
        return
    }

    # Inherit display name and description from the old app
    Write-Host "Inheriting name '$($oldApp.displayName)' from app '$OldAppId'..." -ForegroundColor Cyan
    Set-IntuneWin32App -ID $NewAppId -DisplayName $oldApp.displayName -Description $oldApp.description -Confirm:$false | Out-Null

    # Configure supersedence (Update = upgrade in place, keeps old install path)
    Write-Host "Adding supersedence (Update) over '$($oldApp.displayName)'..." -ForegroundColor Cyan
    $SupersedenceObject = New-IntuneWin32AppSupersedence -ID $OldAppId -SupersedenceType 'Update'
    Add-IntuneWin32AppSupersedence -ID $NewAppId -Supersedence $SupersedenceObject | Out-Null

    # Copy old app's group assignments as exclusions for safe testing
    Write-Host "Copying group assignments from old app as exclusions..." -ForegroundColor Cyan
    $OldAssignments = Get-IntuneWin32AppAssignment -ID $OldAppId
    $ExcludeCount = 0
    foreach ($assignment in $OldAssignments) {
        # All Users / All Devices have no GroupID - cannot be added as exclusions
        if ([string]::IsNullOrEmpty($assignment.GroupID)) {
            Write-Warning "Skipping All Users / All Devices assignment (intent: $($assignment.Intent)) - not supported as exclusion."
            continue
        }
        # Skip the config group to avoid an include/exclude conflict (it was already added as Include)
        if ($assignment.GroupID -eq $Config.Params.AADGroupId) {
            Write-Warning "Skipping config AADGroupId '$($assignment.GroupID)' to avoid include/exclude conflict."
            continue
        }
        Add-IntuneWin32AppAssignmentGroup -Exclude -ID $NewAppId -GroupID $assignment.GroupID -Intent $assignment.Intent | Out-Null
        Write-Host "  Excluded group '$($assignment.GroupName)' ($($assignment.GroupID)) [intent: $($assignment.Intent)]" -ForegroundColor Yellow
        $ExcludeCount++
    }

    Write-Host "`nSupersedence configured successfully." -ForegroundColor Green
    Write-Host "  Old app        : $($oldApp.displayName) ($OldAppId)" -ForegroundColor Green
    Write-Host "  Groups excluded: $ExcludeCount" -ForegroundColor Green
}
