BeforeAll {
    # The resolve itself belongs to Test-DnsProbeName and is tested there.
    # What this wrapper owns is WHICH question it asks - and the whole point of
    # the host-side probe is that it asks without pinning a resolver.
    function Test-DnsProbeName { param([string] $Server) }

    . "$PSScriptRoot\..\..\Infrastructure.Network.Windows\Public\Ics\Test-HostDnsReachable.ps1"
}

Describe 'Test-HostDnsReachable' {

    It 'resolves via the host''s own resolver - no -Server is passed' {
        # A regression that pinned a -Server would silently turn this into a
        # second copy of Test-IcsDnsReachable, and the diagnosis that depends
        # on the two answering different questions would collapse.
        Mock Test-DnsProbeName { $true }

        Test-HostDnsReachable | Should -BeTrue
        Should -Invoke Test-DnsProbeName -Times 1 -Exactly `
            -ParameterFilter { -not $Server }
    }

    It 'passes the probe result through unchanged' {
        Mock Test-DnsProbeName { $false }

        Test-HostDnsReachable | Should -BeFalse
    }
}
