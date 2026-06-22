BeforeAll {
    # Stub the Windows Firewall + NetAdapter cmdlets so the source can be
    # dot-sourced and every call Mocked per test. Stubbing them as functions
    # also lets the source run on Linux/Mac CI where the real cmdlets do not
    # exist, and shields a Windows dev box from a unit test mutating real
    # firewall state.
    function Get-NetAdapter         { param($ErrorAction) }
    function Get-NetFirewallRule    { param([string] $DisplayName, $ErrorAction) }
    function Remove-NetFirewallRule { param([string] $DisplayName) }

    . "$PSScriptRoot\..\..\Infrastructure.Network.Windows\Public\Firewall\Remove-RouterSshPortProxyFirewall.ps1"

    function New-WslAdapter {
        [PSCustomObject]@{ Name = 'vEthernet (WSL (Hyper-V firewall))' }
    }
}

Describe 'Remove-RouterSshPortProxyFirewall' {

    Context 'no WSL adapter present' {

        It 'skips removal without erroring' {
            # Real Get-NetAdapter emits nothing (empty pipeline), not $null,
            # on hosts without a WSL adapter - match that.
            Mock Get-NetAdapter         { }
            Mock Get-NetFirewallRule    { }
            Mock Remove-NetFirewallRule { }

            Remove-RouterSshPortProxyFirewall

            Should -Invoke Get-NetFirewallRule    -Times 0
            Should -Invoke Remove-NetFirewallRule -Times 0
        }
    }

    Context 'WSL adapter present, matching rule exists' {

        It 'removes the rule by its port-keyed DisplayName' {
            Mock Get-NetAdapter      { New-WslAdapter }
            Mock Get-NetFirewallRule {
                [PSCustomObject]@{
                    DisplayName = 'Vm-Provisioner: WSL -> router SSH portproxy (TCP/2222)'
                }
            }
            Mock Remove-NetFirewallRule { }

            Remove-RouterSshPortProxyFirewall

            Should -Invoke Remove-NetFirewallRule -Times 1 -Exactly -ParameterFilter {
                $DisplayName -eq 'Vm-Provisioner: WSL -> router SSH portproxy (TCP/2222)'
            }
        }
    }

    Context 'WSL adapter present, no matching rule' {

        It 'does not call Remove-NetFirewallRule (idempotent)' {
            Mock Get-NetAdapter         { New-WslAdapter }
            Mock Get-NetFirewallRule    { $null }
            Mock Remove-NetFirewallRule { }

            Remove-RouterSshPortProxyFirewall

            Should -Invoke Remove-NetFirewallRule -Times 0
        }
    }

    Context 'operator-supplied ListenPort' {

        It 'targets the rule named for that port' {
            Mock Get-NetAdapter      { New-WslAdapter }
            Mock Get-NetFirewallRule {
                [PSCustomObject]@{
                    DisplayName = 'Vm-Provisioner: WSL -> router SSH portproxy (TCP/8222)'
                }
            }
            Mock Remove-NetFirewallRule { }

            Remove-RouterSshPortProxyFirewall -ListenPort 8222

            Should -Invoke Get-NetFirewallRule -Times 1 -Exactly -ParameterFilter {
                $DisplayName -eq 'Vm-Provisioner: WSL -> router SSH portproxy (TCP/8222)'
            }
            Should -Invoke Remove-NetFirewallRule -Times 1 -Exactly -ParameterFilter {
                $DisplayName -eq 'Vm-Provisioner: WSL -> router SSH portproxy (TCP/8222)'
            }
        }
    }
}
