BeforeAll {
    # Stub netsh so the source dot-sources cleanly and every call is
    # recorded. $LASTEXITCODE is set explicitly because PowerShell does not
    # propagate it across a function boundary when the body invokes no real
    # native process.
    function global:netsh {
        $script:_NetshCalls += @{ Args = $args }
        $output = $script:_NetshOutput
        $global:LASTEXITCODE = $script:_NetshExitCode
        return $output
    }

    . "$PSScriptRoot\..\..\Infrastructure.Network.Windows\Public\Portproxy\Get-NetshPortProxyRules.ps1"
    . "$PSScriptRoot\..\..\Infrastructure.Network.Windows\Public\Portproxy\Remove-RouterSshPortProxy.ps1"

    function Initialize-NetshState {
        $script:_NetshCalls    = @()
        $script:_NetshOutput   = @()
        $script:_NetshExitCode = 0
    }

    function New-NetshShowOutput {
        # Mimic `netsh interface portproxy show v4tov4` text shape.
        param([object[]] $Rules)
        $lines = @(
            'Listen on ipv4:             Connect to ipv4:',
            '',
            'Address         Port        Address         Port',
            '--------------- ----------  --------------- ----------'
        )
        foreach ($r in $Rules) {
            $lines += ("{0,-15} {1,-11} {2,-15} {3}" -f `
                $r.ListenAddress, $r.ListenPort, $r.ConnectAddress, $r.ConnectPort)
        }
        $lines
    }
}

Describe 'Remove-RouterSshPortProxy' {

    BeforeEach { Initialize-NetshState }

    Context 'a relay forwarding to the router exists' {

        It 'deletes it by its listen target' {
            $script:_NetshOutput = New-NetshShowOutput @(
                [PSCustomObject]@{
                    ListenAddress = '0.0.0.0'; ListenPort = 2222
                    ConnectAddress = '192.168.137.11'; ConnectPort = 22
                }
            )

            Remove-RouterSshPortProxy -ConnectAddress '192.168.137.11'

            $delete = @($script:_NetshCalls | Where-Object { $_.Args -contains 'delete' })
            $delete.Count   | Should -Be 1
            $delete[0].Args | Should -Contain 'listenaddress=0.0.0.0'
            $delete[0].Args | Should -Contain 'listenport=2222'
        }
    }

    Context 'multiple relays point at the same router' {

        It 'sweeps every one (0.0.0.0 AND a pinned 127.0.0.1)' {
            # The exact drift that broke production: a router IP with both a
            # 0.0.0.0 and a leftover 127.0.0.1 relay. Keying on the connect
            # target removes both.
            $script:_NetshOutput = New-NetshShowOutput @(
                [PSCustomObject]@{
                    ListenAddress = '0.0.0.0'; ListenPort = 2222
                    ConnectAddress = '192.168.137.11'; ConnectPort = 22
                }
                [PSCustomObject]@{
                    ListenAddress = '127.0.0.1'; ListenPort = 2222
                    ConnectAddress = '192.168.137.11'; ConnectPort = 22
                }
            )

            Remove-RouterSshPortProxy -ConnectAddress '192.168.137.11'

            @($script:_NetshCalls | Where-Object { $_.Args -contains 'delete' }).Count |
                Should -Be 2
        }
    }

    Context 'no relay forwards to the router' {

        It 'does not call netsh delete (idempotent)' {
            $script:_NetshOutput = New-NetshShowOutput @(
                [PSCustomObject]@{
                    ListenAddress = '0.0.0.0'; ListenPort = 2222
                    ConnectAddress = '10.0.0.99'; ConnectPort = 22
                }
            )

            Remove-RouterSshPortProxy -ConnectAddress '192.168.137.11'

            @($script:_NetshCalls | Where-Object { $_.Args -contains 'delete' }).Count |
                Should -Be 0
        }
    }

    Context 'a relay to a different router IP coexists' {

        It 'removes only the matching router IP, leaving the other in place' {
            $script:_NetshOutput = New-NetshShowOutput @(
                [PSCustomObject]@{
                    ListenAddress = '0.0.0.0'; ListenPort = 2222
                    ConnectAddress = '192.168.137.10'; ConnectPort = 22   # E2E's - keep
                }
                [PSCustomObject]@{
                    ListenAddress = '0.0.0.0'; ListenPort = 3333
                    ConnectAddress = '192.168.137.11'; ConnectPort = 22   # target - remove
                }
            )

            Remove-RouterSshPortProxy -ConnectAddress '192.168.137.11'

            $delete = @($script:_NetshCalls | Where-Object { $_.Args -contains 'delete' })
            $delete.Count   | Should -Be 1
            $delete[0].Args | Should -Contain 'listenport=3333'
        }
    }

    Context 'netsh delete fails transiently' {

        It 'warns and does not throw (teardown must stay resilient)' {
            $script:_NetshOutput = New-NetshShowOutput @(
                [PSCustomObject]@{
                    ListenAddress = '0.0.0.0'; ListenPort = 2222
                    ConnectAddress = '192.168.137.11'; ConnectPort = 22
                }
            )
            $script:_NetshExitCode = 1

            { Remove-RouterSshPortProxy -ConnectAddress '192.168.137.11' `
                -WarningAction SilentlyContinue } | Should -Not -Throw
        }
    }
}
