function Connect-IntuneSession {
    <#
    .SYNOPSIS
        Connects to Microsoft Graph for Intune using the configured tenant and app registration.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Config
    )

    Write-Host "`nConnecting to Microsoft Intune Graph..." -ForegroundColor Cyan
    Connect-MSIntuneGraph -TenantID $Config.TenantId -ClientID $Config.AADClientId -Verbose | Out-Null
}
