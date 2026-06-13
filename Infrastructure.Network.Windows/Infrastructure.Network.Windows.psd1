@{
    ModuleVersion        = '0.1.0'
    GUID                 = 'd8b3f5c2-1e47-4f9a-b6d3-7e5a9c2f1b08'
    Author               = 'Vitaly Andrev'
    Description          = 'Windows host network utilities for infrastructure repos (ICS, netsh portproxy, firewall, network profile, DNS).'
    PowerShellVersion    = '7.0'
    CompatiblePSEditions = @('Core')
    RootModule        = 'Infrastructure.Network.Windows.psm1'

    RequiredModules = @(
    )

    FunctionsToExport = @(
    )
    CmdletsToExport   = @()
    AliasesToExport   = @()
}
