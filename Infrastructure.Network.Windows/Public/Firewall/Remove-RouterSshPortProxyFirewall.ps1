<#
.NOTES
    Do not run this file directly. Dot-sourced by deprovision.ps1.
#>

# ---------------------------------------------------------------------------
# Remove-RouterSshPortProxyFirewall
#   Teardown counterpart to Set-RouterSshPortProxyFirewall. Removes the
#   inbound allow rule that companion creates for the WSL -> router SSH
#   portproxy, so the firewall surface is torn down symmetrically with the
#   portproxy itself rather than lingering after the router is gone.
#
#   The DisplayName MUST match Set-RouterSshPortProxyFirewall's exactly -
#   that name (keyed on the listen port) is the rule's identity. ListenPort
#   defaults to 2222, the same default the setter uses.
#
#   Gated on a WSL adapter being present, mirroring the setter: the rule is
#   only ever created when WSL is installed, the Windows Firewall cmdlets do
#   not exist off-Windows (so the Pester suite on Linux/Mac exercises the
#   gate as a clean no-op), and a Windows dev box without WSL has no rule to
#   remove. Idempotent: absent rule -> logs and returns.
# ---------------------------------------------------------------------------

function Remove-RouterSshPortProxyFirewall {
    [CmdletBinding()]
    param(
        # Listen port whose rule is removed. Must match the
        # Set-RouterSshPortProxyFirewall listen port - same default.
        [int] $ListenPort = 2222
    )

    # Presence signal only (same gate as the setter). Get-NetAdapter returns
    # nothing on hosts without WSL and does not exist on Linux/Mac, so this
    # also keeps the helper a clean no-op under the cross-platform test run.
    $wslAdapter = Get-NetAdapter -ErrorAction SilentlyContinue |
                  Where-Object { $_.Name -like 'vEthernet (WSL*' } |
                  Select-Object -First 1

    if (-not $wslAdapter) {
        Write-Host "  [firewall] no vEthernet (WSL*) adapter found; skipping firewall removal (WSL probably not installed)."
        return
    }

    $ruleName = "Vm-Provisioner: WSL -> router SSH portproxy (TCP/$ListenPort)"

    $existing = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
    if (-not $existing) {
        Write-Host "  [firewall] no inbound rule '$ruleName' - nothing to remove."
        return
    }

    Write-Host "  [firewall] removing inbound rule '$ruleName'."
    Remove-NetFirewallRule -DisplayName $ruleName
}
