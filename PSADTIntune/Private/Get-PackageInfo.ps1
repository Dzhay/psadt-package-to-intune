function Get-PackageInfo {
    <#
    .SYNOPSIS
        Reads PackageInfo.json from a PSADT package folder.
    .DESCRIPTION
        PackageInfo.json is optionally written by the PSADT-Packager module next to
        Invoke-AppDeployToolkit.ps1. It carries the tested detection rule, the store
        description and more. Any key may be missing.
    .OUTPUTS
        The parsed object, or $null when the file is missing (silent) or is not valid
        JSON (with a warning naming the file).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PackageDirectory
    )

    $infoPath = Join-Path -Path $PackageDirectory -ChildPath 'PackageInfo.json'
    if (-not (Test-Path -LiteralPath $infoPath -PathType Leaf)) {
        return $null
    }

    try {
        $info = Get-Content -LiteralPath $infoPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Write-Warning "Could not read '$infoPath' (ignored): $($_.Exception.Message)"
        return $null
    }
    if ($info -isnot [pscustomobject]) {
        Write-Warning "Could not read '$infoPath' (ignored): the content is not a JSON object."
        return $null
    }
    $info
}
