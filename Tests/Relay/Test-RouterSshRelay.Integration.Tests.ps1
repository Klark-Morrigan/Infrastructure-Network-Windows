BeforeAll {
    . "$PSScriptRoot\..\..\Infrastructure.Network.Windows\Public\Relay\Test-RouterSshRelay.ps1"

    # These tests drive REAL loopback sockets rather than mocking TcpClient.
    # The whole value of this function is what actually happens on the wire - a
    # mocked socket would assert the test's own fiction and prove nothing about
    # the failure mode the probe exists to catch. Hence the Integration name:
    # they need no Docker and run in the normal suite, but they are not unit
    # tests and their cost is real socket time, not CPU.

    # A listener that is Start()ed but never Accept()s. The OS completes the
    # TCP handshake from the backlog, so a client connects successfully and
    # then waits forever for data - which is EXACTLY the stale-forwarding
    # signature: iphlpsvc accepts on the host and never delivers the onward
    # hop. No background thread needed for this one.
    function New-SilentListener {
        $listener = [System.Net.Sockets.TcpListener]::new(
            [System.Net.IPAddress]::Loopback, 0)
        $listener.Start()
        return $listener
    }

    # Probes a listener that accepts one connection and writes $Payload (or
    # closes immediately when $Payload is empty), and returns the probe result
    # alongside the port it ran against.
    #
    # Setup, probe and teardown are one call because the listener is
    # single-shot: it serves exactly one probe, so every caller repeated the
    # same create / try / finally around a single Test-RouterSshRelay.
    function Invoke-ProbeAgainstResponder {
        param([string] $Payload)

        $listener = [System.Net.Sockets.TcpListener]::new(
            [System.Net.IPAddress]::Loopback, 0)
        $listener.Start()

        # $using: rather than -ArgumentList: a thread job runs in-process, so
        # the listener object crosses by reference with no serialization, and
        # it keeps PSScriptAnalyzer's new-runspace scope rule satisfied
        # without a suppression.
        $job = Start-ThreadJob -ScriptBlock {
            $client = ($using:listener).AcceptTcpClient()
            $stream = $client.GetStream()
            $payloadIn = $using:Payload
            if ($payloadIn) {
                $bytes = [System.Text.Encoding]::ASCII.GetBytes($payloadIn)
                $stream.Write($bytes, 0, $bytes.Length)
                $stream.Flush()
            }
            # Closing without writing is the "connection closed without a
            # banner" case; closing after writing is harmless (the probe
            # has already read what it needs).
            $client.Close()
        }

        try {
            $port = $listener.LocalEndpoint.Port
            return [pscustomobject]@{
                Port   = $port
                Result = Test-RouterSshRelay -ListenPort $port -TimeoutSeconds 5
            }
        }
        finally {
            $job | Remove-Job -Force -ErrorAction SilentlyContinue
            $listener.Stop()
        }
    }

    # A port nothing is listening on. Bind an ephemeral port, note it, then
    # release it - far more reliable than hoping a hardcoded port is free.
    function Get-UnusedPort {
        $probe = [System.Net.Sockets.TcpListener]::new(
            [System.Net.IPAddress]::Loopback, 0)
        $probe.Start()
        $port = $probe.LocalEndpoint.Port
        $probe.Stop()
        return $port
    }
}

