BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Import-Module $ModuleManifest -Force
}

Describe 'Publish-PSADTIntuneApp -Install / -Uninstall' {
    BeforeAll {
        $originalAppData = $env:APPDATA
        $originalConfigEnv = $env:PSADTINTUNE_CONFIG
        $env:PSADTINTUNE_CONFIG = $null

        Mock Write-Host -ModuleName PSADTIntune {}
        Mock Write-Warning -ModuleName PSADTIntune {}
        Mock Test-IsElevated -ModuleName PSADTIntune { $true }
        Mock Start-Process -ModuleName PSADTIntune { [PSCustomObject]@{ ExitCode = 0 } }

        # A local install or uninstall must not reach these
        Mock Connect-MSIntuneGraph -ModuleName PSADTIntune {}
        Mock New-IntuneWin32AppPackage -ModuleName PSADTIntune {}
    }

    AfterAll {
        $env:APPDATA = $originalAppData
        $env:PSADTINTUNE_CONFIG = $originalConfigEnv
    }

    BeforeEach {
        $root = Join-Path $TestDrive ([guid]::NewGuid())
        $env:APPDATA = Join-Path $root 'AppData'
        $package = New-TestPSADTPackage -Path $root
        $packageExe = Join-Path $package.PackageDirectory 'Invoke-AppDeployToolkit.exe'
    }

    Context 'command line' {
        It '-Install runs the default install command in the package folder' {
            Publish-PSADTIntuneApp -Install -WorkingDirectory $package.AppDirectory

            Should -Invoke Start-Process -ModuleName PSADTIntune -Times 1 -Exactly -ParameterFilter {
                $FilePath -eq $packageExe -and
                ($ArgumentList -join ' ') -eq '-DeploymentType Install -DeployMode Auto' -and
                $WorkingDirectory -eq $package.PackageDirectory -and
                $Wait -and $PassThru
            }
        }

        It '-Uninstall runs the default uninstall command in the package folder' {
            Publish-PSADTIntuneApp -Uninstall -WorkingDirectory $package.AppDirectory

            Should -Invoke Start-Process -ModuleName PSADTIntune -Times 1 -Exactly -ParameterFilter {
                $FilePath -eq $packageExe -and
                ($ArgumentList -join ' ') -eq '-DeploymentType Uninstall -DeployMode Auto' -and
                $WorkingDirectory -eq $package.PackageDirectory
            }
        }

        It '-i is short for -Install and -u for -Uninstall' {
            Publish-PSADTIntuneApp -i -WorkingDirectory $package.AppDirectory
            Publish-PSADTIntuneApp -u -WorkingDirectory $package.AppDirectory

            Should -Invoke Start-Process -ModuleName PSADTIntune -Times 1 -Exactly -ParameterFilter { ($ArgumentList -join ' ') -like '-DeploymentType Install *' }
            Should -Invoke Start-Process -ModuleName PSADTIntune -Times 1 -Exactly -ParameterFilter { ($ArgumentList -join ' ') -like '-DeploymentType Uninstall *' }
        }

        It 'works through the PSADTIntune alias' {
            PSADTIntune -i -WorkingDirectory $package.AppDirectory

            Should -Invoke Start-Process -ModuleName PSADTIntune -Times 1 -Exactly
        }

        It 'works from inside the package folder' {
            Push-Location -LiteralPath $package.PackageDirectory
            try {
                Publish-PSADTIntuneApp -i
            }
            finally {
                Pop-Location
            }

            Should -Invoke Start-Process -ModuleName PSADTIntune -Times 1 -Exactly -ParameterFilter { $FilePath -eq $packageExe }
        }

        It 'accepts a quoted program' {
            $configPath = New-TestConfig -Path (Join-Path $root 'config.json') -Params @{
                InstallCommandLine = '"Invoke-AppDeployToolkit.exe" -DeploymentType Install -DeployMode Silent'
            }

            Publish-PSADTIntuneApp -i -WorkingDirectory $package.AppDirectory -ConfigPath $configPath

            Should -Invoke Start-Process -ModuleName PSADTIntune -Times 1 -Exactly -ParameterFilter {
                $FilePath -eq $packageExe -and ($ArgumentList -join ' ') -eq '-DeploymentType Install -DeployMode Silent'
            }
        }

        It 'starts a program that is not in the package folder as given' {
            $configPath = New-TestConfig -Path (Join-Path $root 'config.json') -Params @{
                InstallCommandLine = 'powershell.exe -NoProfile -File Invoke-AppDeployToolkit.ps1 -DeploymentType Install'
            }

            Publish-PSADTIntuneApp -i -WorkingDirectory $package.AppDirectory -ConfigPath $configPath

            Should -Invoke Start-Process -ModuleName PSADTIntune -Times 1 -Exactly -ParameterFilter {
                $FilePath -eq 'powershell.exe' -and
                ($ArgumentList -join ' ') -eq '-NoProfile -File Invoke-AppDeployToolkit.ps1 -DeploymentType Install' -and
                $WorkingDirectory -eq $package.PackageDirectory
            }
        }

        It 'passes no arguments when the command line has none' {
            $configPath = New-TestConfig -Path (Join-Path $root 'config.json') -Params @{ UninstallCommandLine = 'Invoke-AppDeployToolkit.exe' }

            Publish-PSADTIntuneApp -u -WorkingDirectory $package.AppDirectory -ConfigPath $configPath

            Should -Invoke Start-Process -ModuleName PSADTIntune -Times 1 -Exactly -ParameterFilter { $FilePath -eq $packageExe -and -not $ArgumentList }
        }
    }

    Context 'config' {
        It 'uses the command line from the per-user config file' {
            New-TestConfig -Path (Join-Path $env:APPDATA 'PSADTIntune\intune-config.json') -Params @{
                UninstallCommandLine = 'Invoke-AppDeployToolkit.exe -DeploymentType Uninstall -DeployMode NonInteractive'
            } | Out-Null

            Publish-PSADTIntuneApp -u -WorkingDirectory $package.AppDirectory

            Should -Invoke Start-Process -ModuleName PSADTIntune -Times 1 -Exactly -ParameterFilter {
                ($ArgumentList -join ' ') -eq '-DeploymentType Uninstall -DeployMode NonInteractive'
            }
        }

        It 'does not need TenantId or ClientId' {
            $configPath = Join-Path $root 'no-connection.json'
            Set-Content -LiteralPath $configPath -Value '{ "Params": { "Owner": "IT" } }'

            Publish-PSADTIntuneApp -i -WorkingDirectory $package.AppDirectory -ConfigPath $configPath

            Should -Invoke Start-Process -ModuleName PSADTIntune -Times 1 -Exactly
        }

        It 'fails when the given -ConfigPath does not exist' {
            { Publish-PSADTIntuneApp -i -WorkingDirectory $package.AppDirectory -ConfigPath (Join-Path $root 'missing.json') } |
                Should -Throw '*No PSADTIntune config found*'
            Should -Invoke Start-Process -ModuleName PSADTIntune -Times 0 -Exactly
        }

        It 'does not sign in to Intune or build a package' {
            Publish-PSADTIntuneApp -i -WorkingDirectory $package.AppDirectory

            Should -Invoke Connect-MSIntuneGraph -ModuleName PSADTIntune -Times 0 -Exactly
            Should -Invoke New-IntuneWin32AppPackage -ModuleName PSADTIntune -Times 0 -Exactly
        }

        It 'fails when the folder has no PSADT package' {
            $empty = New-Item -ItemType Directory -Path (Join-Path $root 'Empty')

            { Publish-PSADTIntuneApp -i -WorkingDirectory $empty.FullName } | Should -Throw '*No subdirectory found*'
            Should -Invoke Start-Process -ModuleName PSADTIntune -Times 0 -Exactly
        }
    }

    Context 'elevation' {
        It 'asks for elevation when the package requires admin and PowerShell is not elevated' {
            Mock Test-IsElevated -ModuleName PSADTIntune { $false }

            Publish-PSADTIntuneApp -i -WorkingDirectory $package.AppDirectory

            Should -Invoke Start-Process -ModuleName PSADTIntune -Times 1 -Exactly -ParameterFilter { $Verb -eq 'RunAs' }
        }

        It 'does not ask when PowerShell is already elevated' {
            Publish-PSADTIntuneApp -i -WorkingDirectory $package.AppDirectory

            Should -Invoke Start-Process -ModuleName PSADTIntune -Times 1 -Exactly -ParameterFilter { -not $Verb }
        }

        It 'does not ask for user-context packages' {
            Mock Test-IsElevated -ModuleName PSADTIntune { $false }
            $userPackage = New-TestPSADTPackage -Path (Join-Path $root 'User') -RequireAdmin '$false'

            Publish-PSADTIntuneApp -i -WorkingDirectory $userPackage.AppDirectory

            Should -Invoke Start-Process -ModuleName PSADTIntune -Times 1 -Exactly -ParameterFilter { -not $Verb }
        }
    }

    Context 'result' {
        It 'reports success for exit code 0 without warnings' {
            { Publish-PSADTIntuneApp -i -WorkingDirectory $package.AppDirectory } | Should -Not -Throw

            Should -Invoke Write-Warning -ModuleName PSADTIntune -Times 0 -Exactly
        }

        It 'treats exit code <_> as success that needs a restart' -ForEach @(1641, 3010) {
            $exitCode = $_
            Mock Start-Process -ModuleName PSADTIntune { [PSCustomObject]@{ ExitCode = $exitCode } }

            { Publish-PSADTIntuneApp -i -WorkingDirectory $package.AppDirectory } | Should -Not -Throw

            Should -Invoke Write-Warning -ModuleName PSADTIntune -Times 1 -Exactly -ParameterFilter { $Message -like '*restart is required*' }
        }

        It 'fails on exit code <_>' -ForEach @(1, 1603, 60001) {
            $exitCode = $_
            Mock Start-Process -ModuleName PSADTIntune { [PSCustomObject]@{ ExitCode = $exitCode } }

            { Publish-PSADTIntuneApp -i -WorkingDirectory $package.AppDirectory } | Should -Throw "*failed with exit code $exitCode*"
        }

        It '-WhatIf runs nothing' {
            Publish-PSADTIntuneApp -i -WorkingDirectory $package.AppDirectory -WhatIf

            Should -Invoke Start-Process -ModuleName PSADTIntune -Times 0 -Exactly
        }
    }
}
