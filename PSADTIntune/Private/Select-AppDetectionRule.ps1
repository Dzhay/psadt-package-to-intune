function Select-AppDetectionRule {
    <#
    .SYNOPSIS
        Builds Intune detection rules from MSI product codes in the package and recent
        Start Menu shortcuts on this machine, letting the user pick them in a grid.
    .DESCRIPTION
        File-based candidates come from the 15 most recently modified Start Menu shortcuts
        on the packaging machine, so the app should be installed locally first. Every row
        has a Source column: 'MSI' (Files\), 'Start Menu' or 'Packager (tested)'. The packager
        row is 'Packager (stale)' with a warning when the script's SHA-256 differs from
        PackageInfo.json's ScriptHash (the script was edited after the test), and
        'Packager (not verified)' when Tests.Verified is false.

        When PackageInfo.json (written by PSADT-Packager) has a Detection entry, it is the
        first row. It stays valid when the file does not exist on this machine, because the
        packager tested it and the app may have been uninstalled since. Later MSI and
        shortcut rows that duplicate it are dropped.

        Icon: when <PSADTDirectory>\AppIcon.png exists, nothing is extracted. Otherwise the
        icon of the first selected existing file is extracted into a new temporary folder
        (PSADTIntune_<guid> under the temp path), never into the working directory. The
        caller removes that folder.

        If nothing is selected, a PLACEHOLDER rule is returned that must be fixed in Intune.
    .OUTPUTS
        [pscustomobject] with DetectionRules (list of rule objects) and IconPath (the
        extracted PNG in the temporary folder, or $null).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)][bool]$RequireAdmin,
        [Parameter(Mandatory)][string]$Context,
        [Parameter(Mandatory)][hashtable]$Paths
    )

    $PossibleDetections = [System.Collections.Generic.List[object]]::new()

    # Tested detection from the packager is the first row
    $packageInfo = Get-PackageInfo -PackageDirectory $Paths.PSADTDirectory
    $packagerDetection = $null
    if ($packageInfo -and $packageInfo.Detection) {
        $d = $packageInfo.Detection
        # The packager stores the script's SHA-256; a different hash means the script was edited after the test
        $packagerSource = 'Packager (tested)'
        $scriptPath = Join-Path -Path $Paths.PSADTDirectory -ChildPath 'Invoke-AppDeployToolkit.ps1'
        if ($packageInfo.ScriptHash -and (Test-Path -LiteralPath $scriptPath -PathType Leaf) -and
            (Get-FileHash -LiteralPath $scriptPath -Algorithm SHA256).Hash -ne [string]$packageInfo.ScriptHash) {
            $packagerSource = 'Packager (stale)'
            Write-Warning 'Invoke-AppDeployToolkit.ps1 changed after PackageInfo.json was written: check the Packager detection row, or retest with Test-PSADTPackage first.'
        }
        elseif ($packageInfo.Tests -and $packageInfo.Tests.Verified -eq $false) {
            $packagerSource = 'Packager (not verified)'
            Write-Warning 'PackageInfo.json says the package is not verified: check the Packager detection row.'
        }
        if ($d.Type -eq 'File' -and $d.File) {
            $packagerDetection = [PSCustomObject]@{
                'Type'         = 'File'
                'Source'       = $packagerSource
                'Property'     = [string]$d.File
                'VersionValue' = if ($d.Version) { [string]$d.Version } else { $null }
                'Path'         = [string]$d.Path
            }
        }
        elseif ($d.Type -eq 'MSI' -and $d.ProductCode) {
            $packagerDetection = [PSCustomObject]@{
                'Type'         = 'MSI'
                'Source'       = $packagerSource
                'Property'     = ([string]$d.ProductCode).Trim()
                'VersionValue' = $null
                'Path'         = $null
            }
        }
        else {
            Write-Warning "Ignoring unsupported or incomplete Detection in PackageInfo.json (Type '$($d.Type)')."
        }
    }
    if ($packagerDetection) {
        $PossibleDetections.Add($packagerDetection)
    }

    # Same rule as the packager row: MSI by product code, File by folder and file name
    function Test-DuplicateOfPackager {
        param($Candidate)
        if (-not $packagerDetection -or $Candidate.Type -ne $packagerDetection.Type) { return $false }
        if ($Candidate.Type -eq 'MSI') {
            return $Candidate.Property -eq $packagerDetection.Property
        }
        $candidateFull = Join-Path ([string]$Candidate.Path).TrimEnd('\') $Candidate.Property
        $packagerFull = Join-Path ([string]$packagerDetection.Path).TrimEnd('\') $packagerDetection.Property
        return $candidateFull -eq $packagerFull
    }

    # MSI detection
    $MSIPaths = Get-ChildItem -LiteralPath (Join-Path $Paths.PSADTDirectory 'Files') -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -eq '.msi' }
    foreach ($MSIPath in $MSIPaths) {
        $Property = ([string](Get-MSIMetaData -Path $MSIPath.FullName -Property ProductCode)).Trim()
        $candidate = [PSCustomObject]@{
            'Type'         = 'MSI'
            'Source'       = 'MSI'
            'Property'     = $Property
            'VersionValue' = $null
            'Path'         = $MSIPath.FullName
        }
        if (-not (Test-DuplicateOfPackager -Candidate $candidate)) {
            $PossibleDetections.Add($candidate)
        }
    }

    # File detection via shortcuts
    if ($RequireAdmin) {
        $ShortcutSearchPath = Join-Path -Path $env:ProgramData -ChildPath 'Microsoft\Windows\Start Menu'
    }
    else {
        $ShortcutSearchPath = Join-Path -Path $env:APPDATA -ChildPath 'Microsoft\Windows\Start Menu\Programs'
    }
    $ShortcutPaths = Get-ChildItem -LiteralPath $ShortcutSearchPath -Filter '*.lnk' -Recurse -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 15

    # Targets under %WINDIR% are never app files: advertised MSI shortcuts resolve to icon stubs in
    # %WINDIR%\Installer, and "Uninstall"/console shortcuts point at msiexec.exe or cmd.exe
    $WindowsPath = $env:windir.TrimEnd('\') + '\'
    $seenTargets = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    $shell = New-Object -ComObject WScript.Shell
    try {
        foreach ($ShortcutPath in $ShortcutPaths) {
            $AppPath = $shell.CreateShortcut($ShortcutPath.FullName).TargetPath
            # Shell-item shortcuts (UWP apps, Control Panel items) have no file target
            if ([string]::IsNullOrWhiteSpace($AppPath)) {
                Write-Verbose "Skipping shortcut without a file target: $($ShortcutPath.FullName)"
                continue
            }
            if ($AppPath.StartsWith($WindowsPath, [System.StringComparison]::OrdinalIgnoreCase)) {
                Write-Verbose "Skipping shortcut to a Windows system file: $($ShortcutPath.FullName) -> $AppPath"
                continue
            }
            if (-not $seenTargets.Add($AppPath)) {
                continue
            }
            if (-not (Test-Path -LiteralPath $AppPath -PathType Leaf)) {
                Write-Warning "Skipping invalid shortcut path: $AppPath"
                continue
            }
            $Name = Split-Path -Path $AppPath -Leaf
            $VersionInfo = (Get-Item -LiteralPath $AppPath).VersionInfo
            $Version = "$($VersionInfo.FileMajorPart).$($VersionInfo.FileMinorPart).$($VersionInfo.FileBuildPart).$($VersionInfo.FilePrivatePart)"
            # Files without version info report 0.0.0.0 - use an Exists rule instead
            if ($Version -notmatch '^\d+(\.\d+)+$' -or $Version -eq '0.0.0.0') {
                $Version = $null
            }
            $candidate = [PSCustomObject]@{
                'Type'         = 'File'
                'Source'       = 'Start Menu'
                'Property'     = $Name
                'VersionValue' = $Version
                'Path'         = Split-Path -Path $AppPath -Parent
            }
            if (-not (Test-DuplicateOfPackager -Candidate $candidate)) {
                $PossibleDetections.Add($candidate)
            }
        }
    }
    finally {
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) | Out-Null
        $shell = $null
    }

    # User selection
    $selected = @($PossibleDetections | Out-ConsoleGridView -Title 'Select detection rule(s)')

    $DetectionRules = [System.Collections.ArrayList]::new()

    # No selection made - warn and add placeholder
    if ($selected.Count -eq 0) {
        Write-Warning "No detection rule selected. Adding placeholder rule - you MUST update this in Intune before deploying."
        $DetectionRule = New-IntuneWin32AppDetectionRuleFile -Path 'C:\Program Files\PLACEHOLDER' -FileOrFolder 'PLACEHOLDER.exe' -DetectionType Exists -Existence -Check32BitOn64System $false
        $DetectionRules.Add($DetectionRule) | Out-Null
        return [PSCustomObject]@{ DetectionRules = $DetectionRules; IconPath = $null }
    }

    # Multiple MSI selected - error
    if (@($selected | Where-Object { $_.Type -eq 'MSI' }).Count -gt 1) {
        throw "Multiple MSI detection rules selected. Please select only one MSI detection rule."
    }

    # A package-supplied AppIcon.png wins, so nothing is extracted
    $iconNeeded = -not (Test-Path -LiteralPath (Join-Path $Paths.PSADTDirectory 'AppIcon.png') -PathType Leaf)
    $iconPath = $null
    $iconDone = $false
    $iconFolder = $null
    $completed = $false
    try {
        foreach ($item in $selected) {
            if ($item.Type -eq 'MSI') {
                $DetectionRule = New-IntuneWin32AppDetectionRuleMSI -ProductCode $item.Property
            }
            elseif ($item.Type -eq 'File') {
                # Use the first selected existing executable's icon as the app icon
                $itemFile = Join-Path $item.Path $item.Property
                if ($iconNeeded -and -not $iconDone -and (Test-Path -LiteralPath $itemFile -PathType Leaf)) {
                    try {
                        if (-not $iconFolder) {
                            $iconFolder = Join-Path ([System.IO.Path]::GetTempPath()) "PSADTIntune_$([guid]::NewGuid())"
                            New-Item -ItemType Directory -Path $iconFolder -Force | Out-Null
                        }
                        Export-AppIcon -Path $itemFile -Destination $iconFolder -Name 'AppIcon' -Format 'png' | Out-Null
                        $iconDone = $true
                        $extracted = Join-Path $iconFolder 'AppIcon.png'
                        if (Test-Path -LiteralPath $extracted -PathType Leaf) { $iconPath = $extracted }
                    }
                    catch {
                        Write-Warning "Could not extract icon from '$($item.Property)': $_"
                    }
                }
                # Replace dynamic username with %username%
                if ($Context -eq 'user') {
                    $item.Path = $item.Path -replace '(?<=^[A-Z]:\\Users\\)[^\\]+', '%username%'
                }
                $DetectionParams = @{
                    Path                 = $item.Path
                    FileOrFolder         = $item.Property
                    Check32BitOn64System = $false
                }
                if ($null -ne $item.VersionValue) {
                    $DetectionParams['Version'] = $true
                    $DetectionParams['Operator'] = 'Equal'
                    $DetectionParams['VersionValue'] = $item.VersionValue
                }
                else {
                    $DetectionParams['DetectionType'] = 'Exists'
                    $DetectionParams['Existence'] = $true
                }
                $DetectionRule = New-IntuneWin32AppDetectionRuleFile @DetectionParams
            }
            $DetectionRules.Add($DetectionRule) | Out-Null
        }
        $completed = $true
    }
    finally {
        # Nothing extracted, or the run failed: do not leave the temp folder behind
        if ($iconFolder -and (-not $iconPath -or -not $completed)) {
            Remove-Item -LiteralPath $iconFolder -Recurse -Force -ErrorAction SilentlyContinue -WhatIf:$false -Confirm:$false
        }
    }

    return [PSCustomObject]@{ DetectionRules = $DetectionRules; IconPath = $iconPath }
}
