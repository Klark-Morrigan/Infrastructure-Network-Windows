BeforeAll {
    # Stub the two inner removers so the composition can be dot-sourced
    # and asserted in isolation. Their own behaviour is covered in
    # Tests/Portproxy and Tests/Firewall.
    function Remove-RouterSshPortProxy         { param([string]$ConnectAddress, [int]$ConnectPort) }
    function Remove-RouterSshPortProxyFirewall { param([int]$ListenPort) }

    . "$PSScriptRoot\..\..\Infrastructure.Network.Windows\Public\Relay\Remove-RouterSshRelay.ps1"
}

Describe 'Remove-RouterSshRelay' {

    BeforeEach {
        Mock Remove-RouterSshPortProxy         { }
        Mock Remove-RouterSshPortProxyFirewall { }
    }

    It 'removes the portproxy for the connect address and the firewall' {
        Remove-RouterSshRelay -ConnectAddress '192.168.137.11'

        Should -Invoke Remove-RouterSshPortProxy -Times 1 -Exactly -ParameterFilter {
            $ConnectAddress -eq '192.168.137.11'
        }
        Should -Invoke Remove-RouterSshPortProxyFirewall -Times 1 -Exactly
    }

    It 'forwards a custom listen port to the firewall remover' {
        Remove-RouterSshRelay -ConnectAddress '192.168.137.11' -ListenPort 8222

        Should -Invoke Remove-RouterSshPortProxyFirewall -Times 1 -Exactly -ParameterFilter {
            $ListenPort -eq 8222
        }
    }

    It 'forwards a custom connect port to the portproxy remover' {
        Remove-RouterSshRelay -ConnectAddress '192.168.137.11' -ConnectPort 2200

        Should -Invoke Remove-RouterSshPortProxy -Times 1 -Exactly -ParameterFilter {
            $ConnectPort -eq 2200
        }
    }
}
