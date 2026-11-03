# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.9.1] - 2026-11-03

### Changed
- The packager's detection row is labelled `Packager (stale)`, with a warning, when `Invoke-AppDeployToolkit.ps1` changed after `PackageInfo.json` was written (its `ScriptHash` no longer matches), and `Packager (not verified)` when `Tests.Verified` is false.

## [0.9.0] - 2026-11-03

### Added
- `PackageInfo.json` (written by PSADT-Packager next to `Invoke-AppDeployToolkit.ps1`) is read when present. Its `Detection` entry becomes the first row of the detection grid (`Packager (tested)`), valid even when the file is not on this machine, and its `Description` is used as the Company Portal description instead of `<Vendor> <App> <Version>` when not empty. A missing file is ignored; invalid JSON gives a warning.
- The detection grid has a `Source` column: `MSI`, `Start Menu` or `Packager (tested)`.
- An `AppIcon.png` in the package folder is used as the app icon.

### Changed
- Icon order: `AppIcon.png` in the package folder, then the icon extracted from the first selected executable, then the PSADT `Assets\AppIcon.png`. The extracted icon now goes to a temporary folder that is removed after the upload (also with `-WhatIf`, when declined and on errors), instead of `AppIcon.png` in the working directory.
- The icon extracted from an executable is its largest icon (up to 256 x 256) instead of 32 x 32.

### Fixed
- When run inside the package folder, the cleanup after the upload deleted the packager's `AppIcon.png`. Only the `.intunewin` is removed now.

## [0.8.1] - 2026-10-07

First release as a PowerShell module (previously the standalone script `packageIntune.ps1`).

### Added
- Module `PSADTIntune` with `Publish-PSADTIntuneApp` (aliases `packageIntune` and `PSADTIntune`), `Set-PSADTIntuneConfig` and `Get-PSADTIntuneConfig`.
- `-Install` (`-i`) and `-Uninstall` (`-u`) install or uninstall the package on this computer with the configured install/uninstall command line. They prompt for elevation when the package requires admin rights.
- Per-user config at `%APPDATA%\PSADTIntune\intune-config.json`, overridable with `-ConfigPath` or `$env:PSADTINTUNE_CONFIG`. Missing keys fall back to the defaults.
- First-run setup: when `packageIntune` runs without a config (or without `TenantId`/`AADClientId`) in an interactive console, it offers to prompt for them and continue, or to open the config file in an editor. Non-interactive sessions still fail with setup instructions.
- `packageIntune -Config` opens the config file in `$env:VISUAL`, `$env:EDITOR` or Notepad, creating it from the defaults if needed.
- `Set-PSADTIntuneConfig` without parameters now also prompts for `TenantId`/`ClientId` when the file exists but they are empty.
- `packageIntune -Help`, comment-based help for all commands, and `Get-Help about_PSADTIntune`.
- `-WhatIf` / `-Confirm` support for all Intune changes.
- `-AppId` now sets the app version to the PSADT `AppVersion` and warns that detection rules are not updated.
- `Set-PSADTIntuneConfig` validates `-Architecture` and `-MinimumWindowsRelease` against the installed IntuneWin32App.
- Pester 5 test suite in `tests/`, run in CI. It needs no tenant and no network access.

### Fixed
- The parameter summary before upload now shows the actual app parameters instead of hashtable internals.
- The upload prompt no longer claims that typing a character deletes the `.intunewin`.
- `-Supersede` now warns when supersedence is skipped because the upload was cancelled.
- Relative `-WorkingDirectory` values such as `.` no longer produce a `..intunewin` file name.
- Detection candidates: shortcuts without a file target, shortcuts to Windows system files (advertised MSI stubs, `msiexec.exe`, `cmd.exe`) and duplicate targets are skipped. Files without version info get an "exists" rule instead of "version equals 0.0.0.0".
- The icon is extracted only from the first selected file, and a failed extraction no longer aborts the run.
- App ID parameters are validated as full GUIDs.

### Changed
- Dependencies are declared in the module manifest instead of being installed silently at runtime.
- Requires PowerShell 7.2+.
