<#
.SYNOPSIS
    Windows host network utilities for infrastructure repos.

.DESCRIPTION
    Provides Windows-specific networking helpers. Underlying primitives
    (netsh, HNetCfg, Get-NetFirewallRule, Get-NetConnectionProfile,
    Resolve-DnsName) do not exist on other platforms.

    Subdomains:
      - Firewall/   - Windows Firewall companion for portproxy

    Each function lives in its own file under Public\<subdomain>\ and
    is dot-sourced below so diffs stay focused on a single function
    per commit.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\Public\Firewall\Set-RouterSshPortProxyFirewall.ps1"

# Export-ModuleMember controls what is actually callable after Import-Module.
# It takes precedence over FunctionsToExport in the psd1 at runtime, so both
# must be kept in sync. FunctionsToExport serves a separate purpose: it is
# read by Get-Module -ListAvailable, Find-Module, and PSGallery for fast
# discovery without loading the module. The shared Module.Tests.ps1 in the
# run-unit-tests action enforces that every Public\*.ps1 file appears in both.
Export-ModuleMember -Function @(
    'Set-RouterSshPortProxyFirewall',
)
