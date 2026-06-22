<#
.NOTES
    Do not run this file directly. Dot-sourced by deprovision.ps1.
#>

# ---------------------------------------------------------------------------
# Remove-RouterSshPortProxy
#   Teardown counterpart to Set-RouterSshPortProxy. Removes every host-side
#   netsh portproxy rule that forwards to <ConnectAddress>:<ConnectPort>
#   (the router VM's SSH endpoint), whatever listen address each rule binds.
#
#   Why key on the CONNECT target, not the listen target:
#     A router's relay can exist under more than one listen address across a
#     machine's history (0.0.0.0 default vs an operator-pinned 127.0.0.1),
#     and netsh portproxy state PERSISTS across VM/switch teardown - reboots,
#     re-provisions, the lot - in HKLM\...\Services\PortProxy. Keying removal
#     on the router IP sweeps every relay pointing at the router being torn
#     down, which is the only thing that stops rules accumulating per router
#     IP across lifecycles.
#
#   Why a leftover rule is not harmless:
#     The WSL-side relay auto-discovery (the Ansible bridge) keys on the
#     rule's CONNECT address, so a stale rule for a decommissioned router IP
#     can shadow the discovery for a different router and silently misroute
#     - exactly the drift this removal exists to prevent.
#
#   Idempotent: no matching rule -> logs and returns. Best-effort per rule -
#   a transient netsh delete failure is warned, not thrown, so one stuck
#   rule cannot derail the rest of a teardown.
# ---------------------------------------------------------------------------

function Remove-RouterSshPortProxy {
    [CmdletBinding()]
    param(
        # Router VM's reachable IP on the host's Internal vSwitch - the
        # connect target whose relays are removed. The same value the
        # provision side passed to Set-RouterSshPortProxy's -ConnectAddress.
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $ConnectAddress,

        [int]    $ConnectPort = 22
    )

    $stale = @(Get-NetshPortProxyRules | Where-Object {
        $_.ConnectAddress -eq $ConnectAddress -and $_.ConnectPort -eq $ConnectPort
    })

    if ($stale.Count -eq 0) {
        Write-Host ("  [portproxy] no rule forwarding to {0}:{1} - nothing to remove." -f `
            $ConnectAddress, $ConnectPort)
        return
    }

    foreach ($rule in $stale) {
        $listenAddress = $rule.ListenAddress
        $listenPort    = $rule.ListenPort
        Write-Host ("  [portproxy] removing {0}:{1} -> {2}:{3}" -f `
            $listenAddress, $listenPort, $rule.ConnectAddress, $rule.ConnectPort)

        & netsh interface portproxy delete v4tov4 `
            listenaddress=$listenAddress listenport=$listenPort | Out-Null

        # netsh signals failure via exit code, not an exception. A stuck
        # delete leaves a stale rule (re-runnable on the next teardown) but
        # must not abort the wider teardown, so warn and continue.
        if ($LASTEXITCODE -ne 0) {
            Write-Warning ("  [portproxy] netsh delete of {0}:{1} returned exit {2}; rule may persist - re-run deprovision to retry." -f `
                $listenAddress, $listenPort, $LASTEXITCODE)
        }
    }
}
