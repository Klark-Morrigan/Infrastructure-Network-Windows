BeforeAll {
    # Stub the two inner relay primitives so the composition can be
    # dot-sourced and asserted in isolation. Their own behaviour is
    # covered in Tests/Portproxy and Tests/Firewall.
    function Set-RouterSshPortProxy         { param([string]$ConnectAddress) }
    function Set-RouterSshPortProxyFirewall { param([int]$ListenPort) }

    . "$PSScriptRoot\..\..\Infrastructure.Network.Windows\Public\Relay\Set-RouterSshRelay.ps1"
}

Describe 'Set-RouterSshRelay' {

    BeforeEach {
        Mock Set-RouterSshPortProxy         { }
        Mock Set-RouterSshPortProxyFirewall { }
    }

    Context 'Full set (portproxy + firewall)' {

        It 'lays the portproxy with the connect address and the firewall' {
            Set-RouterSshRelay -ConnectAddress '192.168.137.11'

            Should -Invoke Set-RouterSshPortProxy -Times 1 -Exactly -ParameterFilter {
                $ConnectAddress -eq '192.168.137.11'
            }
            Should -Invoke Set-RouterSshPortProxyFirewall -Times 1 -Exactly
        }
    }

    Context 'FirewallOnly set' {

        It 'lays only the firewall and skips the portproxy' {
            Set-RouterSshRelay -FirewallOnly

            Should -Invoke Set-RouterSshPortProxy         -Times 0
            Should -Invoke Set-RouterSshPortProxyFirewall -Times 1 -Exactly
        }
    }

    Context 'mutually exclusive parameter sets' {

        It 'rejects passing both -ConnectAddress and -FirewallOnly' {
            { Set-RouterSshRelay -ConnectAddress '192.168.137.11' -FirewallOnly } |
                Should -Throw
        }
    }
}
