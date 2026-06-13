@{
    ModuleVersion        = '0.1.0'
    GUID                 = 'd8b3f5c2-1e47-4f9a-b6d3-7e5a9c2f1b08'
    Author               = 'Vitaly Andrev'
    Description          = 'Windows host network utilities for infrastructure repos (ICS, netsh portproxy, firewall, network profile, DNS).'
    PowerShellVersion    = '7.0'
    CompatiblePSEditions = @('Core')
    RootModule        = 'Infrastructure.Network.Windows.psm1'

    # RequiredModules declares load-time dependencies so consumers do
    # not have to know to Import-Module them by hand. Infrastructure.Wsl
    # is required because Test-WslRouterReachability calls
    # Invoke-WslShell - PowerShell auto-imports the listed module when
    # this one loads.
    RequiredModules = @(
        @{
            ModuleName    = 'Infrastructure.Wsl'
            ModuleVersion = '0.1.0'
        }
    )

    # FunctionsToExport is module discovery metadata: used by
    # Get-Module -ListAvailable, Find-Module, and PSGallery without loading
    # the module. It does NOT control what is callable at runtime - that is
    # governed by Export-ModuleMember in the psm1, which takes precedence.
    # Both lists must stay in sync. The shared Module.Tests.ps1 in the
    # run-unit-tests action enforces this.
    FunctionsToExport = @(
        # ICS (Internet Connection Sharing) - host-side toggling +
        # DNS-via-ICS probes.
        'Reset-IcsSharing',
        'Test-IcsDnsReachable',
        'Test-IcsDnsProxyReachable',
        # netsh portproxy - localhost:port -> remote:port forwarding,
        # used to make Hyper-V Internal-switch IPs reachable from WSL.
        'Get-NetshPortProxyRules',
        'Set-RouterSshPortProxy',
        # Windows Firewall companion for the portproxy.
        'Set-RouterSshPortProxyFirewall',
        # Network profile (Public / Private / Domain) on a host
        # interface. The preflight wraps this for vEthernet adapters.
        'Test-HostNetworkProfileSetting',
        # Reachability probes that run from WSL through the host
        # portproxy. Lives here because the concern is network
        # reachability; WSL is just the execution side.
        'Test-WslRouterReachability'
    )
    CmdletsToExport   = @()
    AliasesToExport   = @()
}
