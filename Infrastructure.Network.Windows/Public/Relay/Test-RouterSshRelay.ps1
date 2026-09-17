<#
.NOTES
    Do not run this file directly. Dot-sourced by the module psm1.
#>

# ---------------------------------------------------------------------------
# Test-RouterSshRelay
#   Probes the controller -> router SSH relay end to end and reports which
#   half of it is broken. The read counterpart to Set-RouterSshRelay /
#   Remove-RouterSshRelay.
#
#   WHY AN ACTIVE PROBE, not an inspection of the netsh table. The failure
#   this exists to catch is that an ICS toggle regenerates the Internal
#   vSwitch network and iphlpsvc keeps forwarding bound to the PRE-toggle
#   generation. The portproxy entry still reads back perfectly from
#   `netsh interface portproxy show v4tov4` - it is the forwarding behind
#   it that is dead. So comparing configuration against expectation cannot
#   see this; only moving bytes can.
#
#   WHY THE LISTENER, not the router's own IP. Connecting straight to
#   <router>:22 bypasses the relay entirely and would report healthy while
#   every WSL-side consumer is broken. The probe therefore targets the
#   host-side listen endpoint, so the packets traverse exactly the hop that
#   goes stale.
#
#   The two stages are the diagnosis, and are reported separately:
#     Connect - the TCP connect to the listener failed. The portproxy is
#               absent (or the listen port moved). Nothing is forwarding.
#     Banner  - the connect SUCCEEDED but no SSH banner arrived before the
#               timeout. This is the stale-forwarding signature: iphlpsvc
#               accepted on the host and dropped the onward hop. It is also
#               what a powered-off router looks like, which the message
#               says rather than guessing between them.
#
#   SCOPE. This runs host-side against the loopback listener, so it proves
#   the portproxy and its forwarding. It does NOT traverse the Windows
#   Firewall (loopback bypasses it), so it cannot prove a WSL client is
#   allowed inbound. That is a deliberate and narrow gap: the firewall
#   companion is scoped by REMOTE ADDRESS (the WSL NAT range) rather than
#   by interface precisely so it has nothing volatile to go stale against -
#   see Set-RouterSshPortProxyFirewall. Forwarding staleness is the live
#   failure mode; the firewall's was closed by that scoping change.
#
#   Returns a result object rather than throwing, matching the Test-* verb
#   contract in this module (Assert-* throws; Test-* reports). Callers that
#   want a gate assert on .Ok and surface .Reason, which is written to be
#   shown to an operator verbatim.
#
#   PREFER A WSL-SIDE PROBE WHERE ONE IS REACHABLE. A probe run from inside
#   WSL also traverses the Windows Firewall, which this loopback probe cannot
#   (see SCOPE), making it the stronger check - Common-Ansible's
#   ops/virtual-machines/_assert-router-reachable.sh is that probe, and it
#   already gates the Ansible flows. This exists for host-side callers that
#   cannot reach it: an operator at a PowerShell prompt, a readiness script, a
#   pre-check. The reference is documentation, not a dependency - this module
#   does not consume Common-Ansible and must not start.
# ---------------------------------------------------------------------------

