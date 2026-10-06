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
                Select-AppDetectionRule -RequireAdmin $RequireAdmin -Context $Context -Paths $Paths
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
            Remove-Item -LiteralPath (Join-Path $workingDirectory 'AppIcon.png') -ErrorAction SilentlyContinue
        }

        It 'saves the icon of the selected file as AppIcon.png' {
            $null = Invoke-Selection -Select 'Contoso.exe'

            $icon = Join-Path $workingDirectory 'AppIcon.png'
            $icon | Should -Exist
            # PNG signature
            ([System.IO.File]::ReadAllBytes($icon)[0..3] -join ',') | Should -Be '137,80,78,71'
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
}
