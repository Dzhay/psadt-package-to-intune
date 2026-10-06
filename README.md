# PSADTIntune

PowerShell module that packages [PSAppDeployToolkit](https://psappdeploytoolkit.com) (PSADT) v4 applications as `.intunewin` and creates, updates or supersedes them as Win32 apps in Microsoft Intune.

```powershell
packageIntune -i                     # install the PSADT app in this folder on this computer
packageIntune                        # package it and create a new Intune app
packageIntune -AppId <app-guid>      # replace the package of an existing app
packageIntune -Supersede <app-guid>  # create a new app that supersedes an existing one
packageIntune -u                     # uninstall it from this computer
```

`PSADTIntune` works the same as `packageIntune`: both are aliases of `Publish-PSADTIntuneApp`.

> **Test in a non-production tenant first.** This tool creates and modifies Intune apps and assignments.

## Requirements

- Windows with **PowerShell 7.2+**. The tool uses WScript.Shell, System.Drawing and Start Menu paths.
- Modules [IntuneWin32App](https://www.powershellgallery.com/packages/IntuneWin32App) (1.4.4+) and [Microsoft.PowerShell.ConsoleGuiTools](https://www.powershellgallery.com/packages/Microsoft.PowerShell.ConsoleGuiTools). `Install-Module` installs them automatically.
- An Entra ID app registration. See [Permissions](#permissions).

## Installation

From the PowerShell Gallery:

```powershell
Install-Module PSADTIntune -Scope CurrentUser
```

Or from a clone of this repo:

```powershell
Install-Module IntuneWin32App, Microsoft.PowerShell.ConsoleGuiTools -Scope CurrentUser
Import-Module .\PSADTIntune\PSADTIntune.psd1
```

## Setup

Configure your tenant and app registration once per user:

```powershell
Set-PSADTIntuneConfig -TenantId 'contoso.onmicrosoft.com' -ClientId 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'

# optional settings
Set-PSADTIntuneConfig -AADGroupId '11111111-2222-3333-4444-555555555555' -Owner 'Workplace Team' -ScopeTag 'Default'

# show the effective settings and where they are stored
Get-PSADTIntuneConfig
```

Run `Set-PSADTIntuneConfig` with no parameters to be prompted for the tenant and client ID.

### Where settings are stored

Settings live in a JSON file outside the module folder, so they survive `Update-Module`. The file is chosen in this order:

1. `-ConfigPath <file>` parameter
2. `$env:PSADTINTUNE_CONFIG` environment variable
3. `%APPDATA%\PSADTIntune\intune-config.json` (default)

Keys missing from your file fall back to the defaults in [PSADTIntune/intune-config.json](PSADTIntune/intune-config.json).

| JSON key | `Set-PSADTIntuneConfig` | Default | Description |
|---|---|---|---|
| `TenantId` | `-TenantId` | *(required)* | Tenant name or ID, e.g. `contoso.onmicrosoft.com` |
| `AADClientId` | `-ClientId` | *(required)* | App registration (client) ID |
| `Params.Owner` | `-Owner` | *(empty)* | Owner shown on the Intune app |
| `Params.AADGroupId` | `-AADGroupId` | *(none)* | Group assigned as **Available** after upload |
| `Params.ScopeTagNameArray` | `-ScopeTag` | `["Default"]` | Intune scope tags |
| `Params.Architecture` | `-Architecture` | `x64` | Requirement rule architecture |
| `Params.MinimumWindowsRelease` | `-MinimumWindowsRelease` | `W11_22H2` | Minimum Windows release |
| `Params.InstallCommandLine` | `-InstallCommandLine` | PSADT v4 install, `-DeployMode Auto` | Install command, in Intune and for `-i` |
| `Params.UninstallCommandLine` | `-UninstallCommandLine` | PSADT v4 uninstall, `-DeployMode Auto` | Uninstall command, in Intune and for `-u` |

## Usage

### Folder structure

Run in a folder that contains one PSADT package folder, or inside the package folder itself:

```
Contoso_Example_App/                  <- run here ...
└── Contoso_Example_App_Package/      <- ... or here (PSADT v4 package)
    ├── Invoke-AppDeployToolkit.ps1
    ├── Invoke-AppDeployToolkit.exe
    └── Files/ ...
```

`AppName`, `AppVersion`, `AppVendor` and `RequireAdmin` are read from the `$adtSession` block in `Invoke-AppDeployToolkit.ps1`. `RequireAdmin` selects system or user install context.

### Install or uninstall on this computer

```powershell
packageIntune -Install     # or -i
packageIntune -Uninstall   # or -u
```

These run the configured `InstallCommandLine` / `UninstallCommandLine` in the PSADT package folder, the same command Intune runs. Nothing is packaged or uploaded, and no Intune sign-in is needed. Without a config file, the defaults are used.
- **Elevation:** if the package has `RequireAdmin = $true` and PowerShell isn't elevated, you get a UAC prompt.
- **Exit codes:** 0, 1641 and 3010 count as success. 1641 and 3010 also mean a restart is required.
- **Why install first:** the detection rules come from Start Menu shortcuts on this computer, so install before packaging.

Intune runs system installs as SYSTEM, while `-i` runs them as you (elevated). For a SYSTEM-context test, use a tool like PsExec.

### Create a new app

```powershell
packageIntune
packageIntune -WorkingDirectory 'C:\Packages\Contoso_Example_App'
```

1. **Packaging**: creates `<PackageFolder>.intunewin`, or offers to reuse an existing one.
2. **Detection rules**: a grid lists MSI product codes found under `Files\` and the targets of the 15 most recent Start Menu shortcuts **on this machine**, skipping shortcuts to files under `C:\Windows`. Install the app locally first (`packageIntune -i`). Select one or more. If you select nothing, a *PLACEHOLDER* rule is added, and you must fix it in Intune.
3. **Review & confirm**: all app parameters are shown before anything is uploaded.
4. **Upload**: creates the Win32 app. The icon comes from the selected executable, or the PSADT `Assets\AppIcon.png` as a fallback.
5. **Assignment**: if `AADGroupId` is set, the app is assigned to it as Available.

### Update an existing app

```powershell
packageIntune -AppId 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
```

Replaces the app's package content and sets its version to the PSADT `AppVersion`. Detection rules, assignments and other settings are **not** changed. If the app uses a version-based detection rule, update that rule in Intune or use `-Supersede` instead.

### Supersede an existing app

```powershell
packageIntune -Supersede 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
```

1. Runs the full new-app flow.
2. Copies the old app's **display name** and **description** to the new app.
3. Adds **Update** supersedence over the old app.
4. Adds every group assigned to the old app as an **Exclude** assignment, keeping each group's intent, so existing users aren't affected yet. *All Users* / *All Devices* assignments can't be excluded and are skipped with a warning.
5. Assigns `AADGroupId` as **Available (Include)** for testing.

Remove the exclusions when you're ready to roll out.

### Other options

| Option | Effect |
|---|---|
| `-WhatIf` | Builds the package and shows what would be uploaded, without changing Intune. With `-i`/`-u`, shows what would run |
| `-Confirm:$false` | Skips the confirmation prompt |
| `-ConfigPath <file>` | Uses a specific config file |
| `-Help` | Shows a quick-start and which config file is in use |

## Help

```powershell
packageIntune -Help                    # quick-start + config status
Get-Help about_PSADTIntune             # full guide
Get-Help packageIntune -Examples
Get-Help Set-PSADTIntuneConfig -Full
```

## Permissions

Sign-in is interactive (delegated) through IntuneWin32App's `Connect-MSIntuneGraph`. Create an Entra ID app registration with:

- Platform **Mobile and desktop applications** with redirect URI `http://localhost`
- **Allow public client flows** enabled
- Delegated Microsoft Graph permissions, with admin consent as your tenant requires:
  - `DeviceManagementApps.ReadWrite.All`
  - `DeviceManagementConfiguration.ReadWrite.All`
  - `DeviceManagementRBAC.Read.All`
  - `Group.Read.All`

The signed-in user also needs an Intune role that allows managing apps.

## Troubleshooting

| Problem | Solution |
|---|---|
| `No PSADTIntune config found` | Run `Set-PSADTIntuneConfig`; `Get-PSADTIntuneConfig` shows the expected path |
| `Could not extract AppName` | The `$adtSession` block must contain `AppName = 'YourApp'` |
| `No PSADT v4 script found` | `Invoke-AppDeployToolkit.ps1` must be in the package folder |
| `Multiple .intunewin files` | Remove extra `.intunewin` files from the working directory |
| No useful detection candidates | Install the app on this machine first and check its Start Menu shortcut |
| Grid view doesn't open | Use a PowerShell 7 console (Windows Terminal / VS Code), not the ISE |

## Development

Run the Pester 5 test suite from the repo root:

```powershell
Install-PSResource Pester, PSScriptAnalyzer -Scope CurrentUser   # once
Invoke-Pester ./tests -Output Detailed
```

The tests mock all Intune/Graph calls and the detection-rule grid, so they need no tenant and no network access. They also run PSScriptAnalyzer and check that every IntuneWin32App parameter the module uses still exists in the installed version. CI runs the same suite on every push and pull request.

## Credits

- [IntuneWin32App](https://github.com/MSEndpointMgr/IntuneWin32App) by Nickolaj Andersen (MSEndpointMgr) does all the Intune/Graph work.
- [PSAppDeployToolkit](https://psappdeploytoolkit.com).
- The icon extraction is adapted from [Extracting Icons with PowerShell](https://jdhitsolutions.com/blog/powershell/7931/extracting-icons-with-powershell/) by Jeff Hicks.

## License

[MIT](LICENSE)