function Test-RouterSshRelay {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        # Host-side listen endpoint to probe. Defaults to loopback: the
        # portproxy listens on 0.0.0.0 so WSL can reach it via the host's
        # vEthernet IP, and loopback hits the same listener without needing
        # to know which of the host's addresses is the WSL-facing one.
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $ListenAddress = '127.0.0.1',

        # Must match the port Set-RouterSshRelay laid. Both default to 2222;
        # a caller that overrode one has to override the other.
        [Parameter()]
        [ValidateRange(1, 65535)]
        [int] $ListenPort = 2222,

        # Budget for BOTH the TCP connect and the banner read. Five seconds
        # is well past a healthy local relay (the connect is loopback and
        # the banner is one hop away) while still failing a wedged relay
        # fast enough to gate a provisioning run.
        [Parameter()]
        [ValidateRange(1, 120)]
        [int] $TimeoutSeconds = 5
    )

    $timeoutMs = $TimeoutSeconds * 1000
    $endpoint  = "${ListenAddress}:${ListenPort}"

    # Result shape is built up front and mutated on the way through so every
    # exit path returns the same fields - a caller can read .Ok and .Reason
    # without checking whether the others exist.
    $result = [pscustomobject]@{
        Ok            = $false
        ListenAddress = $ListenAddress
        ListenPort    = $ListenPort
        Stage         = 'Connect'
        Banner        = ''
        Reason        = ''
    }

    $client = [System.Net.Sockets.TcpClient]::new()
    try {
        # ConnectAsync + Wait rather than the synchronous Connect: the sync
        # overload ignores any timeout and can hang on SYN retries for the
        # OS default (~20s+), which is far too long for a gate.
        $connectTask = $client.ConnectAsync($ListenAddress, $ListenPort)

        # Wait reports the two ways a connect can fail differently: an expired
        # budget returns false, while a refusal FAULTS the task and is rethrown.
        # Both mean nothing usable answered, so both take the verdict below -
        # letting the fault escape would hand the generic catch the commonest
        # failure of all and replace this advice with a .NET exception string.
        $connectFault = ''
        try {
            $connected = $connectTask.Wait($timeoutMs) -and $client.Connected
        } catch {
            $connected = $false

            # Unwrap to the socket error: Wait raises AggregateException and
            # PowerShell wraps that again, so the outer messages say only that
            # something went wrong, not what.
            $inner = $_.Exception
            while ($inner.InnerException) { $inner = $inner.InnerException }
            $connectFault = $inner.Message
        }

        if (-not $connected) {
            # The cause separates "refused at once" (no listener on the port)
            # from "no answer at all" (a black-holed port, or a host that never
            # replied) - same remedy, different thing to check first, so it is
            # reported rather than flattened into one sentence.
            $cause = if ($connectFault) {
                "The connect failed: $connectFault"
            } else {
                "The connect did not complete within ${TimeoutSeconds}s."
            }
            $result.Reason = (
                "No SSH relay listening on $endpoint. $cause The host-side " +
                "portproxy is absent or on a different port. Re-lay it with " +
                "Set-RouterSshRelay -ConnectAddress <router-ip>, or run the " +
                "provisioner's network preflight with -AutoRepair."
            )
            return $result
        }

        # Connected: the listener is live, so anything that fails from here
        # is the onward hop rather than the portproxy's existence.
        $result.Stage = 'Banner'

        $stream = $client.GetStream()
        $stream.ReadTimeout = $timeoutMs
        $buffer = [byte[]]::new(255)

        try {
            $read = $stream.Read($buffer, 0, $buffer.Length)
        }
        catch [System.IO.IOException] {
            # A read timeout surfaces as IOException. This is THE signature
            # of the stale-forwarding bug, so the message leads with it
            # while naming the other cause it is indistinguishable from.
            $result.Reason = (
                "Connected to $endpoint but no SSH banner arrived within " +
                "${TimeoutSeconds}s. The portproxy is listening but its " +
                "onward hop to the router is not delivering - either the " +
                "forwarding went stale (an ICS toggle regenerates the " +
                "Internal vSwitch and strands iphlpsvc on the old network " +
                "generation) or the router VM is down. Re-lay the relay " +
                "with Set-RouterSshRelay -ConnectAddress <router-ip>; if " +
                "that does not fix it, check the router VM is running."
            )
            return $result
        }

        if ($read -le 0) {
            $result.Reason = (
                "Connected to $endpoint but the connection closed without " +
                "sending an SSH banner. The onward hop to the router is not " +
                "delivering; re-lay the relay and confirm the router VM is up."
            )
            return $result
        }

        # SSH servers announce themselves with an "SSH-<protoversion>-..."
        # identification string before anything else (RFC 4253 s4.2), so the
        # prefix is a sufficient and cheap proof that we reached sshd rather
        # than some other listener that happens to hold the port.
        $banner        = [System.Text.Encoding]::ASCII.GetString($buffer, 0, $read).Trim()
        $result.Banner = $banner

        if (-not $banner.StartsWith('SSH-')) {
            $result.Reason = (
                "Something is answering on $endpoint but it is not an SSH " +
                "server (banner: '$banner'). Another service may have taken " +
                "the listen port."
            )
            return $result
        }

        $result.Ok     = $true
        $result.Reason = "SSH relay healthy on $endpoint ($banner)."
        return $result
    }
    catch {
        # Anything unanticipated (a socket layer error, a DNS failure on a
        # non-loopback ListenAddress) is reported as a probe failure rather
        # than thrown, so a caller's gate still gets a Reason to display
        # instead of a stack trace.
        $result.Reason = (
            "Probing the SSH relay at $endpoint failed: $($_.Exception.Message)"
        )
        return $result
    }
    finally {
        # Dispose closes the underlying socket; safe on a client that never
        # connected.
        $client.Dispose()
    }
}
