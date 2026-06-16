<#
.NOTES
    Do not run this file directly. Dot-sourced by provision.ps1.
#>

# ---------------------------------------------------------------------------
# Set-RouterSshPortProxy
#   Ensures a host-side netsh portproxy rule forwarding
#   <ListenAddress>:<ListenPort> (typically 127.0.0.1:2222) to
#   <ConnectAddress>:<ConnectPort> (the router VM's SSH endpoint).
#   Refreshes on every run: deletes any rule already bound to the
#   listen target and re-adds it - even when the connect target is
#   unchanged - then adds fresh when none exists. The unconditional
#   re-add is load-bearing; see the body for why a "skip when
#   identical" optimisation strands the relay across a reprovision.
#
#   Why this matters: WSL2 runs as a separate Hyper-V guest with its
#   own NAT subnet. Outbound from WSL to the host's Internal-vSwitch
#   subnet (e.g. 192.168.137.0/24, the ICS-served network) is not
#   forwarded by default - ICS NAT is set up for WSL -> Internet via
#   the WAN, not WSL -> peer VM via the LAN side. A localhost port
#   proxy on the host turns the cross-subnet hop into a same-host
#   loopback that WSL can always reach. Ansible's ProxyCommand
#   (sshpass + ssh routeradmin@<host-port>) then succeeds.
#
#   The rule text persists across reboots AND across VM/switch
#   teardowns (netsh portproxy state lives in
#   HKLM\SYSTEM\CurrentControlSet\Services\PortProxy) - which is
#   precisely why the re-add is unconditional: a persisted rule whose
#   target router and Internal vSwitch were recreated keeps stale
#   iphlpsvc forwarding behind unchanged rule text.
# ---------------------------------------------------------------------------

function Set-RouterSshPortProxy {
    [CmdletBinding()]
    param(
        # Host-side listen target. 0.0.0.0 (all interfaces) is the
        # default because WSL2 in default NAT mode cannot reach the
        # host's 127.0.0.1 - from inside WSL, `127.0.0.1` is WSL's
        # own loopback, NOT the host's. WSL can reach the host on
        # its WSL-side vEthernet IP, which 0.0.0.0 covers. Operators
        # who don't need WSL access can pin it back to 127.0.0.1 for
        # tighter isolation. Windows Firewall still gates inbound on
        # 2222 - the LAN-facing surface is only as open as the
        # firewall profile allows.
        [string] $ListenAddress = '0.0.0.0',

        [int]    $ListenPort    = 2222,

        # Router VM's reachable IP on the host's Internal vSwitch
        # (typically the routerExternalIp from secret.json).
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $ConnectAddress,

        [int]    $ConnectPort   = 22
    )

    $existing = Get-NetshPortProxyRules |
                Where-Object {
                    $_.ListenAddress -eq $ListenAddress -and
                    $_.ListenPort    -eq $ListenPort
                } | Select-Object -First 1

    if ($existing) {
        # Delete-and-re-add unconditionally, even when the connect target
        # is unchanged. The rule text survives a router/switch teardown,
        # but iphlpsvc binds the forwarding behind it to the network
        # generation live when the rule was added. E2E (and any
        # reprovision) destroys and recreates the router VM and its
        # Internal vSwitch, leaving a rule that LOOKS correct but whose
        # relay is stale: WSL reaches the listener, the onward hop to the
        # recreated router never delivers, and Ansible only surfaces an
        # opaque "Connection timed out during banner exchange"
        # UNREACHABLE. Re-adding forces iphlpsvc to re-register the
        # forwarding against the current generation. The former "skip
        # when the rule is identical" optimisation is what stranded it.
        Write-Host ("  [portproxy] {0}:{1} present (-> {2}:{3}); refreshing via delete + re-add to rebind the relay." -f `
            $ListenAddress, $ListenPort,
            $existing.ConnectAddress, $existing.ConnectPort)
        & netsh interface portproxy delete v4tov4 `
            listenaddress=$ListenAddress listenport=$ListenPort | Out-Null
    } else {
        Write-Host ("  [portproxy] adding {0}:{1} -> {2}:{3}" -f `
            $ListenAddress, $ListenPort, $ConnectAddress, $ConnectPort)
    }

    # The add is retry-wrapped. netsh portproxy add can fail transiently
    # when iphlpsvc is momentarily busy, and because the delete above has
    # already run, a single hard failure would strand the listen target
    # with NO rule at all - strictly worse than the stale rule we are
    # refreshing. A short bounded retry absorbs the transient case; a
    # genuine failure still throws after the final attempt. netsh signals
    # failure through its exit code (not an exception), so this uses
    # Common.PowerShell's Invoke-WithExitCodeRetry (the exit-code sibling
    # of Invoke-WithRetry): its contract is that the script block's final
    # statement is the native command whose $LASTEXITCODE drives the loop.
    Invoke-WithExitCodeRetry `
        -OperationName "netsh portproxy add ${ListenAddress}:${ListenPort} -> ${ConnectAddress}:${ConnectPort}" `
        -ScriptBlock {
            & netsh interface portproxy add v4tov4 `
                listenaddress=$ListenAddress listenport=$ListenPort `
                connectaddress=$ConnectAddress connectport=$ConnectPort | Out-Null
        }
}
