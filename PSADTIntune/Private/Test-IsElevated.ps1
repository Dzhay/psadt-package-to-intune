function Test-IsElevated {
    <#
    .SYNOPSIS
        Returns $true when the current PowerShell session runs elevated (as administrator).
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $principal = [System.Security.Principal.WindowsPrincipal]::new([System.Security.Principal.WindowsIdentity]::GetCurrent())
    $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}
