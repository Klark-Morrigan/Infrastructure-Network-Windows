BeforeAll {
    # Stub netsh so the source can be dot-sourced and the call
    # sites mocked per-test. The function returns whatever the
    # test wires up via Mock; $LASTEXITCODE is set explicitly
    # because PowerShell does not propagate it across function
    # boundaries when the body does not invoke a native process.
    function global:netsh {
        $script:_NetshCalls += @{ Args = $args }
        $output = $global:_NetshOutput
        $global:LASTEXITCODE = $global:_NetshExitCode
        return $output
    }

    # Stub the Common.PowerShell retry primitive the production code now
    # delegates the add to. The retry MECHANICS (attempt count, backoff,
    # exhaustion throw) are owned and tested by Common.PowerShell; this
    # unit only needs to prove Set-RouterSshPortProxy hands the netsh add
    # to it. The stub records the call and runs the block once - the
    # block sees the caller's locals because it is invoked synchronously
    # while Set-RouterSshPortProxy is still on the call stack.
    function global:Invoke-WithExitCodeRetry {
        param(
            [scriptblock] $ScriptBlock,
            [string]      $OperationName,
            [hashtable]   $BackoffStrategy,
            [int]         $MaxAttempts = 3,
            [int[]]       $RetryableExitCode = @()
        )
        $script:_RetryCalls += @{ OperationName = $OperationName }
        & $ScriptBlock
    }

    . "$PSScriptRoot\..\..\Infrastructure.Network.Windows\Public\Portproxy\Get-NetshPortProxyRules.ps1"
    . "$PSScriptRoot\..\..\Infrastructure.Network.Windows\Public\Portproxy\Set-RouterSshPortProxy.ps1"

    function Initialize-NetshState {
        $script:_NetshCalls    = @()
        $script:_RetryCalls    = @()
        $global:_NetshOutput   = @()
        $global:_NetshExitCode = 0
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
                $r.ListenAddress, $r.ListenPort,
                $r.ConnectAddress, $r.ConnectPort)
        }
        $lines
    }
}

Describe 'Set-RouterSshPortProxy' {

    BeforeEach { Initialize-NetshState }

    Context 'an existing rule for the listen target' {

        It 'refreshes it (delete + re-add) even when the connect target is identical' {
            # The rule text persists across a router/switch teardown but
            # its iphlpsvc forwarding goes stale; an unconditional re-add
            # rebinds the relay. Skipping here (the previous behaviour) is
            # what stranded WSL -> portproxy -> router across reprovisions.
            $global:_NetshOutput = New-NetshShowOutput @(
                [PSCustomObject]@{
                    ListenAddress  = '0.0.0.0'
                    ListenPort     = 2222
                    ConnectAddress = '192.168.137.10'
                    ConnectPort    = 22
                }
            )

            Set-RouterSshPortProxy -ConnectAddress '192.168.137.10'

            # @(...) wraps the (possibly $null) Where-Object result so
            # .Count is StrictMode-safe.
            @($script:_NetshCalls | Where-Object { $_.Args -contains 'delete' }).Count |
                Should -Be 1
            @($script:_NetshCalls | Where-Object { $_.Args -contains 'add' }).Count    |
                Should -Be 1
        }
    }

    Context 'when listen target points at a different connect target' {

        It 'deletes the stale rule and adds the new one' {
            $global:_NetshOutput = New-NetshShowOutput @(
                [PSCustomObject]@{
                    ListenAddress  = '0.0.0.0'
                    ListenPort     = 2222
                    ConnectAddress = '10.0.0.99'      # stale
                    ConnectPort    = 22
                }
            )

            Set-RouterSshPortProxy -ConnectAddress '192.168.137.10'

            @($script:_NetshCalls | Where-Object { $_.Args -contains 'delete' }).Count |
                Should -Be 1
            @($script:_NetshCalls | Where-Object { $_.Args -contains 'add' }).Count    |
                Should -Be 1
        }
    }

    Context 'when no rule exists for the listen target' {

        It 'adds a fresh rule' {
            $global:_NetshOutput = New-NetshShowOutput @()

            Set-RouterSshPortProxy -ConnectAddress '192.168.137.10'

            @($script:_NetshCalls | Where-Object { $_.Args -contains 'add' }).Count |
                Should -Be 1
        }

        It 'passes the operator-supplied listen + connect addresses through verbatim' {
            $global:_NetshOutput = New-NetshShowOutput @()

            Set-RouterSshPortProxy `
                -ListenAddress  '127.0.0.1' `
                -ListenPort     8222 `
                -ConnectAddress '192.168.137.42' `
                -ConnectPort    2200

            $addCall = $script:_NetshCalls | Where-Object { $_.Args -contains 'add' }
            $addCall.Args | Should -Contain 'listenaddress=127.0.0.1'
            $addCall.Args | Should -Contain 'listenport=8222'
            $addCall.Args | Should -Contain 'connectaddress=192.168.137.42'
            $addCall.Args | Should -Contain 'connectport=2200'
        }

        It 'performs the add through the Invoke-WithExitCodeRetry wrapper' {
            # The add must be retry-wrapped: with the delete already done,
            # a single hard failure would strand the listen target. Prove
            # the netsh add is handed to the retry primitive (which owns
            # the attempt/backoff/exhaustion behaviour) rather than run
            # bare. Mechanics themselves are covered by Common.PowerShell.
            $global:_NetshOutput = New-NetshShowOutput @()

            Set-RouterSshPortProxy -ConnectAddress '192.168.137.10'

            @($script:_RetryCalls).Count | Should -Be 1
            $script:_RetryCalls[0].OperationName |
                Should -BeLike '*netsh portproxy add*192.168.137.10*'
            # The wrapped block actually issued the add.
            @($script:_NetshCalls | Where-Object { $_.Args -contains 'add' }).Count |
                Should -Be 1
        }
    }
}
