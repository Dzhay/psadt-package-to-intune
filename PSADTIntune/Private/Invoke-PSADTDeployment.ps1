function Invoke-PSADTDeployment {
    <#
    .SYNOPSIS
        Installs or uninstalls the PSADT package on this computer.
    .DESCRIPTION
        Runs the configured InstallCommandLine / UninstallCommandLine in the PSADT package
        folder, the same command and folder Intune uses. A program name without a path is
        taken from the package folder when it exists there (e.g. Invoke-AppDeployToolkit.exe),
        otherwise it is started as given (e.g. powershell.exe from PATH).

        Packages with RequireAdmin = $true are started elevated through a UAC prompt when
        the session is not elevated. Exit codes 0, 1641 and 3010 count as success.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Install', 'Uninstall')]
        [string]$DeploymentType,

        [Parameter(Mandatory)]
        [string]$PSADTDirectory,

        [Parameter(Mandatory)]
        [string]$CommandLine,

        [Parameter(Mandatory)]
        [pscustomobject]$Metadata
    )

    # Split into program and arguments; the program may be quoted
    if ($CommandLine -notmatch '^\s*(?:"(?<file>[^"]+)"|(?<file>\S+))\s*(?<arguments>.*)$') {
        throw "Could not read the $DeploymentType command line '$CommandLine'. Check it with Get-PSADTIntuneConfig."
    }
    $file = $Matches['file']
    $arguments = $Matches['arguments'].Trim()

    if (-not [System.IO.Path]::IsPathRooted($file)) {
        $packageFile = Join-Path -Path $PSADTDirectory -ChildPath $file
        if (Test-Path -LiteralPath $packageFile -PathType Leaf) {
            $file = $packageFile
        }
    }

    $target = "$($Metadata.AppName) $($Metadata.AppVersion)"
    if (-not $PSCmdlet.ShouldProcess($target, "$DeploymentType on this computer")) {
        return
    }

    $startParams = @{
        FilePath         = $file
        WorkingDirectory = $PSADTDirectory
        Wait             = $true
        PassThru         = $true
    }
    if ($arguments) {
        $startParams['ArgumentList'] = $arguments
    }

    Write-Host "`n$($DeploymentType): $target" -ForegroundColor Cyan
    Write-Host "  Command: $CommandLine"
    Write-Host "  Folder : $PSADTDirectory"
    if ($Metadata.RequireAdmin -and -not (Test-IsElevated)) {
        $startParams['Verb'] = 'RunAs'
        Write-Host "  The package requires admin rights - confirm the UAC prompt." -ForegroundColor Yellow
    }

    $process = Start-Process @startParams
    $exitCode = $process.ExitCode

    if ($exitCode -eq 0) {
        Write-Host "$DeploymentType finished successfully (exit code 0)." -ForegroundColor Green
    }
    elseif ($exitCode -in 1641, 3010) {
        Write-Host "$DeploymentType finished successfully (exit code $exitCode)." -ForegroundColor Green
        Write-Warning "A restart is required to complete the $($DeploymentType.ToLower())."
    }
    else {
        throw "$DeploymentType of $target failed with exit code $exitCode. Check the PSADT log for details."
    }
}
