BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Import-Module $ModuleManifest -Force
}

Describe 'Select-AppDetectionRule' {
    BeforeAll {
        $originalProgramData = $env:ProgramData
        $originalAppData = $env:APPDATA

        # A fake machine under TestDrive: all-users and per-user Start Menus with real .lnk files
        $root = Join-Path $TestDrive 'machine'
        $env:ProgramData = Join-Path $root 'ProgramData'
        $env:APPDATA = Join-Path $root 'Profile\AppData\Roaming'
        $allUsersStartMenu = Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs'
        $userStartMenu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
        $appDirectory = Join-Path $root 'Programs\Contoso'
        $userAppDirectory = Join-Path $root 'Profile\AppData\Local\Programs\UserApp'
        New-Item -ItemType Directory -Path $allUsersStartMenu, $userStartMenu, $appDirectory, $userAppDirectory -Force | Out-Null

        $versionedExe = Join-Path $appDirectory 'Contoso.exe'
        Copy-Item -LiteralPath (Join-Path $env:windir 'System32\notepad.exe') -Destination $versionedExe
        $expectedVersion = (Get-Item -LiteralPath $versionedExe).VersionInfo |
            ForEach-Object { '{0}.{1}.{2}.{3}' -f $_.FileMajorPart, $_.FileMinorPart, $_.FileBuildPart, $_.FilePrivatePart }
        $unversionedExe = Join-Path $appDirectory 'Helper.exe'
        Set-Content -LiteralPath $unversionedExe -Value 'no version info'
        $userExe = Join-Path $userAppDirectory 'UserApp.exe'
        Copy-Item -LiteralPath $versionedExe -Destination $userExe

        $shell = New-Object -ComObject WScript.Shell
        try {
            $shortcuts = @(
                @{ Folder = $allUsersStartMenu; Name = 'Contoso'; Target = $versionedExe }
                @{ Folder = $allUsersStartMenu; Name = 'Contoso (second shortcut)'; Target = $versionedExe }
                @{ Folder = $allUsersStartMenu; Name = 'Contoso Helper'; Target = $unversionedExe }
                @{ Folder = $allUsersStartMenu; Name = 'Uninstall Contoso'; Target = (Join-Path $env:windir 'System32\msiexec.exe') }
                @{ Folder = $allUsersStartMenu; Name = 'Removed App'; Target = (Join-Path $appDirectory 'Removed.exe') }
                @{ Folder = $userStartMenu; Name = 'User App'; Target = $userExe }
            )
            foreach ($shortcut in $shortcuts) {
                $link = $shell.CreateShortcut((Join-Path $shortcut.Folder "$($shortcut.Name).lnk"))
                $link.TargetPath = $shortcut.Target
                $link.Save()
            }
        }
        finally {
            [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell)
        }

        # PSADT package with MSIs; product codes come from the mocked Get-MSIMetaData
        $packageDirectory = Join-Path $root 'Package'
        New-Item -ItemType Directory -Path (Join-Path $packageDirectory 'Files\Addon') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $packageDirectory 'Files\Contoso.msi') -Value 'msi'
        Set-Content -LiteralPath (Join-Path $packageDirectory 'Files\Addon\Contoso.Addon.msi') -Value 'msi'
        Set-Content -LiteralPath (Join-Path $packageDirectory 'Files\Contoso.msix') -Value 'msix'
        $mainProductCode = '{AAAAAAAA-1111-2222-3333-444444444444}'
        $addonProductCode = '{BBBBBBBB-1111-2222-3333-444444444444}'

        $workingDirectory = Join-Path $root 'Work'
        New-Item -ItemType Directory -Path $workingDirectory -Force | Out-Null
        $paths = @{ PSADTDirectory = $packageDirectory; WorkingDirectory = $workingDirectory }

        Mock Write-Warning -ModuleName PSADTIntune {}
        Mock Get-MSIMetaData -ModuleName PSADTIntune {
            if ($Path -like '*Addon*') { $addonProductCode } else { $mainProductCode }
        }
        # Records every candidate shown in the grid and returns the ones listed in $script:SelectProperties.
        # Pester runs the mock once per pipeline item, with the item in $InputObject.
        Mock Out-ConsoleGridView -ModuleName PSADTIntune {
            if ($null -ne $InputObject) {
                $script:GridCandidates += $InputObject
                if ($InputObject.Property -in $script:SelectProperties) { $InputObject }
            }
        }

        function Invoke-Selection {
            param(
                [string[]]$Select = @(),
                [bool]$RequireAdmin = $true
            )
            $script:GridCandidates = @()
            $script:SelectProperties = $Select
            $context = if ($RequireAdmin) { 'system' } else { 'user' }
            InModuleScope PSADTIntune -Parameters @{ RequireAdmin = $RequireAdmin; Context = $context; Paths = $paths } {
                param($RequireAdmin, $Context, $Paths)
                (Select-AppDetectionRule -RequireAdmin $RequireAdmin -Context $Context -Paths $Paths).DetectionRules
            }
        }

        # Same for a system install, but returns the whole result (DetectionRules and IconPath)
        function Invoke-SelectionResult {
            param([string[]]$Select = @())
            $script:GridCandidates = @()
            $script:SelectProperties = $Select
            InModuleScope PSADTIntune -Parameters @{ Paths = $paths } {
                param($Paths)
                Select-AppDetectionRule -RequireAdmin $true -Context 'system' -Paths $Paths
            }
        }
    }

    AfterAll {
        $env:ProgramData = $originalProgramData
        $env:APPDATA = $originalAppData
    }

    Context 'candidates shown in the grid' {
        BeforeAll {
            $null = Invoke-Selection
            $candidates = $script:GridCandidates
            $fileCandidates = @($candidates | Where-Object Type -eq 'File')
        }

        It 'lists the product code of every MSI under Files\, including subfolders' {
            (@($candidates | Where-Object Type -eq 'MSI').Property | Sort-Object) -join ',' | Should -Be "$mainProductCode,$addonProductCode"
        }

        It 'ignores .msix files' {
            $candidates.Path | Should -Not -Contain (Join-Path $packageDirectory 'Files\Contoso.msix')
        }

        It 'lists each shortcut target once' {
            @($fileCandidates | Where-Object Property -eq 'Contoso.exe').Count | Should -Be 1
        }

        It 'reads the file version of the target' {
            ($fileCandidates | Where-Object Property -eq 'Contoso.exe').VersionValue | Should -Be $expectedVersion
        }

        It 'lists files without version info without a version' {
            $helper = $fileCandidates | Where-Object Property -eq 'Helper.exe'
            $helper | Should -Not -BeNullOrEmpty
            $helper.VersionValue | Should -BeNullOrEmpty
        }

        It 'skips shortcuts to files in the Windows folder' {
            $fileCandidates.Property | Should -Not -Contain 'msiexec.exe'
        }

        It 'skips shortcuts whose target no longer exists' {
            $fileCandidates.Property | Should -Not -Contain 'Removed.exe'
        }

        It 'uses the all-users Start Menu for system installs' {
            $fileCandidates.Property | Should -Not -Contain 'UserApp.exe'
        }
    }

    Context 'rules for the selected candidates' {
        It 'warns about shortcuts whose target no longer exists' {
            $null = Invoke-Selection

            Should -Invoke Write-Warning -ModuleName PSADTIntune -ParameterFilter { $Message -like '*Removed.exe*' }
        }

        It 'creates a version rule for a file with version info' {
            $rules = @(Invoke-Selection -Select 'Contoso.exe')

            $rules.Count | Should -Be 1
            $rules[0].detectionType | Should -Be 'version'
            $rules[0].operator | Should -Be 'equal'
            $rules[0].detectionValue | Should -Be $expectedVersion
            $rules[0].path | Should -Be $appDirectory
            $rules[0].fileOrFolderName | Should -Be 'Contoso.exe'
        }

        It 'creates an exists rule for a file without version info' {
            $rules = @(Invoke-Selection -Select 'Helper.exe')

            $rules[0].detectionType | Should -Be 'exists'
            $rules[0].fileOrFolderName | Should -Be 'Helper.exe'
        }

        It 'creates a product code rule for an MSI' {
            $rules = @(Invoke-Selection -Select $mainProductCode)

            $rules.Count | Should -Be 1
            $rules[0].productCode | Should -Be $mainProductCode
        }

        It 'returns one rule per selected candidate' {
            $rules = @(Invoke-Selection -Select 'Contoso.exe', $mainProductCode)

            $rules.Count | Should -Be 2
        }

        It 'refuses more than one MSI rule' {
            { Invoke-Selection -Select $mainProductCode, $addonProductCode } | Should -Throw '*only one MSI*'
        }

        It 'adds a placeholder rule with a warning when nothing is selected' {
            $rules = @(Invoke-Selection)

            $rules.Count | Should -Be 1
            $rules[0].path | Should -Be 'C:\Program Files\PLACEHOLDER'
            Should -Invoke Write-Warning -ModuleName PSADTIntune -Times 1 -Exactly -ParameterFilter { $Message -like 'No detection rule selected*' }
        }

        It 'uses the per-user Start Menu and a %username% path for user installs' {
            if ($TestDrive -notmatch '^[A-Za-z]:\\Users\\') {
                Set-ItResult -Skipped -Because "TestDrive '$TestDrive' is not under C:\Users"
                return
            }

            $rules = @(Invoke-Selection -Select 'UserApp.exe' -RequireAdmin $false)

            $script:GridCandidates.Property | Should -Not -Contain 'Contoso.exe'
            $rules.Count | Should -Be 1
            $rules[0].path | Should -Match '^[A-Za-z]:\\Users\\%username%\\'
        }
    }

    Context 'app icon' {
        BeforeEach {
            Remove-Item -LiteralPath (Join-Path $packageDirectory 'AppIcon.png') -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath (Join-Path $workingDirectory 'AppIcon.png') -ErrorAction SilentlyContinue
            $result = $null
        }

        AfterEach {
            # The caller owns the temp folder; remove it here
            if ($result -and $result.IconPath) {
                Remove-Item -LiteralPath (Split-Path $result.IconPath -Parent) -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'extracts the icon of the selected file into a new temp folder, not the working directory' {
            $result = Invoke-SelectionResult -Select 'Contoso.exe'

            $result.IconPath | Should -Exist
            # PNG signature
            ([System.IO.File]::ReadAllBytes($result.IconPath)[0..3] -join ',') | Should -Be '137,80,78,71'
            $folder = Split-Path $result.IconPath -Parent
            (Split-Path $folder -Leaf) | Should -BeLike 'PSADTIntune_*'
            ([System.IO.Path]::GetFullPath($folder) -like ([System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()) + 'PSADTIntune_*')) | Should -BeTrue
            (Join-Path $workingDirectory 'AppIcon.png') | Should -Not -Exist
        }

        It 'does not extract an icon when the package has an AppIcon.png' {
            New-TestPng -Path (Join-Path $packageDirectory 'AppIcon.png') | Out-Null
            Mock Export-AppIcon -ModuleName PSADTIntune {}

            $result = Invoke-SelectionResult -Select 'Contoso.exe'

            Should -Invoke Export-AppIcon -ModuleName PSADTIntune -Times 0 -Exactly
            $result.IconPath | Should -BeNullOrEmpty
            @($result.DetectionRules).Count | Should -Be 1
        }

        It 'returns no icon path when only an MSI is selected' {
            Mock Export-AppIcon -ModuleName PSADTIntune {}

            $result = Invoke-SelectionResult -Select $mainProductCode

            Should -Invoke Export-AppIcon -ModuleName PSADTIntune -Times 0 -Exactly
            $result.IconPath | Should -BeNullOrEmpty
        }

        It 'removes the temp folder again when no icon file is produced' {
            $script:ExportDestination = $null
            Mock Export-AppIcon -ModuleName PSADTIntune { $script:ExportDestination = $Destination }

            $result = Invoke-SelectionResult -Select 'Contoso.exe'

            $result.IconPath | Should -BeNullOrEmpty
            $script:ExportDestination | Should -BeLike '*PSADTIntune_*'
            $script:ExportDestination | Should -Not -Exist
        }

        It 'extracts the icon only once when several files are selected' {
            Mock Export-AppIcon -ModuleName PSADTIntune {}

            $null = Invoke-Selection -Select 'Contoso.exe', 'Helper.exe'

            Should -Invoke Export-AppIcon -ModuleName PSADTIntune -Times 1 -Exactly
        }

        It 'keeps going with a warning when the icon cannot be extracted' {
            Mock Export-AppIcon -ModuleName PSADTIntune { throw 'icon failure' }

            $rules = @(Invoke-Selection -Select 'Contoso.exe')

            $rules.Count | Should -Be 1
            Should -Invoke Write-Warning -ModuleName PSADTIntune -ParameterFilter { $Message -like 'Could not extract icon*' }
        }
    }

    Context 'Source column' {
        It 'labels MSI and Start Menu rows' {
            $null = Invoke-Selection

            @($script:GridCandidates | Where-Object Type -eq 'MSI').Source | Select-Object -Unique | Should -Be 'MSI'
            @($script:GridCandidates | Where-Object Type -eq 'File').Source | Select-Object -Unique | Should -Be 'Start Menu'
        }
    }

    Context 'detection from PackageInfo.json' {
        BeforeAll {
            $infoPath = Join-Path $packageDirectory 'PackageInfo.json'
            function Set-PackageInfo {
                param($Detection)
                @{ SchemaVersion = 1; Detection = $Detection } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $infoPath
            }
        }

        AfterEach {
            Remove-Item -LiteralPath $infoPath -ErrorAction SilentlyContinue
        }

        It 'puts a tested File detection first, valid even when the file does not exist' {
            Set-PackageInfo @{ Type = 'File'; Path = 'C:\Program Files\Gone'; File = 'gone.exe'; Version = '1.2.3.4' }

            $rules = @(Invoke-Selection -Select 'gone.exe')

            $first = $script:GridCandidates[0]
            $first.Source | Should -Be 'Packager (tested)'
            $first.Type | Should -Be 'File'
            $first.Property | Should -Be 'gone.exe'
            $first.VersionValue | Should -Be '1.2.3.4'
            $first.Path | Should -Be 'C:\Program Files\Gone'
            $rules.Count | Should -Be 1
            $rules[0].detectionType | Should -Be 'version'
            $rules[0].detectionValue | Should -Be '1.2.3.4'
            $rules[0].path | Should -Be 'C:\Program Files\Gone'
            $rules[0].fileOrFolderName | Should -Be 'gone.exe'
        }

        It 'creates an exists rule when the tested detection has no version' {
            Set-PackageInfo @{ Type = 'File'; Path = 'C:\Program Files\Gone'; File = 'gone.exe'; Version = $null }

            $rules = @(Invoke-Selection -Select 'gone.exe')

            $rules[0].detectionType | Should -Be 'exists'
        }

        It 'puts a tested MSI detection first as a product code row' {
            Set-PackageInfo @{ Type = 'MSI'; ProductCode = '{CCCCCCCC-1111-2222-3333-444444444444}' }

            $rules = @(Invoke-Selection -Select '{CCCCCCCC-1111-2222-3333-444444444444}')

            $script:GridCandidates[0].Source | Should -Be 'Packager (tested)'
            $script:GridCandidates[0].Type | Should -Be 'MSI'
            $rules[0].productCode | Should -Be '{CCCCCCCC-1111-2222-3333-444444444444}'
        }

        It 'drops a shortcut row that duplicates the tested File detection' {
            Set-PackageInfo @{ Type = 'File'; Path = $appDirectory; File = 'Contoso.exe'; Version = $expectedVersion }

            $null = Invoke-Selection

            @($script:GridCandidates | Where-Object Property -eq 'Contoso.exe').Count | Should -Be 1
            $script:GridCandidates[0].Source | Should -Be 'Packager (tested)'
            @($script:GridCandidates | Where-Object Source -eq 'Start Menu').Property | Should -Contain 'Helper.exe'
        }

        It 'drops an MSI row that duplicates the tested product code' {
            Set-PackageInfo @{ Type = 'MSI'; ProductCode = $mainProductCode }

            $null = Invoke-Selection

            @($script:GridCandidates | Where-Object Property -eq $mainProductCode).Count | Should -Be 1
            @($script:GridCandidates | Where-Object Type -eq 'MSI').Property | Should -Contain $addonProductCode
        }

        It 'adds no extra row without a Detection entry' {
            Set-Content -LiteralPath $infoPath -Value '{ "SchemaVersion": 1 }'

            $null = Invoke-Selection

            $script:GridCandidates.Source | Should -Not -Contain 'Packager (tested)'
        }
    }
}
