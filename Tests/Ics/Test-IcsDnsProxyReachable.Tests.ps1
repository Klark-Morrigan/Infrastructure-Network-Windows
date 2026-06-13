BeforeAll {
    function Test-IcsDnsReachable { param([string] $Server) }
    function Reset-IcsSharing     { param([string] $WanInterfaceName, [string] $LanInterfaceName) }

    . "$PSScriptRoot\..\..\Infrastructure.Network.Windows\Public\Ics\Test-IcsDnsProxyReachable.ps1"
}

Describe 'Test-IcsDnsProxyReachable' {

    Context 'happy path' {

        It 'returns PASS without auto-repair when the first probe succeeds' {
            Mock Test-IcsDnsReachable { $true }
            Mock Reset-IcsSharing { }

            $result = Test-IcsDnsProxyReachable `
                -DnsProbeTarget  '192.168.137.1' `
                -LanAdapterName  'vEthernet (Shared)' `
                -WanAdapterName  'Wi-Fi'

            $result.Status | Should -Be 'PASS'
            Should -Invoke Reset-IcsSharing -Times 0
        }
    }

    Context 'one-shot auto-repair' {

        It 'kicks Reset-IcsSharing then re-probes when the first call fails' {
            $script:probeCalls = 0
            Mock Test-IcsDnsReachable {
                $script:probeCalls++
                $script:probeCalls -gt 1   # fail first call, succeed second
            }
            Mock Reset-IcsSharing { }

            $result = Test-IcsDnsProxyReachable `
                -DnsProbeTarget  '192.168.137.1' `
                -LanAdapterName  'vEthernet (Shared)' `
                -WanAdapterName  'Wi-Fi'

            $result.Status | Should -Be 'PASS'
            $result.Label  | Should -Match 'auto-repaired'
            Should -Invoke Reset-IcsSharing -Times 1 -Exactly -ParameterFilter {
                $WanInterfaceName -eq 'Wi-Fi' -and
                $LanInterfaceName -eq 'vEthernet (Shared)'
            }
            $script:probeCalls | Should -Be 2
        }

        It 'reports FAIL when the re-probe also fails - no retry loop' {
            Mock Test-IcsDnsReachable { $false }
            Mock Reset-IcsSharing { }

            $result = Test-IcsDnsProxyReachable `
                -DnsProbeTarget  '192.168.137.1' `
                -LanAdapterName  'vEthernet (Shared)' `
                -WanAdapterName  'Wi-Fi'

            $result.Status | Should -Be 'FAIL'
            Should -Invoke Reset-IcsSharing -Times 1
        }

        It 'reports FAIL when Reset-IcsSharing itself throws' {
            Mock Test-IcsDnsReachable { $false }
            Mock Reset-IcsSharing { throw 'HNetCfg COM error' }

            $result = Test-IcsDnsProxyReachable `
                -DnsProbeTarget  '192.168.137.1' `
                -LanAdapterName  'vEthernet (Shared)' `
                -WanAdapterName  'Wi-Fi'

            $result.Status | Should -Be 'FAIL'
            $result.Detail | Should -Match 'HNetCfg COM error'
        }
    }

    Context '-NoAutoRepair / missing WAN' {

        It 'reports FAIL without invoking Reset-IcsSharing when -NoAutoRepair is set' {
            Mock Test-IcsDnsReachable { $false }
            Mock Reset-IcsSharing { }

            $result = Test-IcsDnsProxyReachable `
                -DnsProbeTarget  '192.168.137.1' `
                -LanAdapterName  'vEthernet (Shared)' `
                -WanAdapterName  'Wi-Fi' `
                -NoAutoRepair

            $result.Status | Should -Be 'FAIL'
            Should -Invoke Reset-IcsSharing -Times 0
        }

        It 'reports FAIL without auto-repair when WanAdapterName is unset' {
            Mock Test-IcsDnsReachable { $false }
            Mock Reset-IcsSharing { }

            $result = Test-IcsDnsProxyReachable `
                -DnsProbeTarget  '192.168.137.1' `
                -LanAdapterName  'vEthernet (Shared)'

            $result.Status | Should -Be 'FAIL'
            Should -Invoke Reset-IcsSharing -Times 0
        }
    }
}
