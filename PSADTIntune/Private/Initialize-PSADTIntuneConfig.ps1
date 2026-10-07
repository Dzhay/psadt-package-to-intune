function Initialize-PSADTIntuneConfig {
    <#
    .SYNOPSIS
        Offers first-run setup when the config file or its TenantId/AADClientId is missing.
    .DESCRIPTION
        In an interactive session, asks whether to enter TenantId and ClientId now
        (Set-PSADTIntuneConfig prompts) or to open the config file in an editor.
        Returns $false when the run should stop (editor opened or setup cancelled),
        otherwise $true. When nobody can answer (Read-Host throws or input is closed)
        it returns $true and leaves it to Import-PSADTIntuneConfig to fail with setup
        instructions.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [string]$ConfigPath
    )

    $location = Resolve-PSADTIntuneConfigPath -ConfigPath $ConfigPath
    if ($location.Exists) {
        $config = Import-PSADTIntuneConfig -ConfigPath $location.Path
        $missing = @('TenantId', 'AADClientId') | Where-Object { -not (Test-PSADTIntuneConfigValue -Value $config.$_) }
        if (-not $missing) { return $true }
        $problem = "Config '$($location.Path)' is missing: $($missing -join ', ')."
    }
    else {
        $problem = "No PSADTIntune config found at '$($location.Path)'."
    }

    Write-Host $problem -ForegroundColor Yellow
    Write-Host "  [Y] Set up now: enter TenantId and ClientId (default)"
    Write-Host "  [E] Open the config file in an editor"
    Write-Host "  [N] Cancel"
    try { $response = Read-Host "Set up the config? [Y/e/n]" }
    catch { return $true }                       # -NonInteractive: Import-PSADTIntuneConfig throws the setup instructions
    if ($null -eq $response) { return $true }    # Input closed (CI, scheduled task): same
    $response = $response.Trim()

    if ($response -match '^[Ee]') {
        Open-PSADTIntuneConfigFile -Path $location.Path
        Write-Host "Save the file, then run packageIntune again." -ForegroundColor Yellow
        return $false
    }
    if ($response -match '^[Nn]') {
        Write-Host "Cancelled. Set up later with Set-PSADTIntuneConfig or packageIntune -Config." -ForegroundColor Yellow
        return $false
    }

    # The user just asked for this, so do not gate it behind -WhatIf / -Confirm of the upload
    Set-PSADTIntuneConfig -ConfigPath $location.Path -WhatIf:$false -Confirm:$false
    return $true
}
