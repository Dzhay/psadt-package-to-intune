function Get-PSADTAppInfo {
    <#
    .SYNOPSIS
        Reads AppName, AppVersion, AppVendor and RequireAdmin from a PSADT v4 Invoke-AppDeployToolkit.ps1.
    .DESCRIPTION
        Matches the `$adtSession` hashtable entries (e.g. `AppName = 'Foo'`). Only lines
        that start with the key are matched, so commented-out lines are ignored.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$ScriptPath
    )

    $scriptContent = Get-Content -LiteralPath $ScriptPath -Raw

    if ($scriptContent -match "(?m)^\s*AppName\s*=\s*['""]([^'""]+)['""]") {
        $AppName = $Matches[1]
    }
    else {
        throw "Could not extract AppName from '$ScriptPath'. Ensure the script contains: AppName = 'YourAppName'"
    }

    if ($scriptContent -match "(?m)^\s*AppVersion\s*=\s*['""]([^'""]+)['""]") {
        $AppVersion = $Matches[1]
    }
    else {
        throw "Could not extract AppVersion from '$ScriptPath'. Ensure the script contains: AppVersion = 'x.x.x'"
    }

    $AppVendor = $null
    if ($scriptContent -match "(?m)^\s*AppVendor\s*=\s*['""]([^'""]*)['""]") {
        $AppVendor = $Matches[1]
    }
    if (-not $AppVendor) {
        $AppVendor = 'Unknown'
    }

    if ($scriptContent -match "(?m)^\s*RequireAdmin\s*=\s*\`$([a-zA-Z]+)") {
        $RequireAdmin = $Matches[1] -eq 'true'
    }
    else {
        Write-Warning "Could not extract RequireAdmin from script. Defaulting to system context."
        $RequireAdmin = $true
    }

    [PSCustomObject]@{
        AppName      = $AppName
        AppVersion   = $AppVersion
        AppVendor    = $AppVendor
        RequireAdmin = $RequireAdmin
        Context      = if ($RequireAdmin) { 'system' } else { 'user' }
    }
}
