using namespace System.Management.Automation.Language

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Import-Module $ModuleManifest -Force

    $module = Get-Module PSADTIntune
    $manifest = Import-PowerShellDataFile -Path $ModuleManifest
}

Describe 'Module manifest' {
    It 'is valid' {
        { Test-ModuleManifest -Path $ModuleManifest -ErrorAction Stop } | Should -Not -Throw
    }

    It 'requires PowerShell 7.2 or later' {
        $manifest.PowerShellVersion | Should -Be '7.2'
        $manifest.CompatiblePSEditions | Should -Be 'Core'
    }

    It 'requires IntuneWin32App 1.4.4 or later and ConsoleGuiTools' {
        $intuneWin32App = $manifest.RequiredModules | Where-Object { $_ -is [hashtable] -and $_.ModuleName -eq 'IntuneWin32App' }
        $intuneWin32App.ModuleVersion | Should -Be '1.4.4'
        $manifest.RequiredModules | Should -Contain 'Microsoft.PowerShell.ConsoleGuiTools'
    }

    It 'exports every function in Public\ and nothing else' {
        $publicFunctions = (Get-ChildItem -Path (Join-Path $ModuleRoot 'Public') -Filter '*.ps1').BaseName | Sort-Object

        ($manifest.FunctionsToExport | Sort-Object) -join ',' | Should -Be ($publicFunctions -join ',')
        ($module.ExportedFunctions.Keys | Sort-Object) -join ',' | Should -Be ($publicFunctions -join ',')
    }

    It 'exports the packageIntune and PSADTIntune aliases for Publish-PSADTIntuneApp' {
        ($manifest.AliasesToExport | Sort-Object) -join ',' | Should -Be 'packageIntune,PSADTIntune'
        ($module.ExportedAliases.Keys | Sort-Object) -join ',' | Should -Be 'packageIntune,PSADTIntune'
        (Get-Alias -Name packageIntune).ResolvedCommandName | Should -Be 'Publish-PSADTIntuneApp'
        (Get-Alias -Name PSADTIntune).ResolvedCommandName | Should -Be 'Publish-PSADTIntuneApp'
    }

    It 'links to the project and license' {
        $manifest.PrivateData.PSData.ProjectUri | Should -Not -BeNullOrEmpty
        $manifest.PrivateData.PSData.LicenseUri | Should -Not -BeNullOrEmpty
    }

    It 'has a CHANGELOG entry for this version or an Unreleased section' {
        $changelog = Get-Content -LiteralPath (Join-Path $RepoRoot 'CHANGELOG.md') -Raw
        $versionHeading = '## [{0}]' -f $manifest.ModuleVersion

        ($changelog.Contains($versionHeading) -or $changelog.Contains('## [Unreleased]')) | Should -BeTrue
    }
}

Describe 'Shipped config template' {
    BeforeAll {
        $template = Get-Content -LiteralPath (Join-Path $ModuleRoot 'intune-config.json') -Raw | ConvertFrom-Json
    }

    It 'contains no tenant, client or group ID' {
        $template.TenantId | Should -BeNullOrEmpty
        $template.AADClientId | Should -BeNullOrEmpty
        $template.Params.AADGroupId | Should -BeNullOrEmpty
    }

    It 'uses requirement values that IntuneWin32App accepts' {
        $requirementRule = Get-Command -Name New-IntuneWin32AppRequirementRule
        $architectures = ($requirementRule.Parameters['Architecture'].Attributes | Where-Object { $_ -is [ValidateSet] }).ValidValues
        $releases = ($requirementRule.Parameters['MinimumSupportedWindowsRelease'].Attributes | Where-Object { $_ -is [ValidateSet] }).ValidValues

        $architectures | Should -Contain $template.Params.Architecture
        $releases | Should -Contain $template.Params.MinimumWindowsRelease
    }
}

