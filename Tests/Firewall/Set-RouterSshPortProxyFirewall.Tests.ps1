BeforeAll {
    # Stub the Windows Firewall + NetAdapter cmdlets (both the Defender
    # and the Hyper-V Firewall families) so the source can be
    # dot-sourced and every call Mocked per test. Stubbing the Hyper-V
    # cmdlets as functions is load-bearing twice over: it lets the
    # source run on Linux/Mac CI where those cmdlets do not exist, AND
    # it shields a Windows dev box that DOES have them from a unit test
    # mutating real firewall state.
    function Get-NetAdapter        { param($ErrorAction) }
    function Get-NetFirewallRule   { param([string] $DisplayName, $ErrorAction) }
    function New-NetFirewallRule {
        param(
            [string] $DisplayName,
            [string] $Direction,
            [int]    $LocalPort,
            [string] $Protocol,
            [string] $Action,
            [string] $InterfaceAlias
        )
    }
    function Get-NetFirewallHyperVVMSetting { param([string] $Name, $ErrorAction) }
    function Get-NetFirewallHyperVRule      { param([string] $Name, $ErrorAction) }
    function New-NetFirewallHyperVRule {
        param(
            [string] $Name,
            [string] $DisplayName,
            [string] $Direction,
            [string] $VMCreatorId,
            [string] $Protocol,
            [int]    $LocalPorts,
            [string] $Action
        )
    }

    . "$PSScriptRoot\..\..\Infrastructure.Network.Windows\Public\Firewall\Set-RouterSshPortProxyFirewall.ps1"

    function New-WslAdapter {
        [PSCustomObject]@{ Name = 'vEthernet (WSL (Hyper-V firewall))' }
    }

    # The well-known WSL VM-creator id the source scopes engine 2 to.
    $script:wslVmCreatorId = '{40E0AC32-46A5-438A-A0B2-2B479E8F2E90}'
}

