<#
.NOTES
    Do not run this file directly. Dot-sourced by provision.ps1.
#>

# ---------------------------------------------------------------------------
# Test-HostDnsReachable
#   Asks whether the HOST can resolve at all, via its own configured resolver
#   (no -Server). That is the WiFi-side DNS an ICS proxy forwards to, so this
#   answers a different question than Test-IcsDnsReachable.
#
#   The distinction is load-bearing for diagnosis. If the ICS proxy probe
#   fails but THIS succeeds, the proxy is wedged (toggle / restart / reboot).
#   If THIS also fails, the host's upstream network is down and no amount of
#   ICS toggling will help - the proxy has nothing to forward to.
# ---------------------------------------------------------------------------

function Test-HostDnsReachable {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    Test-DnsProbeName
}
