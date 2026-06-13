BeforeAll {
    # Stub Resolve-DnsName so the wrapper can be loaded and the
    # underlying cmdlet mocked per test. The real cmdlet hits the
    # network; tests must be deterministic.
    function Resolve-DnsName {
        param(
            [string] $Name,
            [string] $Server,
            [switch] $DnsOnly,
            $ErrorAction
        )
    }

    . "$PSScriptRoot\..\..\Infrastructure.Network.Windows\Public\Ics\Test-IcsDnsReachable.ps1"
}

Describe 'Test-IcsDnsReachable' {

    It 'returns $true when Resolve-DnsName returns an answer' {
        Mock Resolve-DnsName { [PSCustomObject]@{ IPAddress = '185.125.190.21' } }

        Test-IcsDnsReachable -Server '192.168.137.1' | Should -BeTrue
    }

    It 'returns $false when Resolve-DnsName throws (timeout / RST / NXDOMAIN)' {
        Mock Resolve-DnsName { throw 'connection forcibly closed' }

        Test-IcsDnsReachable -Server '192.168.137.1' | Should -BeFalse
    }

    It 'passes -Server through verbatim' {
        Mock Resolve-DnsName { [PSCustomObject]@{ IPAddress = '1.1.1.1' } } `
            -ParameterFilter { $Server -eq '10.20.30.40' }

        Test-IcsDnsReachable -Server '10.20.30.40' | Should -BeTrue
        Should -Invoke Resolve-DnsName -Times 1 -Exactly `
            -ParameterFilter { $Server -eq '10.20.30.40' }
    }

    It 'probes the fixed archive.ubuntu.com name regardless of caller' {
        # The cmdlet hard-codes the probe target so callers do not
        # have to pick. Pinned here so a regression that lets callers
        # supply -Name (and accidentally test the wrong hostname) fails.
        Mock Resolve-DnsName { [PSCustomObject]@{ IPAddress = '1.1.1.1' } } `
            -ParameterFilter { $Name -eq 'archive.ubuntu.com' }

        Test-IcsDnsReachable -Server '192.168.137.1' | Should -BeTrue
        Should -Invoke Resolve-DnsName -Times 1 -Exactly `
            -ParameterFilter { $Name -eq 'archive.ubuntu.com' }
    }
}
