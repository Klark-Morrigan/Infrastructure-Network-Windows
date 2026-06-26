<#
.NOTES
    Do not run this file directly. Dot-sourced by the module psm1.
#>

# ---------------------------------------------------------------------------
# Remove-RouterSshRelay
#   Teardown counterpart to Set-RouterSshRelay: removes the host-side
#   netsh portproxy (Remove-RouterSshPortProxy) AND its Windows Firewall
#   companion (Remove-RouterSshPortProxyFirewall) for a router being torn
#   down, so the relay surface comes down symmetrically with the way it
#   went up. Pairing both behind one call mirrors Set-RouterSshRelay and
#   stops a caller from sweeping the portproxy while leaving the firewall
#   rule (or vice versa) lingering after the router is gone.
#
#   Both inner removers are idempotent (absent rule -> log + return) and
#   best-effort (a stuck netsh delete is warned, not thrown), so a
#   half-present relay or a re-run is handled cleanly. The portproxy is
#   keyed on the CONNECT target (router IP), the firewall on the listen
#   port - see each inner remover for why.
# ---------------------------------------------------------------------------

function Remove-RouterSshRelay {
    [CmdletBinding()]
    param(
        # Router VM's reachable IP whose relays are removed - the same
        # value the provision side passed to Set-RouterSshRelay's
        # -ConnectAddress. Forwarded to Remove-RouterSshPortProxy.
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $ConnectAddress,

        # Router SSH port the portproxy forwards to. Matches
        # Set-RouterSshPortProxy's default.
        [int] $ConnectPort = 22,

        # Listen port whose firewall rule is removed. Matches
        # Set-RouterSshPortProxyFirewall's default.
        [int] $ListenPort = 2222
    )

    Remove-RouterSshPortProxy -ConnectAddress $ConnectAddress -ConnectPort $ConnectPort
    Remove-RouterSshPortProxyFirewall -ListenPort $ListenPort
}
