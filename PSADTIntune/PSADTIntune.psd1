@{
    RootModule           = 'PSADTIntune.psm1'
    ModuleVersion        = '0.8.0'
    GUID                 = 'e0ef784f-8a0f-4e8e-9a93-e588eb489142'
    Author               = 'Darius Lakačauskis'
    Copyright            = '(c) 2026 Darius Lakačauskis. MIT License.'
    Description          = 'Packages PSAppDeployToolkit (PSADT) v4 applications as .intunewin and uploads, updates or supersedes them as Win32 apps in Microsoft Intune.'
    PowerShellVersion    = '7.2'
    CompatiblePSEditions = @('Core')

    RequiredModules      = @(
        @{ ModuleName = 'IntuneWin32App'; ModuleVersion = '1.4.4' }
        'Microsoft.PowerShell.ConsoleGuiTools'
    )

    FunctionsToExport    = @(
        'Publish-PSADTIntuneApp'
        'Set-PSADTIntuneConfig'
        'Get-PSADTIntuneConfig'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @('packageIntune', 'PSADTIntune')

    PrivateData          = @{
        PSData = @{
            Tags         = @('Intune', 'PSADT', 'PSAppDeployToolkit', 'Win32', 'IntuneWin', 'Packaging', 'Windows', 'PSEdition_Core')
            LicenseUri   = 'https://github.com/Dzhay/psadt-package-to-intune/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/Dzhay/psadt-package-to-intune'
            ReleaseNotes = 'See https://github.com/Dzhay/psadt-package-to-intune/blob/main/CHANGELOG.md'
        }
    }
}
