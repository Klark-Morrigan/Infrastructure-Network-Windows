<#
.NOTES
    Do not run this file directly. Dot-sourced by the module psm1.
#>

# ---------------------------------------------------------------------------
# Set-RouterSshRelay
#   Establishes the full controller -> router SSH relay: the host-side
#   netsh portproxy (Set-RouterSshPortProxy) AND its Windows Firewall
#   companion (Set-RouterSshPortProxyFirewall), which are an inseparable
#   pair. The portproxy alone listens but Windows silently drops WSL's
#   inbound packets without the firewall allow, surfacing later only as
#   the opaque "Connection timed out during banner exchange" Ansible
#   UNREACHABLE. Wrapping both behind one call means no caller can lay
#   the portproxy and forget the firewall - the bug this guards against.
#
#   Both inner calls are idempotent delete+re-adds, so re-invoking when
#   nothing changed is harmless, and the firewall half no-ops on hosts
#   without a WSL adapter.
#
#   Ports use the inner functions' defaults (host 2222 -> router 22). A
#   caller needing to override the listen port must add a -ListenPort
#   parameter here and forward it to BOTH inner calls, so the portproxy
#   and the firewall rule stay on the same port - never split this back
#   into two separate calls to change one of them.
#
#   -FirewallOnly lays just the firewall half and skips the portproxy.
#   It exists for the pre-VM-creation phase, where a router whose IP is
#   not yet known (DHCP) still wants its inbound allow pre-laid so the
#   relay is ready the instant the portproxy follows once its IP is
#   known. The firewall rule is independent of the router IP, so laying
#   it early is valid; the portproxy, which needs a connect target, is
#   not laid until the IP is known.
# ---------------------------------------------------------------------------

function Set-RouterSshRelay {
    [CmdletBinding(DefaultParameterSetName = 'Full')]
    param(
        # Router VM's reachable IP on the host's Internal vSwitch - the
        # portproxy's connect target. Passed straight through to
        # Set-RouterSshPortProxy.
        [Parameter(Mandatory, ParameterSetName = 'Full')]
        [ValidateNotNullOrEmpty()]
        [string] $ConnectAddress,

        # Lay only the firewall companion, skipping the portproxy. Used
        # when the router IP is not yet known so the inbound allow is
        # pre-laid ahead of the portproxy. Mutually exclusive with
        # -ConnectAddress via parameter sets.
        [Parameter(Mandatory, ParameterSetName = 'FirewallOnly')]
        [switch] $FirewallOnly
    )

    # Portproxy needs a connect target, so it is laid only in the Full
    # set; the firewall is always laid (both sets reach it).
    if ($PSCmdlet.ParameterSetName -eq 'Full') {
        Set-RouterSshPortProxy -ConnectAddress $ConnectAddress
    }
    Set-RouterSshPortProxyFirewall
}
