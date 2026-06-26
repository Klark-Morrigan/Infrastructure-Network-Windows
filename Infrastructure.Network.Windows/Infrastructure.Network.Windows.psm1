<#
.SYNOPSIS
    Windows host network utilities for infrastructure repos.

.DESCRIPTION
    Provides Windows-specific networking helpers. Underlying primitives
    (netsh, HNetCfg, Get-NetFirewallRule, Get-NetConnectionProfile,
    Resolve-DnsName) do not exist on other platforms.

    Subdomains:
      - Adapter/    - Physical NIC identification (wireless detection)
      - Ics/        - Internet Connection Sharing toggle + DNS probes
      - Portproxy/  - netsh portproxy parser + idempotent add/replace
      - Firewall/   - Windows Firewall companion for portproxy
      - Relay/      - portproxy + firewall composed as one pair
      - Profile/    - Network profile (Public/Private/Domain) on a NIC
      - Probes/     - WSL-side network reachability probes
                      (depends on Infrastructure.Wsl for Invoke-WslShell)

    Each function lives in its own file under Public\<subdomain>\ and
    is dot-sourced below so diffs stay focused on a single function
    per commit.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\Public\Adapter\Get-WirelessNetAdapter.ps1"
. "$PSScriptRoot\Public\Ics\Get-IcsDnsFailureDiagnostics.ps1"
. "$PSScriptRoot\Public\Ics\Reset-IcsSharing.ps1"
. "$PSScriptRoot\Public\Ics\Test-HostDnsReachable.ps1"
. "$PSScriptRoot\Public\Ics\Test-IcsDnsProxyReachable.ps1"
. "$PSScriptRoot\Public\Ics\Test-IcsDnsReachable.ps1"
. "$PSScriptRoot\Public\Portproxy\Get-NetshPortProxyRules.ps1"
. "$PSScriptRoot\Public\Portproxy\Remove-RouterSshPortProxy.ps1"
. "$PSScriptRoot\Public\Portproxy\Set-RouterSshPortProxy.ps1"
. "$PSScriptRoot\Public\Firewall\Remove-RouterSshPortProxyFirewall.ps1"
. "$PSScriptRoot\Public\Firewall\Set-RouterSshPortProxyFirewall.ps1"
. "$PSScriptRoot\Public\Relay\Remove-RouterSshRelay.ps1"
. "$PSScriptRoot\Public\Relay\Set-RouterSshRelay.ps1"
. "$PSScriptRoot\Public\Profile\Test-HostNetworkProfileSetting.ps1"
. "$PSScriptRoot\Public\Probes\Test-WslRouterReachability.ps1"

# Export-ModuleMember controls what is actually callable after Import-Module.
# It takes precedence over FunctionsToExport in the psd1 at runtime, so both
# must be kept in sync. FunctionsToExport serves a separate purpose: it is
# read by Get-Module -ListAvailable, Find-Module, and PSGallery for fast
# discovery without loading the module. The shared Module.Tests.ps1 in the
# run-unit-tests action enforces that every Public\*.ps1 file appears in both.
Export-ModuleMember -Function @(
    'Get-IcsDnsFailureDiagnostics',
    'Get-NetshPortProxyRules',
    'Get-WirelessNetAdapter',
    'Remove-RouterSshPortProxy',
    'Remove-RouterSshPortProxyFirewall',
    'Remove-RouterSshRelay',
    'Reset-IcsSharing',
    'Set-RouterSshPortProxy',
    'Set-RouterSshPortProxyFirewall',
    'Set-RouterSshRelay',
    'Test-HostDnsReachable',
    'Test-HostNetworkProfileSetting',
    'Test-IcsDnsProxyReachable',
    'Test-IcsDnsReachable',
    'Test-WslRouterReachability'
)
