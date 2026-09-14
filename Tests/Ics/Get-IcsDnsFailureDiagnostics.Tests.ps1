BeforeAll {
    # Get-Service is Windows-only and Test-HostDnsReachable hits the
    # network; stub both so the verdict logic is tested deterministically
    # on any runner.
    function Get-Service {
        # Suppressed inline (not fleet-wide) so the rule still guards
        # production code against clobbering a built-in.
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            'PSAvoidOverwritingBuiltInCmdlets', '',
            Justification = 'Intentional in-scope test double for Get-Service.')]
        param([string] $Name, $ErrorAction)
    }
    function Test-HostDnsReachable { }

    . "$PSScriptRoot\..\..\Infrastructure.Network.Windows\Public\Ics\Get-IcsDnsFailureDiagnostics.ps1"
}

Describe 'Get-IcsDnsFailureDiagnostics' {

    Context 'SharedAccess service is not Running' {

        It 'names Start-Service as the fix and skips the proxy-wedged verdict' {
            Mock Get-Service { [PSCustomObject]@{ Status = 'Stopped' } }
            Mock Test-HostDnsReachable { $true }   # irrelevant - service wins

            $detail = Get-IcsDnsFailureDiagnostics -DnsProbeTarget '192.168.137.1'

            $detail | Should -Match 'SharedAccess=Stopped'
            $detail | Should -Match 'Start-Service SharedAccess'
            $detail | Should -Not -Match 'proxy is wedged'
        }

        It 'ends the command list with the re-probe against the target' {
            Mock Get-Service { [PSCustomObject]@{ Status = 'Stopped' } }
            Mock Test-HostDnsReachable { $true }

            $lines = (Get-IcsDnsFailureDiagnostics -DnsProbeTarget '192.168.137.1') -split "`n"

            $lines[-1].Trim() |
                Should -Be 'Resolve-DnsName archive.ubuntu.com -Server 192.168.137.1 -DnsOnly'
        }

        It 'reports ''not found'' when the service is absent' {
            Mock Get-Service { $null }
            Mock Test-HostDnsReachable { $true }

            $detail = Get-IcsDnsFailureDiagnostics -DnsProbeTarget '192.168.137.1'

            $detail | Should -Match 'SharedAccess=not found'
            $detail | Should -Match 'Start-Service SharedAccess'
        }
    }

    Context 'service Running but host upstream DNS is also dead' {

        It 'blames the host network, not ICS' {
            Mock Get-Service { [PSCustomObject]@{ Status = 'Running' } }
            Mock Test-HostDnsReachable { $false }

            $detail = Get-IcsDnsFailureDiagnostics -DnsProbeTarget '192.168.137.1'

            $detail | Should -Match 'host upstream DNS=FAIL'
            $detail | Should -Match 'not ICS'
            $detail | Should -Not -Match 'Start-Service'
        }

        It 'lists host-side probes and never the ICS toggle' {
            Mock Get-Service { [PSCustomObject]@{ Status = 'Running' } }
            Mock Test-HostDnsReachable { $false }

            $detail = Get-IcsDnsFailureDiagnostics -DnsProbeTarget '192.168.137.1' `
                                                   -WanAdapterName 'Wi-Fi' `
                                                   -LanAdapterName 'vEthernet (Shared)'

            $detail | Should -Match 'Get-NetConnectionProfile'
            $detail | Should -Match 'Get-DnsClientServerAddress'
            $detail | Should -Not -Match 'Reset-IcsSharing'
        }
    }

    Context 'service Running and host DNS fine - proxy itself wedged' {

        It 'points at restart + reboot and echoes the probe target' {
            Mock Get-Service { [PSCustomObject]@{ Status = 'Running' } }
            Mock Test-HostDnsReachable { $true }

            $detail = Get-IcsDnsFailureDiagnostics -DnsProbeTarget '10.20.30.40'

            $detail | Should -Match 'SharedAccess=Running'
            $detail | Should -Match 'host upstream DNS=OK'
            $detail | Should -Match 'proxy at 10\.20\.30\.40 does not answer'
            $detail | Should -Match 'Restart-Service SharedAccess'
            $detail | Should -Match 'Restart-Computer'
        }

        It 'builds the Reset-IcsSharing example from the supplied adapter names' {
            Mock Get-Service { [PSCustomObject]@{ Status = 'Running' } }
            Mock Test-HostDnsReachable { $true }

            $detail = Get-IcsDnsFailureDiagnostics -DnsProbeTarget '192.168.137.1' `
                                                   -WanAdapterName 'Wi-Fi' `
                                                   -LanAdapterName 'vEthernet (Shared)'

            $detail | Should -Match ([regex]::Escape(
                "Reset-IcsSharing -WanInterfaceName 'Wi-Fi' -LanInterfaceName 'vEthernet (Shared)'"))
            $detail | Should -Not -Match 'Get-NetAdapter'
        }

        It 'falls back to placeholders plus a Get-NetAdapter hint without adapter names' {
            Mock Get-Service { [PSCustomObject]@{ Status = 'Running' } }
            Mock Test-HostDnsReachable { $true }

            $detail = Get-IcsDnsFailureDiagnostics -DnsProbeTarget '192.168.137.1'

            $detail | Should -Match 'Reset-IcsSharing -WanInterfaceName'
            $detail | Should -Match 'Get-NetAdapter'
        }

        It 'puts every command on its own line' {
            Mock Get-Service { [PSCustomObject]@{ Status = 'Running' } }
            Mock Test-HostDnsReachable { $true }

            $lines = (Get-IcsDnsFailureDiagnostics -DnsProbeTarget '192.168.137.1') -split "`n"

            # Verdict prose, then one line each for restart / reset / probe / reboot.
            $lines.Count | Should -Be 5
            @($lines | Select-Object -Skip 1) |
                ForEach-Object { $_ | Should -Match '^\s{4,}\S' }
        }
    }
}