Describe 'Set-RouterSshPortProxyFirewall' {

    # -------------------------------------------------------------------
    # Engine 1: Windows Defender Firewall (older NAT-mode WSL). The
    # Hyper-V engine is pinned to a no-op in this block (no VM-creator
    # setting) so the assertions isolate the Defender path.
    # -------------------------------------------------------------------
    Context 'Defender firewall (NAT-mode WSL)' {

        BeforeEach {
            # Engine 2 returns early at the VM-creator check, so it never
            # touches New-NetFirewallHyperVRule in these Defender tests.
            Mock Get-NetFirewallHyperVVMSetting { $null }
            Mock New-NetFirewallHyperVRule      { }
        }

        It 'skips the rule add without erroring when no WSL adapter is present' {
            # Real Get-NetAdapter emits nothing (empty pipeline) on
            # hosts without a WSL adapter - not $null. Match that.
            Mock Get-NetAdapter { }
            Mock New-NetFirewallRule { }

            Set-RouterSshPortProxyFirewall

            Should -Invoke New-NetFirewallRule -Times 0
        }

        It 'creates an inbound TCP allow rule scoped to the WSL adapter' {
            Mock Get-NetAdapter      { New-WslAdapter }
            Mock Get-NetFirewallRule { $null }
            Mock New-NetFirewallRule { }

            Set-RouterSshPortProxyFirewall

            Should -Invoke New-NetFirewallRule -Times 1 -Exactly -ParameterFilter {
                $Direction      -eq 'Inbound'     -and
                $LocalPort      -eq 2222          -and
                $Protocol       -eq 'TCP'         -and
                $Action         -eq 'Allow'       -and
                $InterfaceAlias -eq 'vEthernet (WSL (Hyper-V firewall))'
            }
        }

        It 'passes the operator-supplied ListenPort through' {
            Mock Get-NetAdapter      { New-WslAdapter }
            Mock Get-NetFirewallRule { $null }
            Mock New-NetFirewallRule { }

            Set-RouterSshPortProxyFirewall -ListenPort 8222

            Should -Invoke New-NetFirewallRule -Times 1 -Exactly -ParameterFilter {
                $LocalPort -eq 8222
            }
        }

        It 'skips the add when a matching rule already exists (idempotency)' {
            Mock Get-NetAdapter      { New-WslAdapter }
            Mock Get-NetFirewallRule {
                [PSCustomObject]@{
                    DisplayName = 'Vm-Provisioner: WSL -> router SSH portproxy (TCP/2222)'
                }
            }
            Mock New-NetFirewallRule { }

            Set-RouterSshPortProxyFirewall

            Should -Invoke New-NetFirewallRule -Times 0
        }
    }

    # -------------------------------------------------------------------
    # Engine 2: Hyper-V Firewall (Windows 11 Hyper-V-firewall-mode WSL).
    # The Defender engine is pinned to a no-op (no WSL adapter) so the
    # assertions isolate the Hyper-V path.
    # -------------------------------------------------------------------
    Context 'Hyper-V firewall (Hyper-V-firewall-mode WSL)' {

        BeforeEach {
            # No WSL adapter -> engine 1 no-ops before any Defender call.
            Mock Get-NetAdapter      { }
            Mock New-NetFirewallRule { }
        }

        It 'skips when the Hyper-V firewall cmdlet is unavailable (down-level Windows)' {
            # Simulate a host without the feature: Get-Command finds no
            # New-NetFirewallHyperVRule. Scope the mock to that name so
            # Pester's own Get-Command calls fall through untouched.
            Mock Get-Command { $null } -ParameterFilter {
                $Name -eq 'New-NetFirewallHyperVRule'
            }
            Mock Get-NetFirewallHyperVVMSetting { [PSCustomObject]@{ Name = $wslVmCreatorId } }
            Mock New-NetFirewallHyperVRule { }

            Set-RouterSshPortProxyFirewall

            Should -Invoke New-NetFirewallHyperVRule -Times 0
        }

        It 'skips when no WSL VM-creator setting is present (WSL not in Hyper-V firewall mode)' {
            Mock Get-NetFirewallHyperVVMSetting { $null }
            Mock New-NetFirewallHyperVRule      { }

            Set-RouterSshPortProxyFirewall

            Should -Invoke New-NetFirewallHyperVRule -Times 0
        }

        It 'creates an inbound TCP allow rule scoped to the WSL VM-creator id' {
            Mock Get-NetFirewallHyperVVMSetting { [PSCustomObject]@{ Name = $wslVmCreatorId } }
            Mock Get-NetFirewallHyperVRule      { $null }
            Mock New-NetFirewallHyperVRule      { }

            Set-RouterSshPortProxyFirewall

            Should -Invoke New-NetFirewallHyperVRule -Times 1 -Exactly -ParameterFilter {
                $Name        -eq 'VmProvisioner-WSL-RouterSshPortproxy-2222' -and
                $Direction   -eq 'Inbound'                                   -and
                $VMCreatorId -eq $wslVmCreatorId                             -and
                $Protocol    -eq 'TCP'                                       -and
                $LocalPorts  -eq 2222                                        -and
                $Action      -eq 'Allow'
            }
        }

        It 'passes the operator-supplied ListenPort through to the rule name and port' {
            Mock Get-NetFirewallHyperVVMSetting { [PSCustomObject]@{ Name = $wslVmCreatorId } }
            Mock Get-NetFirewallHyperVRule      { $null }
            Mock New-NetFirewallHyperVRule      { }

            Set-RouterSshPortProxyFirewall -ListenPort 8222

            Should -Invoke New-NetFirewallHyperVRule -Times 1 -Exactly -ParameterFilter {
                $Name       -eq 'VmProvisioner-WSL-RouterSshPortproxy-8222' -and
                $LocalPorts -eq 8222
            }
        }

        It 'skips the add when a matching Hyper-V rule already exists (idempotency)' {
            Mock Get-NetFirewallHyperVVMSetting { [PSCustomObject]@{ Name = $wslVmCreatorId } }
            Mock Get-NetFirewallHyperVRule {
                [PSCustomObject]@{ Name = 'VmProvisioner-WSL-RouterSshPortproxy-2222' }
            }
            Mock New-NetFirewallHyperVRule { }

            Set-RouterSshPortProxyFirewall

            Should -Invoke New-NetFirewallHyperVRule -Times 0
        }
    }
}