Describe 'Help' {
    It '<_> has a synopsis, description and examples' -ForEach @('Publish-PSADTIntuneApp', 'Set-PSADTIntuneConfig', 'Get-PSADTIntuneConfig') {
        $help = Get-Help -Name $_ -Full

        $help.Synopsis | Should -Not -BeNullOrEmpty
        $help.Synopsis | Should -Not -BeLike "$_ *"
        ($help.description.Text -join '') | Should -Not -BeNullOrEmpty
        @($help.examples.example).Count | Should -BeGreaterThan 0
    }

    It '<_> documents every parameter' -ForEach @('Publish-PSADTIntuneApp', 'Set-PSADTIntuneConfig', 'Get-PSADTIntuneConfig') {
        $commandName = $_
        $help = Get-Help -Name $commandName -Full
        $commonParameters = [System.Management.Automation.PSCmdlet]::CommonParameters + [System.Management.Automation.PSCmdlet]::OptionalCommonParameters
        $parameters = (Get-Command -Name $commandName).Parameters.Keys | Where-Object { $_ -notin $commonParameters }

        foreach ($parameter in $parameters) {
            $parameterHelp = $help.parameters.parameter | Where-Object { $_.name -eq $parameter }
            ($parameterHelp.description.Text -join '') | Should -Not -BeNullOrEmpty -Because "-$parameter of $commandName needs a .PARAMETER entry"
        }
    }

    It 'has the about_PSADTIntune topic' {
        Get-Help -Name about_PSADTIntune | Out-String | Should -Match 'QUICK START'
    }

    Context 'packageIntune -Help' {
        BeforeAll {
            $originalAppData = $env:APPDATA
            $originalConfigEnv = $env:PSADTINTUNE_CONFIG
            $env:APPDATA = Join-Path $TestDrive 'AppData'
            $env:PSADTINTUNE_CONFIG = $null
            Mock Connect-MSIntuneGraph -ModuleName PSADTIntune {}
        }

        AfterAll {
            $env:APPDATA = $originalAppData
            $env:PSADTINTUNE_CONFIG = $originalConfigEnv
        }

        It 'prints usage and the config location without connecting' {
            $output = (Publish-PSADTIntuneApp -Help 6>&1 | ForEach-Object { "$_" }) -join "`n"

            $output | Should -Match 'packageIntune -AppId'
            $output | Should -Match ([regex]::Escape((Join-Path $env:APPDATA 'PSADTIntune\intune-config.json')))
            $output | Should -Match 'Get-Help about_PSADTIntune'
            Should -Invoke Connect-MSIntuneGraph -ModuleName PSADTIntune -Times 0 -Exactly
        }
    }
}

