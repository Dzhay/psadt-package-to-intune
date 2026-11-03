function Invoke-IntuneUpload {
    <#
    .SYNOPSIS
        Builds the Win32 app definition and creates it in Intune.
    .DESCRIPTION
        Description: PackageInfo.json Description (PSADT-Packager) when not empty, else
        "<Vendor> <App> <Version>". Icon order: <PSADTDirectory>\AppIcon.png, the icon
        extracted from the selected executable (temporary file, removed afterwards, also
        on -WhatIf, when declined and on errors), then <PSADTDirectory>\Assets\AppIcon.png.
    .OUTPUTS
        The created app object, or nothing if the upload was declined / -WhatIf.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)][hashtable]$Paths,
        [Parameter(Mandatory)][pscustomobject]$Config,
        [Parameter(Mandatory)][pscustomobject]$Metadata
    )

    $Params = $Config.Params
    $Description = "$($Metadata.AppVendor) $($Metadata.AppName) $($Metadata.AppVersion)"
    $tempIconFolder = $null

    try {
        # Requirements
        $RequirementRule = New-IntuneWin32AppRequirementRule -Architecture $Params.Architecture -MinimumSupportedWindowsRelease $Params.MinimumWindowsRelease

        # Detection (also yields the icon extracted from the selected executable, if any)
        $Detection = Select-AppDetectionRule -RequireAdmin $Metadata.RequireAdmin -Context $Metadata.Context -Paths $Paths
        $DetectionRuleArray = @($Detection.DetectionRules)
        $ExtractedIcon = $Detection.IconPath
        if ($ExtractedIcon) { $tempIconFolder = Split-Path -Path $ExtractedIcon -Parent }

        # Store description from PackageInfo.json (a bad file was already warned about by the detection step)
        $packageInfo = Get-PackageInfo -PackageDirectory $Paths.PSADTDirectory -WarningAction SilentlyContinue
        if ($packageInfo -and $packageInfo.Description -is [string] -and -not [string]::IsNullOrWhiteSpace($packageInfo.Description)) {
            $Description = $packageInfo.Description
        }

        # Notes eq PSADT folder name
        $Notes = Split-Path -Path $Paths.PSADTDirectory -Leaf

        ### Params for Add-IntuneWin32App
        $IntuneAppParams = [ordered]@{
            'FilePath'                = $Paths.intunewinFile
            'DisplayName'             = $Metadata.AppName
            'Description'             = $Description
            'AppVersion'              = $Metadata.AppVersion
            'Publisher'               = $Metadata.AppVendor
            'InstallCommandLine'      = $Params.InstallCommandLine
            'UninstallCommandLine'    = $Params.UninstallCommandLine
            'AllowAvailableUninstall' = $true
            'InstallExperience'       = $Metadata.Context
            'RestartBehavior'         = 'basedOnReturnCode'
            'RequirementRule'         = $RequirementRule
            'DetectionRule'           = $DetectionRuleArray
            'ScopeTagName'            = @($Params.ScopeTagNameArray)
            'Notes'                   = $Notes
        }

        # App icon: the package's AppIcon.png, else the one extracted from the selected executable,
        # else the PSADT default icon
        $iconCandidates = @(
            (Join-Path $Paths.PSADTDirectory 'AppIcon.png')
            $ExtractedIcon
            (Join-Path $Paths.PSADTDirectory 'Assets\AppIcon.png')
        )
        $AppIconFile = $iconCandidates | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -First 1
        if ($AppIconFile) {
            $IntuneAppParams['Icon'] = New-IntuneWin32AppIcon -FilePath $AppIconFile
        }
        # Package owner
        if ($Params.Owner) {
            $IntuneAppParams['Owner'] = $Params.Owner
        }

        # Log everything except the (large, base64) icon; show the icon file used instead
        $ParamsForLog = [ordered]@{}
        foreach ($key in $IntuneAppParams.Keys) {
            if ($key -ne 'Icon') { $ParamsForLog[$key] = $IntuneAppParams[$key] }
        }
        if ($AppIconFile) { $ParamsForLog['Icon'] = $AppIconFile }
        Write-Host "Importing application into Intune with the following parameters:`n$($ParamsForLog | ConvertTo-Json -Depth 5)`n" -ForegroundColor Green

        if (-not $PSCmdlet.ShouldProcess("$($Metadata.AppName) $($Metadata.AppVersion)", 'Create Win32 app in Intune')) {
            Write-Warning "Upload to Intune skipped."
            return
        }

        Connect-IntuneSession -Config $Config
        $AppRequest = Add-IntuneWin32App @IntuneAppParams -Verbose
        $AppRequest | Select-Object * -ExcludeProperty largeIcon | Out-Host

        # Add to AAD group if specified in config
        if ($Params.AADGroupId) {
            Add-IntuneWin32AppAssignmentGroup -ID $AppRequest.Id -GroupId $Params.AADGroupId -Include -Intent available -Notification hideAll -DeliveryOptimizationPriority foreground
            Get-IntuneWin32AppAssignment -ID $AppRequest.Id | Out-Host
        }

        return $AppRequest
    }
    finally {
        # The extracted icon lives in its own temp folder created by Select-AppDetectionRule
        if ($tempIconFolder -and (Split-Path -Path $tempIconFolder -Leaf) -like 'PSADTIntune_*') {
            Remove-Item -LiteralPath $tempIconFolder -Recurse -Force -ErrorAction SilentlyContinue -WhatIf:$false -Confirm:$false
        }
    }
}
