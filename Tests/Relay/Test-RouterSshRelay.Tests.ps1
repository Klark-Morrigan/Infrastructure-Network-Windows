BeforeAll {
    . "$PSScriptRoot\..\..\Infrastructure.Network.Windows\Public\Relay\Test-RouterSshRelay.ps1"

    # These tests drive REAL loopback sockets rather than mocking
    # TcpClient. The whole value of this function is what actually happens
    # on the wire - a mocked socket would assert the test's own fiction and
    # prove nothing about the failure mode the probe exists to catch.

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

    # A listener that accepts one connection and writes $Payload (or closes
    # immediately when $Payload is empty). The accept/write half runs on a
    # thread job because the probe blocks reading in the calling thread.
    function New-RespondingListener {
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

        return [pscustomobject]@{ Listener = $listener; Job = $job }
    }

    function Stop-Fixture {
        param($Listener, $Job)
        if ($Job)      { $Job | Remove-Job -Force -ErrorAction SilentlyContinue }
        if ($Listener) { $Listener.Stop() }
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

    Context 'healthy relay' {

        It 'reports Ok with the banner when an SSH server answers' {
            $fixture = New-RespondingListener -Payload "SSH-2.0-OpenSSH_9.6p1 Ubuntu`r`n"
            try {
                $result = Test-RouterSshRelay `
                    -ListenPort $fixture.Listener.LocalEndpoint.Port `
                    -TimeoutSeconds 5

                $result.Ok     | Should -BeTrue
                $result.Stage  | Should -Be 'Banner'
                $result.Banner | Should -BeLike 'SSH-2.0-OpenSSH*'
                $result.Reason | Should -BeLike '*healthy*'
            }
            finally { Stop-Fixture -Listener $fixture.Listener -Job $fixture.Job }
        }

        It 'echoes the probed endpoint back in the result' {
            $fixture = New-RespondingListener -Payload "SSH-2.0-Test`r`n"
            try {
                $port   = $fixture.Listener.LocalEndpoint.Port
                $result = Test-RouterSshRelay -ListenPort $port -TimeoutSeconds 5

                $result.ListenAddress | Should -Be '127.0.0.1'
                $result.ListenPort    | Should -Be $port
            }
            finally { Stop-Fixture -Listener $fixture.Listener -Job $fixture.Job }
        }
    }

    Context 'nothing listening (portproxy absent)' {

        It 'reports Stage Connect and points at re-laying the relay' {
            $result = Test-RouterSshRelay -ListenPort (Get-UnusedPort) -TimeoutSeconds 2

            $result.Ok     | Should -BeFalse
            $result.Stage  | Should -Be 'Connect'
            $result.Reason | Should -BeLike '*No SSH relay listening*'
            $result.Reason | Should -BeLike '*Set-RouterSshRelay*'
        }

        It 'leaves the banner empty when it never connected' {
            $result = Test-RouterSshRelay -ListenPort (Get-UnusedPort) -TimeoutSeconds 2
            $result.Banner | Should -BeNullOrEmpty
        }
    }

    Context 'listening but not forwarding (the stale-generation signature)' {

        # The case that motivated the whole function: the portproxy accepts
        # on the host and the onward hop to the router never delivers. A
        # netsh read cannot see this - the entry looks perfect.
        It 'reports Stage Banner when the connect succeeds but no banner arrives' {
            $listener = New-SilentListener
            try {
                $result = Test-RouterSshRelay `
                    -ListenPort $listener.LocalEndpoint.Port `
                    -TimeoutSeconds 1

                $result.Ok    | Should -BeFalse
                $result.Stage | Should -Be 'Banner'
            }
            finally { Stop-Fixture -Listener $listener }
        }

        # The two causes are indistinguishable on the wire, so the message
        # must name both rather than assert one - an operator chasing the
        # wrong one wastes the time this probe was meant to save.
        It 'names both stale forwarding and a down router as causes' {
            $listener = New-SilentListener
            try {
                $result = Test-RouterSshRelay `
                    -ListenPort $listener.LocalEndpoint.Port `
                    -TimeoutSeconds 1

                $result.Reason | Should -BeLike '*no SSH banner*'
                $result.Reason | Should -BeLike '*stale*'
                $result.Reason | Should -BeLike '*router VM is down*'
            }
            finally { Stop-Fixture -Listener $listener }
        }

        It 'honours the timeout budget rather than hanging' {
            $listener = New-SilentListener
            try {
                $elapsed = Measure-Command {
                    Test-RouterSshRelay `
                        -ListenPort $listener.LocalEndpoint.Port `
                        -TimeoutSeconds 1 | Out-Null
                }
                # Generous upper bound - the point is that it returns at all
                # rather than blocking on the OS default socket timeout.
                $elapsed.TotalSeconds | Should -BeLessThan 15
            }
            finally { Stop-Fixture -Listener $listener }
        }
    }

    Context 'wrong service on the port' {

        It 'rejects a non-SSH banner and quotes what answered' {
            $fixture = New-RespondingListener -Payload "HTTP/1.1 200 OK`r`n"
            try {
                $result = Test-RouterSshRelay `
                    -ListenPort $fixture.Listener.LocalEndpoint.Port `
                    -TimeoutSeconds 5

                $result.Ok     | Should -BeFalse
                $result.Reason | Should -BeLike '*not an SSH server*'
                $result.Reason | Should -BeLike '*HTTP/1.1 200 OK*'
            }
            finally { Stop-Fixture -Listener $fixture.Listener -Job $fixture.Job }
        }
    }

    Context 'connection closed without a banner' {

        It 'reports the close rather than treating it as healthy' {
            $fixture = New-RespondingListener -Payload ''
            try {
                $result = Test-RouterSshRelay `
                    -ListenPort $fixture.Listener.LocalEndpoint.Port `
                    -TimeoutSeconds 5

                $result.Ok     | Should -BeFalse
                $result.Reason | Should -BeLike '*without*banner*'
            }
            finally { Stop-Fixture -Listener $fixture.Listener -Job $fixture.Job }
        }
    }

    Context 'result contract' {

        # Callers gate on .Ok and display .Reason, so every exit path must
        # populate the same fields - a caller should never have to test for
        # a property's existence.
        It 'returns the same shape on success and failure' {
            $expected = @('Ok', 'ListenAddress', 'ListenPort', 'Stage', 'Banner', 'Reason')

            $fixture = New-RespondingListener -Payload "SSH-2.0-Test`r`n"
            try {
                $pass = Test-RouterSshRelay `
                    -ListenPort $fixture.Listener.LocalEndpoint.Port -TimeoutSeconds 5
            }
            finally { Stop-Fixture -Listener $fixture.Listener -Job $fixture.Job }

            $fail = Test-RouterSshRelay -ListenPort (Get-UnusedPort) -TimeoutSeconds 2

            foreach ($result in @($pass, $fail)) {
                $names = @($result.PSObject.Properties.Name)
                foreach ($field in $expected) { $names | Should -Contain $field }
            }
        }

        It 'never throws on an unreachable endpoint' {
            { Test-RouterSshRelay -ListenPort (Get-UnusedPort) -TimeoutSeconds 2 } |
                Should -Not -Throw
        }
    }
}
