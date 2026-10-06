function Select-AppDetectionRule {
    <#
    .SYNOPSIS
        Builds Intune detection rules from MSI product codes in the package and recent
        Start Menu shortcuts on this machine, letting the user pick them in a grid.
    .DESCRIPTION
        File-based candidates come from the 15 most recently modified Start Menu shortcuts
        on the packaging machine, so the app should be installed locally first. The icon of
        the first selected file is saved as AppIcon.png in the working directory.
        If nothing is selected, a PLACEHOLDER rule is returned that must be fixed in Intune.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)][bool]$RequireAdmin,
        [Parameter(Mandatory)][string]$Context,
        [Parameter(Mandatory)][hashtable]$Paths
    )

    $PossibleDetections = [System.Collections.Generic.List[object]]::new()

    # MSI detection
    $MSIPaths = Get-ChildItem -LiteralPath (Join-Path $Paths.PSADTDirectory 'Files') -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -eq '.msi' }
    foreach ($MSIPath in $MSIPaths) {
        $Property = ([string](Get-MSIMetaData -Path $MSIPath.FullName -Property ProductCode)).Trim()
        $PossibleDetections.Add([PSCustomObject]@{
                'Type'         = 'MSI'
                'Property'     = $Property
                'VersionValue' = $null
                'Path'         = $MSIPath.FullName
            })
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
            $PossibleDetections.Add([PSCustomObject]@{
                    'Type'         = 'File'
                    'Property'     = $Name
                    'VersionValue' = $Version
                    'Path'         = Split-Path -Path $AppPath -Parent
                })
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
        return $DetectionRules
    }

    # Multiple MSI selected - error
    if (@($selected | Where-Object { $_.Type -eq 'MSI' }).Count -gt 1) {
        throw "Multiple MSI detection rules selected. Please select only one MSI detection rule."
    }

    $iconExtracted = $false
    foreach ($item in $selected) {
        if ($item.Type -eq 'MSI') {
            $DetectionRule = New-IntuneWin32AppDetectionRuleMSI -ProductCode $item.Property
        }
        elseif ($item.Type -eq 'File') {
            # Use the first selected executable's icon as the app icon
            if (-not $iconExtracted) {
                try {
                    Export-AppIcon -Path (Join-Path $item.Path $item.Property) -Destination $Paths.WorkingDirectory -Name 'AppIcon' -Format 'png' | Out-Null
                    $iconExtracted = $true
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

    return $DetectionRules
}
