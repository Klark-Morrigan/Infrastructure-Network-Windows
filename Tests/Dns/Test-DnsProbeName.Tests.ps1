BeforeAll {
    # Stub Resolve-DnsName so the wrapper can be loaded and the underlying
    # cmdlet mocked per test. The real cmdlet hits the network; tests must be
    # deterministic.
    function Resolve-DnsName {
        param(
            [string] $Name,
            [string] $Server,
            [switch] $DnsOnly,
            $ErrorAction
        )
    }
    function Get-DnsProbeName { }

    . "$PSScriptRoot\..\..\Infrastructure.Network.Windows\Private\Dns\Test-DnsProbeName.ps1"
}

Describe 'Test-DnsProbeName' {

    BeforeEach {
        Mock Get-DnsProbeName { 'probe.example.test' }
    }

    It 'returns $true when Resolve-DnsName returns an answer' {
        Mock Resolve-DnsName { [PSCustomObject]@{ IPAddress = '185.125.190.21' } }

        Test-DnsProbeName -Server '192.168.137.1' | Should -BeTrue
    }

    It 'returns $false when Resolve-DnsName throws (timeout / RST / NXDOMAIN)' {
        Mock Resolve-DnsName { throw 'connection forcibly closed' }

        Test-DnsProbeName -Server '192.168.137.1' | Should -BeFalse
    }

    It 'passes -Server through verbatim' {
        Mock Resolve-DnsName { [PSCustomObject]@{ IPAddress = '1.1.1.1' } }

        Test-DnsProbeName -Server '10.20.30.40' | Should -BeTrue
        Should -Invoke Resolve-DnsName -Times 1 -Exactly `
            -ParameterFilter { $Server -eq '10.20.30.40' }
    }

    It 'omits -Server entirely when none is supplied' {
        # Passing an empty -Server instead of omitting it would make
        # Resolve-DnsName throw, silently turning "ask the host's own
        # resolver" into an unconditional $false.
        Mock Resolve-DnsName { [PSCustomObject]@{ IPAddress = '1.1.1.1' } }

        Test-DnsProbeName | Should -BeTrue
        Should -Invoke Resolve-DnsName -Times 1 -Exactly `
            -ParameterFilter { -not $Server }
    }

    It 'resolves the name Get-DnsProbeName owns rather than one of its own' {
        Mock Resolve-DnsName { [PSCustomObject]@{ IPAddress = '1.1.1.1' } }

        Test-DnsProbeName -Server '192.168.137.1' | Should -BeTrue
        Should -Invoke Resolve-DnsName -Times 1 -Exactly `
            -ParameterFilter { $Name -eq 'probe.example.test' }
    }
}