Describe 'Test-RouterSshRelay' {

    BeforeAll {
        # Every scenario is probed ONCE here and the tests below only assert on
        # the result. Each probe costs real socket time (a refusal or an unread
        # banner is seconds, not microseconds), so probing per assertion made
        # the suite spend most of its runtime repeating identical waits.
        $script:healthy = Invoke-ProbeAgainstResponder -Payload "SSH-2.0-OpenSSH_9.6p1 Ubuntu`r`n"
        $script:nonSsh  = Invoke-ProbeAgainstResponder -Payload "HTTP/1.1 200 OK`r`n"
        $script:closed  = Invoke-ProbeAgainstResponder -Payload ''

        # Probed at the DEFAULT budget because that is what every real caller
        # uses, and because a refusal that lands inside the budget faults the
        # connect task - a different code path from the budget expiring. A
        # short budget can expire at the same instant the refusal arrives and
        # mask the fault path entirely.
        $script:refused = Test-RouterSshRelay -ListenPort (Get-UnusedPort)

        # Kept open for the whole Describe: unlike the responder it serves any
        # number of probes, and the timeout test below needs a second one.
        $script:silentListener = New-SilentListener
        $script:noBanner       = Test-RouterSshRelay `
            -ListenPort $script:silentListener.LocalEndpoint.Port `
            -TimeoutSeconds 1
    }

    AfterAll {
        $script:silentListener.Stop()
    }

    Context 'healthy relay' {

        It 'reports Ok with the banner when an SSH server answers' {
            $script:healthy.Result.Ok     | Should -BeTrue
            $script:healthy.Result.Stage  | Should -Be 'Banner'
            $script:healthy.Result.Banner | Should -BeLike 'SSH-2.0-OpenSSH*'
            $script:healthy.Result.Reason | Should -BeLike '*healthy*'
        }

        It 'echoes the probed endpoint back in the result' {
            $script:healthy.Result.ListenAddress | Should -Be '127.0.0.1'
            $script:healthy.Result.ListenPort    | Should -Be $script:healthy.Port
        }
    }

    Context 'nothing listening (portproxy absent)' {

        It 'reports Stage Connect and points at re-laying the relay' {
            $script:refused.Ok     | Should -BeFalse
            $script:refused.Stage  | Should -Be 'Connect'
            $script:refused.Reason | Should -BeLike '*No SSH relay listening*'
            $script:refused.Reason | Should -BeLike '*Set-RouterSshRelay*'
        }

        It 'leaves the banner empty when it never connected' {
            $script:refused.Banner | Should -BeNullOrEmpty
        }

        # The socket error is the operator's evidence for WHICH failure this
        # was; reporting only the advice would make a refusal and a silently
        # black-holed port read identically.
        It 'quotes the underlying socket error when the connect faults' {
            $script:refused.Reason | Should -BeLike '*The connect failed:*'
            $script:refused.Reason | Should -BeLike '*refused*'
        }
    }

    Context 'listening but not forwarding (the stale-generation signature)' {

        # The case that motivated the whole function: the portproxy accepts
        # on the host and the onward hop to the router never delivers. A
        # netsh read cannot see this - the entry looks perfect.
        It 'reports Stage Banner when the connect succeeds but no banner arrives' {
            $script:noBanner.Ok    | Should -BeFalse
            $script:noBanner.Stage | Should -Be 'Banner'
        }

        # The two causes are indistinguishable on the wire, so the message
        # must name both rather than assert one - an operator chasing the
        # wrong one wastes the time this probe was meant to save.
        It 'names both stale forwarding and a down router as causes' {
            $script:noBanner.Reason | Should -BeLike '*no SSH banner*'
            $script:noBanner.Reason | Should -BeLike '*stale*'
            $script:noBanner.Reason | Should -BeLike '*router VM is down*'
        }

        It 'honours the timeout budget rather than hanging' {
            $elapsed = Measure-Command {
                Test-RouterSshRelay `
                    -ListenPort $script:silentListener.LocalEndpoint.Port `
                    -TimeoutSeconds 1 | Out-Null
            }
            # Generous upper bound - the point is that it returns at all
            # rather than blocking on the OS default socket timeout.
            $elapsed.TotalSeconds | Should -BeLessThan 15
        }
    }

    Context 'wrong service on the port' {

        It 'rejects a non-SSH banner and quotes what answered' {
            $script:nonSsh.Result.Ok     | Should -BeFalse
            $script:nonSsh.Result.Reason | Should -BeLike '*not an SSH server*'
            $script:nonSsh.Result.Reason | Should -BeLike '*HTTP/1.1 200 OK*'
        }
    }

    Context 'connection closed without a banner' {

        It 'reports the close rather than treating it as healthy' {
            $script:closed.Result.Ok     | Should -BeFalse
            $script:closed.Result.Reason | Should -BeLike '*without*banner*'
        }
    }

    Context 'result contract' {

        # Callers gate on .Ok and display .Reason, so every exit path must
        # populate the same fields - a caller should never have to test for
        # a property's existence.
        It 'returns the same shape on success and failure' {
            $expected = @('Ok', 'ListenAddress', 'ListenPort', 'Stage', 'Banner', 'Reason')

            foreach ($result in @($script:healthy.Result, $script:refused, $script:noBanner)) {
                $names = @($result.PSObject.Properties.Name)
                foreach ($field in $expected) { $names | Should -Contain $field }
            }
        }

        It 'never throws on an unreachable endpoint' {
            { Test-RouterSshRelay -ListenPort (Get-UnusedPort) -TimeoutSeconds 1 } |
                Should -Not -Throw
        }
    }
}