Describe 'Parameters of Publish-PSADTIntuneApp' {
    It 'has the parameter sets New, Update, Supersede, Install, Uninstall and Help' {
        ((Get-Command -Name Publish-PSADTIntuneApp).ParameterSets.Name | Sort-Object) -join ',' | Should -Be 'Help,Install,New,Supersede,Uninstall,Update'
    }

    It 'accepts -i and -u as short forms of -Install and -Uninstall' {
        $parameters = (Get-Command -Name Publish-PSADTIntuneApp).Parameters

        $parameters['Install'].Aliases | Should -Contain 'i'
        $parameters['Uninstall'].Aliases | Should -Contain 'u'
    }

    It 'does not allow <Description>' -ForEach @(
        @{ Description = '-AppId together with -Supersede'; Arguments = @{ AppId = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'; Supersede = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890' } }
        @{ Description = '-Install together with -Uninstall'; Arguments = @{ Install = $true; Uninstall = $true } }
        @{ Description = '-Install together with -AppId'; Arguments = @{ Install = $true; AppId = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890' } }
        @{ Description = '-Uninstall together with -Supersede'; Arguments = @{ Uninstall = $true; Supersede = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890' } }
    ) {
        { Publish-PSADTIntuneApp @Arguments } | Should -Throw -ErrorId 'AmbiguousParameterSet*'
    }

    It 'rejects the app ID <_>' -ForEach @('abc-123', '12345678-1234-1234-1234-12345678901', 'zzzzzzzz-zzzz-zzzz-zzzz-zzzzzzzzzzzz') {
        { Publish-PSADTIntuneApp -AppId $_ } | Should -Throw -ErrorId 'ParameterArgumentValidationError*'
    }

    It 'rejects a working directory that does not exist' {
        { Publish-PSADTIntuneApp -WorkingDirectory (Join-Path $TestDrive 'missing') } | Should -Throw -ErrorId 'ParameterArgumentValidationError*'
    }
}

Describe 'Code quality' {
    It 'passes PSScriptAnalyzer' {
        if (-not (Get-Module -ListAvailable -Name PSScriptAnalyzer)) {
            Set-ItResult -Skipped -Because 'PSScriptAnalyzer is not installed'
            return
        }

        $results = Invoke-ScriptAnalyzer -Path $ModuleRoot -Recurse -Settings (Join-Path $RepoRoot 'PSScriptAnalyzerSettings.psd1')

        $results | ForEach-Object { '{0}:{1} [{2}] {3}' -f $_.ScriptName, $_.Line, $_.RuleName, $_.Message } | Should -BeNullOrEmpty
    }

    It 'calls IntuneWin32App only with parameters that exist in the installed version' {
        # Catches breaking changes when IntuneWin32App is updated. Checks named parameters and
        # the keys of hashtables that are splatted into IntuneWin32App commands.
        $intuneWin32AppCommands = @{}
        foreach ($name in (Get-Module -Name IntuneWin32App).ExportedCommands.Keys) {
            $intuneWin32AppCommands[$name] = Get-Command -Name $name
        }

        $checked = 0
        $problems = foreach ($file in Get-ChildItem -Path $ModuleRoot -Recurse -Filter '*.ps1') {
            $ast = [Parser]::ParseFile($file.FullName, [ref]$null, [ref]$null)

            # Keys assigned to variables: $x = @{ Key = ... } / [ordered]@{ ... } and $x['Key'] = ...
            $hashtableKeys = @{}
            foreach ($assignment in $ast.FindAll({ $args[0] -is [AssignmentStatementAst] }, $true)) {
                if ($assignment.Left -is [VariableExpressionAst]) {
                    $hashtable = $assignment.Right.Find({ $args[0] -is [HashtableAst] }, $true)
                    if ($hashtable) {
                        $hashtableKeys[$assignment.Left.VariablePath.UserPath] += @($hashtable.KeyValuePairs | ForEach-Object { $_.Item1.Value })
                    }
                }
                elseif ($assignment.Left -is [IndexExpressionAst] -and
                    $assignment.Left.Target -is [VariableExpressionAst] -and
                    $assignment.Left.Index -is [StringConstantExpressionAst]) {
                    $hashtableKeys[$assignment.Left.Target.VariablePath.UserPath] += @($assignment.Left.Index.Value)
                }
            }

            foreach ($command in $ast.FindAll({ $args[0] -is [CommandAst] }, $true)) {
                $commandName = $command.GetCommandName()
                if (-not $commandName -or -not $intuneWin32AppCommands.ContainsKey($commandName)) { continue }

                $parameterInfo = $intuneWin32AppCommands[$commandName].Parameters.Values
                $knownNames = @($parameterInfo.Name) + @($parameterInfo.Aliases)
                $usedNames = foreach ($element in $command.CommandElements) {
                    if ($element -is [CommandParameterAst]) { $element.ParameterName }
                    elseif ($element -is [VariableExpressionAst] -and $element.Splatted) { $hashtableKeys[$element.VariablePath.UserPath] }
                }

                foreach ($usedName in $usedNames) {
                    $checked++
                    if (-not ($knownNames | Where-Object { $_ -like "$usedName*" })) {
                        "$($file.Name): $commandName -$usedName"
                    }
                }
            }
        }

        $checked | Should -BeGreaterThan 50 -Because 'the scan should find the IntuneWin32App calls'
        $problems | Should -BeNullOrEmpty
    }
}
