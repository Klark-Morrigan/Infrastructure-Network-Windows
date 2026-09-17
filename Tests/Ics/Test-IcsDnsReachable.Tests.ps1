BeforeAll {
    # The resolve itself belongs to Test-DnsProbeName and is tested there;
    # what this wrapper owns is that the caller's resolver reaches it.
    function Test-DnsProbeName { param([string] $Server) }

    . "$PSScriptRoot\..\..\Infrastructure.Network.Windows\Public\Ics\Test-IcsDnsReachable.ps1"
}

Describe 'Test-IcsDnsReachable' {

    It 'probes the caller''s resolver verbatim' {
        Mock Test-DnsProbeName { $true }

        Test-IcsDnsReachable -Server '10.20.30.40' | Should -BeTrue
        Should -Invoke Test-DnsProbeName -Times 1 -Exactly `
            -ParameterFilter { $Server -eq '10.20.30.40' }
    }

    It 'passes the probe result through unchanged' {
        Mock Test-DnsProbeName { $false }

        Test-IcsDnsReachable -Server '192.168.137.1' | Should -BeFalse
    }

    It 'requires a resolver - the host-side question has its own function' {
        { Test-IcsDnsReachable -Server '' } | Should -Throw
    }
}
