BeforeAll {
    function Test-IcsDnsReachable { param([string] $Server) }
    function Reset-IcsSharing     { param([string] $WanInterfaceName, [string] $LanInterfaceName) }
    # Stubbed so the terminal-FAIL path is tested in isolation from the
    # diagnostics internals (those have their own dedicated suite).
    function Get-IcsDnsFailureDiagnostics {
        param([string] $DnsProbeTarget, [string] $WanAdapterName, [string] $LanAdapterName)
    }

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
            Mock Get-IcsDnsFailureDiagnostics { 'DIAGNOSTIC-VERDICT' }

            $result = Test-IcsDnsProxyReachable `
                -DnsProbeTarget  '192.168.137.1' `
                -LanAdapterName  'vEthernet (Shared)' `
                -WanAdapterName  'Wi-Fi'

            $result.Status | Should -Be 'FAIL'
            Should -Invoke Reset-IcsSharing -Times 1
        }

        It 'folds the failure diagnostics into the terminal FAIL detail' {
            Mock Test-IcsDnsReachable { $false }
            Mock Reset-IcsSharing { }
            Mock Get-IcsDnsFailureDiagnostics { 'DIAGNOSTIC-VERDICT' }

            $result = Test-IcsDnsProxyReachable `
                -DnsProbeTarget  '192.168.137.1' `
                -LanAdapterName  'vEthernet (Shared)' `
                -WanAdapterName  'Wi-Fi'

            $result.Detail | Should -Match 'DIAGNOSTIC-VERDICT'
            Should -Invoke Get-IcsDnsFailureDiagnostics -Times 1 -Exactly `
                -ParameterFilter {
                    $DnsProbeTarget -eq '192.168.137.1'      -and
                    $WanAdapterName -eq 'Wi-Fi'              -and
                    $LanAdapterName -eq 'vEthernet (Shared)'
                }
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
            Mock Get-IcsDnsFailureDiagnostics { 'DIAGNOSTIC-VERDICT' }

            $result = Test-IcsDnsProxyReachable `
                -DnsProbeTarget  '192.168.137.1' `
                -LanAdapterName  'vEthernet (Shared)' `
                -WanAdapterName  'Wi-Fi' `
                -NoAutoRepair

            $result.Status | Should -Be 'FAIL'
            Should -Invoke Reset-IcsSharing -Times 0
        }

        It 'folds the same diagnostics into the skipped-repair FAIL detail' {
            Mock Test-IcsDnsReachable { $false }
            Mock Reset-IcsSharing { }
            Mock Get-IcsDnsFailureDiagnostics { 'DIAGNOSTIC-VERDICT' }

            $result = Test-IcsDnsProxyReachable `
                -DnsProbeTarget  '192.168.137.1' `
                -LanAdapterName  'vEthernet (Shared)' `
                -WanAdapterName  'Wi-Fi' `
                -NoAutoRepair

            $result.Detail | Should -Match 'NoAutoRepair'
            $result.Detail | Should -Match 'DIAGNOSTIC-VERDICT'
            Should -Invoke Get-IcsDnsFailureDiagnostics -Times 1 -Exactly `
                -ParameterFilter { $WanAdapterName -eq 'Wi-Fi' }
        }

        It 'reports FAIL without auto-repair when WanAdapterName is unset' {
            Mock Test-IcsDnsReachable { $false }
            Mock Reset-IcsSharing { }
            Mock Get-IcsDnsFailureDiagnostics { 'DIAGNOSTIC-VERDICT' }

            $result = Test-IcsDnsProxyReachable `
                -DnsProbeTarget  '192.168.137.1' `
                -LanAdapterName  'vEthernet (Shared)'

            $result.Status | Should -Be 'FAIL'
            Should -Invoke Reset-IcsSharing -Times 0
        }
    }
}
