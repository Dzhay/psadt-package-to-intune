BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Import-Module $ModuleManifest -Force
}

Describe 'Publish-PSADTIntuneApp' {
    BeforeAll {
        $originalAppData = $env:APPDATA
        $originalConfigEnv = $env:PSADTINTUNE_CONFIG
        $env:PSADTINTUNE_CONFIG = $null

        $newAppId = '99999999-8888-7777-6666-555555555555'
        $oldAppId = '12345678-1234-1234-1234-123456789012'
        $pilotGroupId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
        $staffGroupId = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'

        # Console output and prompts
        Mock Write-Host -ModuleName PSADTIntune {}
        Mock Out-Host -ModuleName PSADTIntune {}
        Mock Write-Warning -ModuleName PSADTIntune {}
        Mock Read-Host -ModuleName PSADTIntune { '' }

        # Local steps: the real packager downloads IntuneWinAppUtil.exe, detection is covered in Detection.Tests.ps1
        Mock New-IntuneWin32AppPackage -ModuleName PSADTIntune {
            New-Item -ItemType File -Path (Join-Path $OutputFolder 'Invoke-AppDeployToolkit.intunewin') -Force | Out-Null
        }
        Mock Select-AppDetectionRule -ModuleName PSADTIntune {
            [ordered]@{
                '@odata.type'          = '#microsoft.graph.win32LobAppFileSystemDetection'
                'path'                 = 'C:\Program Files\Contoso'
                'fileOrFolderName'     = 'Contoso.exe'
                'check32BitOn64System' = $false
                'detectionType'        = 'exists'
            }
        }
        Mock New-IntuneWin32AppIcon -ModuleName PSADTIntune { 'iVBORw0KGgo=' }

        # Microsoft Graph / Intune.
        # OrderedDictionary parameters need -RemoveParameterType: Pester builds mocks from ProxyCommand,
        # which writes that type as [ordered], and that does not parse as a parameter type.
        $orderedDictionaryParameters = 'DetectionRule', 'RequirementRule', 'AdditionalRequirementRule'
        Mock Connect-MSIntuneGraph -ModuleName PSADTIntune {}
        Mock Add-IntuneWin32App -ModuleName PSADTIntune -RemoveParameterType $orderedDictionaryParameters {
            [PSCustomObject]@{ id = $newAppId; displayName = $DisplayName }
        }
        Mock Add-IntuneWin32AppAssignmentGroup -ModuleName PSADTIntune {}
        Mock Get-IntuneWin32AppAssignment -ModuleName PSADTIntune {}
        Mock Get-IntuneWin32AppAssignment -ModuleName PSADTIntune -ParameterFilter { $ID -eq $oldAppId } {
            [PSCustomObject]@{ GroupID = $null; GroupName = $null; Intent = 'required' }
            [PSCustomObject]@{ GroupID = $TestGroupId; GroupName = 'Packaging Test'; Intent = 'available' }
            [PSCustomObject]@{ GroupID = $pilotGroupId; GroupName = 'Pilot'; Intent = 'required' }
            [PSCustomObject]@{ GroupID = $staffGroupId; GroupName = 'All Staff'; Intent = 'available' }
        }
        Mock Get-IntuneWin32App -ModuleName PSADTIntune {
            [PSCustomObject]@{ id = $ID; displayName = 'Contoso App'; description = 'Old description'; displayVersion = '1.0.0'; publisher = 'Contoso' }
        }
        Mock Set-IntuneWin32App -ModuleName PSADTIntune -RemoveParameterType $orderedDictionaryParameters {}
        Mock Update-IntuneWin32AppPackageFile -ModuleName PSADTIntune {}
        # The real cmdlet looks the old app up in Graph
        Mock New-IntuneWin32AppSupersedence -ModuleName PSADTIntune {
            [ordered]@{ '@odata.type' = '#microsoft.graph.mobileAppSupersedence'; supersedenceType = $SupersedenceType.ToLower(); targetId = $ID }
        }
        Mock Add-IntuneWin32AppSupersedence -ModuleName PSADTIntune -RemoveParameterType 'Supersedence' {}
    }

    AfterAll {
        $env:APPDATA = $originalAppData
        $env:PSADTINTUNE_CONFIG = $originalConfigEnv
    }

    BeforeEach {
        $root = Join-Path $TestDrive ([guid]::NewGuid())
        $env:APPDATA = Join-Path $root 'AppData'
        $package = New-TestPSADTPackage -Path $root
        $configPath = New-TestConfig -Path (Join-Path $root 'config.json') -Params @{ Owner = 'QA'; AADGroupId = $TestGroupId }
        $common = @{ WorkingDirectory = $package.AppDirectory; ConfigPath = $configPath; Confirm = $false }
        $expectedPackage = Join-Path $package.AppDirectory 'Contoso_Test_App_Package.intunewin'
    }

    Context 'new app' {
        It 'creates the app from the PSADT script and the config' {
            Publish-PSADTIntuneApp @common

            Should -Invoke Add-IntuneWin32App -ModuleName PSADTIntune -Times 1 -Exactly -ParameterFilter {
                $DisplayName -eq 'Test App' -and
                $AppVersion -eq '9.9.9' -and
                $Publisher -eq 'Contoso' -and
                $Description -eq 'Contoso Test App 9.9.9' -and
                $InstallExperience -eq 'system' -and
                $Owner -eq 'QA' -and
                $Notes -eq 'Contoso_Test_App_Package' -and
                $InstallCommandLine -eq 'Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Auto' -and
                $UninstallCommandLine -eq 'Invoke-AppDeployToolkit.exe -DeploymentType Uninstall -DeployMode Auto' -and
                ($ScopeTagName -join ',') -eq 'Default'
            }
        }

        It 'names the package after the package folder' {
            Publish-PSADTIntuneApp @common

            $expectedPackage | Should -Exist
            Should -Invoke Add-IntuneWin32App -ModuleName PSADTIntune -Times 1 -Exactly -ParameterFilter { $FilePath -eq $expectedPackage }
        }

        It 'connects with the configured tenant and app registration' {
            Publish-PSADTIntuneApp @common

            Should -Invoke Connect-MSIntuneGraph -ModuleName PSADTIntune -Times 1 -Exactly -ParameterFilter {
                $TenantID -eq $TestTenantId -and $ClientID -eq $TestClientId
            }
        }

        It 'assigns the configured group as Available' {
            Publish-PSADTIntuneApp @common

            Should -Invoke Add-IntuneWin32AppAssignmentGroup -ModuleName PSADTIntune -Times 1 -Exactly -ParameterFilter {
                $Include -and $ID -eq $newAppId -and $GroupID -eq $TestGroupId -and $Intent -eq 'available'
            }
        }

        It 'makes no assignment when AADGroupId is not configured' {
            $common.ConfigPath = New-TestConfig -Path (Join-Path $root 'no-group.json')

            Publish-PSADTIntuneApp @common

            Should -Invoke Add-IntuneWin32AppAssignmentGroup -ModuleName PSADTIntune -Times 0 -Exactly
        }

        It 'returns nothing to the pipeline when the upload is skipped' {
            $result = Publish-PSADTIntuneApp -WorkingDirectory $package.AppDirectory -ConfigPath $configPath -WhatIf

            $result | Should -BeNullOrEmpty
        }

        It 'logs the app parameters before uploading, without hashtable internals' {
            Publish-PSADTIntuneApp @common

            Should -Invoke Write-Host -ModuleName PSADTIntune -Times 1 -Exactly -ParameterFilter { "$Object" -like '*"DisplayName": "Test App"*' }
            Should -Invoke Write-Host -ModuleName PSADTIntune -Times 0 -Exactly -ParameterFilter { "$Object" -match 'SyncRoot|IsFixedSize' }
        }

        It 'sends no icon when there is none' {
            Publish-PSADTIntuneApp @common

            Should -Invoke New-IntuneWin32AppIcon -ModuleName PSADTIntune -Times 0 -Exactly
            Should -Invoke Add-IntuneWin32App -ModuleName PSADTIntune -Times 1 -Exactly -ParameterFilter { [string]::IsNullOrEmpty($Icon) }
        }

        It 'uses the PSADT Assets icon when no icon was extracted' {
            $assetsIcon = New-TestPng -Path (Join-Path $package.PackageDirectory 'Assets\AppIcon.png')

            Publish-PSADTIntuneApp @common

            Should -Invoke New-IntuneWin32AppIcon -ModuleName PSADTIntune -Times 1 -Exactly -ParameterFilter { $FilePath -eq $assetsIcon }
            Should -Invoke Add-IntuneWin32App -ModuleName PSADTIntune -Times 1 -Exactly -ParameterFilter { $Icon -eq 'iVBORw0KGgo=' }
        }

        It 'prefers the icon extracted from the selected executable' {
            New-TestPng -Path (Join-Path $package.PackageDirectory 'Assets\AppIcon.png') | Out-Null
            $extractedIcon = New-TestPng -Path (Join-Path $package.AppDirectory 'AppIcon.png')

            Publish-PSADTIntuneApp @common

            Should -Invoke New-IntuneWin32AppIcon -ModuleName PSADTIntune -Times 1 -Exactly -ParameterFilter { $FilePath -eq $extractedIcon }
        }

        It '-WhatIf builds the package but does not connect or upload' {
            Publish-PSADTIntuneApp -WorkingDirectory $package.AppDirectory -ConfigPath $configPath -WhatIf

            $expectedPackage | Should -Exist
            Should -Invoke Connect-MSIntuneGraph -ModuleName PSADTIntune -Times 0 -Exactly
            Should -Invoke Add-IntuneWin32App -ModuleName PSADTIntune -Times 0 -Exactly
            Should -Invoke Write-Warning -ModuleName PSADTIntune -Times 1 -Exactly -ParameterFilter { $Message -eq 'Upload to Intune skipped.' }
        }
    }

    Context 'existing .intunewin file' {
        It 'reuses it when the answer is Y' {
            $existing = Join-Path $package.AppDirectory 'Prebuilt.intunewin'
            New-Item -ItemType File -Path $existing | Out-Null
            Mock Read-Host -ModuleName PSADTIntune { 'Y' }

            Publish-PSADTIntuneApp @common

            Should -Invoke New-IntuneWin32AppPackage -ModuleName PSADTIntune -Times 0 -Exactly
            Should -Invoke Add-IntuneWin32App -ModuleName PSADTIntune -Times 1 -Exactly -ParameterFilter { $FilePath -eq $existing }
        }

        It 'replaces it when the answer is empty' {
            $existing = Join-Path $package.AppDirectory 'Prebuilt.intunewin'
            New-Item -ItemType File -Path $existing | Out-Null

            Publish-PSADTIntuneApp @common

            $existing | Should -Not -Exist
            Should -Invoke New-IntuneWin32AppPackage -ModuleName PSADTIntune -Times 1 -Exactly
            Should -Invoke Add-IntuneWin32App -ModuleName PSADTIntune -Times 1 -Exactly -ParameterFilter { $FilePath -eq $expectedPackage }
        }

        It 'stops when there are several' {
            New-Item -ItemType File -Path (Join-Path $package.AppDirectory 'One.intunewin'), (Join-Path $package.AppDirectory 'Two.intunewin') | Out-Null

            { Publish-PSADTIntuneApp @common } | Should -Throw '*Multiple .intunewin files*'
            Should -Invoke Add-IntuneWin32App -ModuleName PSADTIntune -Times 0 -Exactly
        }
    }

    Context 'working directory' {
        It 'runs inside the package folder with a relative path and cleans up afterwards' {
            Push-Location -LiteralPath $package.PackageDirectory
            try {
                Publish-PSADTIntuneApp -WorkingDirectory '.' -ConfigPath $configPath -Confirm:$false
            }
            finally {
                Pop-Location
            }

            Should -Invoke Add-IntuneWin32App -ModuleName PSADTIntune -Times 1 -Exactly -ParameterFilter {
                $FilePath -eq (Join-Path $package.PackageDirectory 'Contoso_Test_App_Package.intunewin') -and
                $Notes -eq 'Contoso_Test_App_Package'
            }
            Get-ChildItem -LiteralPath $package.PackageDirectory -Filter '*.intunewin' | Should -BeNullOrEmpty
        }

        It 'accepts a trailing backslash' {
            $common.WorkingDirectory = "$($package.AppDirectory)\"

            Publish-PSADTIntuneApp @common

            Should -Invoke Add-IntuneWin32App -ModuleName PSADTIntune -Times 1 -Exactly -ParameterFilter { $FilePath -eq $expectedPackage }
        }

        It 'fails when the folder has no package subfolder' {
            $empty = New-Item -ItemType Directory -Path (Join-Path $root 'Empty')
            $common.WorkingDirectory = $empty.FullName

            { Publish-PSADTIntuneApp @common } | Should -Throw '*No subdirectory found*'
        }

        It 'fails when Invoke-AppDeployToolkit.ps1 is missing' {
            Remove-Item -LiteralPath (Join-Path $package.PackageDirectory 'Invoke-AppDeployToolkit.ps1')

            { Publish-PSADTIntuneApp @common } | Should -Throw '*No PSADT v4 script*'
            Should -Invoke New-IntuneWin32AppPackage -ModuleName PSADTIntune -Times 0 -Exactly
        }

    }

    Context 'first run without a config' {
        BeforeEach {
            $common.Remove('ConfigPath')
            $defaultConfig = Join-Path $env:APPDATA 'PSADTIntune\intune-config.json'
            Mock Start-Process -ModuleName PSADTIntune {}
        }

        It 'fails with setup instructions before packaging when <Case>' -ForEach @(
            @{ Case = 'input is closed'; Answer = { $null } }
            @{ Case = 'PowerShell is non-interactive'; Answer = { throw 'PowerShell is in NonInteractive mode.' } }
        ) {
            Mock Read-Host -ModuleName PSADTIntune -ParameterFilter { $Prompt -like 'Set up the config*' } $Answer

            { Publish-PSADTIntuneApp @common } | Should -Throw '*Set-PSADTIntuneConfig*'
            $defaultConfig | Should -Not -Exist
            Should -Invoke New-IntuneWin32AppPackage -ModuleName PSADTIntune -Times 0 -Exactly
        }

        It 'asks for TenantId and ClientId, saves them and continues with the upload' {
            Mock Read-Host -ModuleName PSADTIntune -ParameterFilter { $Prompt -like 'Set up the config*' } { 'y' }
            Mock Read-Host -ModuleName PSADTIntune -ParameterFilter { $Prompt -like 'TenantId*' } { $TestTenantId }
            Mock Read-Host -ModuleName PSADTIntune -ParameterFilter { $Prompt -like 'ClientId*' } { $TestClientId }

            Publish-PSADTIntuneApp @common

            (Get-PSADTIntuneConfig).TenantId | Should -Be $TestTenantId
            Should -Invoke Connect-MSIntuneGraph -ModuleName PSADTIntune -Times 1 -Exactly -ParameterFilter {
                $TenantID -eq $TestTenantId -and $ClientID -eq $TestClientId
            }
            Should -Invoke Add-IntuneWin32App -ModuleName PSADTIntune -Times 1 -Exactly
        }

        It 'also offers setup when the config file exists without TenantId and ClientId' {
            New-Item -ItemType Directory -Path (Split-Path $defaultConfig) -Force | Out-Null
            Set-Content -LiteralPath $defaultConfig -Value '{ "TenantId": "", "AADClientId": "", "Params": { "Owner": "IT" } }'
            Mock Read-Host -ModuleName PSADTIntune -ParameterFilter { $Prompt -like 'TenantId*' } { $TestTenantId }
            Mock Read-Host -ModuleName PSADTIntune -ParameterFilter { $Prompt -like 'ClientId*' } { $TestClientId }

            Publish-PSADTIntuneApp @common

            (Get-PSADTIntuneConfig).Owner | Should -Be 'IT'
            Should -Invoke Add-IntuneWin32App -ModuleName PSADTIntune -Times 1 -Exactly
        }

        It 'opens the default config in an editor and stops when the user picks E' {
            Mock Read-Host -ModuleName PSADTIntune -ParameterFilter { $Prompt -like 'Set up the config*' } { 'e' }

            Publish-PSADTIntuneApp @common

            $defaultConfig | Should -Exist
            Should -Invoke Start-Process -ModuleName PSADTIntune -Times 1 -Exactly -ParameterFilter { $ArgumentList -like "*$defaultConfig*" }
            Should -Invoke New-IntuneWin32AppPackage -ModuleName PSADTIntune -Times 0 -Exactly
        }

        It 'stops without creating a config when the user cancels' {
            Mock Read-Host -ModuleName PSADTIntune -ParameterFilter { $Prompt -like 'Set up the config*' } { 'n' }

            Publish-PSADTIntuneApp @common

            $defaultConfig | Should -Not -Exist
            Should -Invoke New-IntuneWin32AppPackage -ModuleName PSADTIntune -Times 0 -Exactly
        }
    }

    Context 'open the config (-Config)' {
        BeforeEach {
            Mock Start-Process -ModuleName PSADTIntune {}
        }

        It 'creates the default config from the template and opens it' {
            $defaultConfig = Join-Path $env:APPDATA 'PSADTIntune\intune-config.json'

            Publish-PSADTIntuneApp -Config

            $defaultConfig | Should -Exist
            (Get-Content -LiteralPath $defaultConfig -Raw | ConvertFrom-Json).Params.Architecture | Should -Be 'x64'
            Should -Invoke Start-Process -ModuleName PSADTIntune -Times 1 -Exactly -ParameterFilter { $ArgumentList -like "*$defaultConfig*" }
        }

        It 'opens an existing config without changing it' {
            $before = Get-Content -LiteralPath $configPath -Raw

            Publish-PSADTIntuneApp -Config -ConfigPath $configPath

            Get-Content -LiteralPath $configPath -Raw | Should -Be $before
            Should -Invoke Start-Process -ModuleName PSADTIntune -Times 1 -Exactly -ParameterFilter { $ArgumentList -like "*$configPath*" }
        }

        It 'does not package or connect' {
            Publish-PSADTIntuneApp -Config -ConfigPath $configPath

            Should -Invoke New-IntuneWin32AppPackage -ModuleName PSADTIntune -Times 0 -Exactly
            Should -Invoke Connect-MSIntuneGraph -ModuleName PSADTIntune -Times 0 -Exactly
        }
    }

    Context 'update an existing app (-AppId)' {
        It 'replaces the package and sets the PSADT version' {
            Publish-PSADTIntuneApp @common -AppId $oldAppId

            Should -Invoke Update-IntuneWin32AppPackageFile -ModuleName PSADTIntune -Times 1 -Exactly -ParameterFilter {
                $ID -eq $oldAppId -and $FilePath -eq $expectedPackage
            }
            Should -Invoke Set-IntuneWin32App -ModuleName PSADTIntune -Times 1 -Exactly -ParameterFilter {
                $ID -eq $oldAppId -and $AppVersion -eq '9.9.9'
            }
            Should -Invoke Add-IntuneWin32App -ModuleName PSADTIntune -Times 0 -Exactly
        }

        It 'warns that detection rules are not updated when the version changes' {
            Publish-PSADTIntuneApp @common -AppId $oldAppId

            Should -Invoke Write-Warning -ModuleName PSADTIntune -Times 1 -Exactly -ParameterFilter { $Message -like 'Detection rules are NOT updated*' }
        }

        It 'leaves the version alone when it has not changed' {
            Mock Get-IntuneWin32App -ModuleName PSADTIntune {
                [PSCustomObject]@{ id = $ID; displayName = 'Contoso App'; displayVersion = '9.9.9'; publisher = 'Contoso' }
            }

            Publish-PSADTIntuneApp @common -AppId $oldAppId

            Should -Invoke Update-IntuneWin32AppPackageFile -ModuleName PSADTIntune -Times 1 -Exactly
            Should -Invoke Set-IntuneWin32App -ModuleName PSADTIntune -Times 0 -Exactly
            Should -Invoke Write-Warning -ModuleName PSADTIntune -Times 0 -Exactly -ParameterFilter { $Message -like 'Detection rules*' }
        }

        It '-WhatIf changes nothing in Intune' {
            Publish-PSADTIntuneApp -WorkingDirectory $package.AppDirectory -ConfigPath $configPath -AppId $oldAppId -WhatIf

            Should -Invoke Update-IntuneWin32AppPackageFile -ModuleName PSADTIntune -Times 0 -Exactly
            Should -Invoke Set-IntuneWin32App -ModuleName PSADTIntune -Times 0 -Exactly
        }

        It 'fails when the app does not exist' {
            Mock Get-IntuneWin32App -ModuleName PSADTIntune { $null }
            Mock Write-Error -ModuleName PSADTIntune {}

            { Publish-PSADTIntuneApp @common -AppId $oldAppId } | Should -Throw '*No application found*'
            Should -Invoke Update-IntuneWin32AppPackageFile -ModuleName PSADTIntune -Times 0 -Exactly
        }
    }

    Context 'supersede an existing app (-Supersede)' {
        It 'creates the new app and copies the old name and description' {
            Publish-PSADTIntuneApp @common -Supersede $oldAppId

            Should -Invoke Add-IntuneWin32App -ModuleName PSADTIntune -Times 1 -Exactly
            Should -Invoke Set-IntuneWin32App -ModuleName PSADTIntune -Times 1 -Exactly -ParameterFilter {
                $ID -eq $newAppId -and $DisplayName -eq 'Contoso App' -and $Description -eq 'Old description'
            }
        }

        It 'adds Update supersedence over the old app' {
            Publish-PSADTIntuneApp @common -Supersede $oldAppId

            Should -Invoke Add-IntuneWin32AppSupersedence -ModuleName PSADTIntune -Times 1 -Exactly -ParameterFilter {
                $ID -eq $newAppId -and
                @($Supersedence)[0].targetId -eq $oldAppId -and
                @($Supersedence)[0].supersedenceType -eq 'update'
            }
        }

        It 'excludes the groups of the old app, keeping their intent' {
            Publish-PSADTIntuneApp @common -Supersede $oldAppId

            Should -Invoke Add-IntuneWin32AppAssignmentGroup -ModuleName PSADTIntune -Times 1 -Exactly -ParameterFilter {
                $Exclude -and $ID -eq $newAppId -and $GroupID -eq $pilotGroupId -and $Intent -eq 'required'
            }
            Should -Invoke Add-IntuneWin32AppAssignmentGroup -ModuleName PSADTIntune -Times 1 -Exactly -ParameterFilter {
                $Exclude -and $ID -eq $newAppId -and $GroupID -eq $staffGroupId -and $Intent -eq 'available'
            }
        }

        It 'does not exclude the configured test group or All Users / All Devices' {
            Publish-PSADTIntuneApp @common -Supersede $oldAppId

            Should -Invoke Add-IntuneWin32AppAssignmentGroup -ModuleName PSADTIntune -Times 2 -Exactly -ParameterFilter { $Exclude }
            Should -Invoke Add-IntuneWin32AppAssignmentGroup -ModuleName PSADTIntune -Times 1 -Exactly -ParameterFilter {
                $Include -and $GroupID -eq $TestGroupId
            }
            Should -Invoke Write-Warning -ModuleName PSADTIntune -Times 1 -Exactly -ParameterFilter { $Message -like 'Skipping All Users / All Devices*' }
        }

        It 'skips supersedence with a warning when nothing was uploaded' {
            Publish-PSADTIntuneApp -WorkingDirectory $package.AppDirectory -ConfigPath $configPath -Supersede $oldAppId -WhatIf

            Should -Invoke Add-IntuneWin32AppSupersedence -ModuleName PSADTIntune -Times 0 -Exactly
            Should -Invoke Set-IntuneWin32App -ModuleName PSADTIntune -Times 0 -Exactly
            Should -Invoke Write-Warning -ModuleName PSADTIntune -Times 1 -Exactly -ParameterFilter { $Message -like 'Supersedence over*was not configured*' }
        }
    }
}
