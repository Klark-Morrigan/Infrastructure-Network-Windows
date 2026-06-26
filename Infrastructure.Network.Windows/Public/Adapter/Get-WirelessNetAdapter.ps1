<#
.NOTES
    Do not run this file directly. Dot-sourced by the module psm1.
#>

# ---------------------------------------------------------------------------
# Get-WirelessNetAdapter
#   Single source of truth for "which physical adapters are Wi-Fi" on a
#   Windows host. Returns the Get-NetAdapter objects whose driver
#   description identifies them as wireless, so callers can compare MACs,
#   resolve a connection name, or check link state without each carrying
#   its own copy of the match (which would let the matcher drift).
#
#   Match is on InterfaceDescription, not Name: the connection name
#   varies by host ('Wi-Fi', 'Wi-Fi 2', a vendor name) while the driver
#   description reliably carries 'Wi-Fi' / 'Wireless'. This is the same
#   connection name Reset-IcsSharing matches on via HNetCfg, so the Name
#   of an adapter returned here can feed that function's WAN interface
#   parameter directly.
#
#   Returns nothing (not an error) on hosts with no wireless NIC, so
#   callers can treat an empty result as "no Wi-Fi present".
# ---------------------------------------------------------------------------

function Get-WirelessNetAdapter {
    [CmdletBinding()]
    param()

    # -ErrorAction SilentlyContinue: Get-NetAdapter throws when no
    # adapters match its filter on some hosts; an empty wireless set is
    # a valid state (wired-only / headless), so swallow it here and let
    # callers branch on the empty result.
    Get-NetAdapter -Physical -ErrorAction SilentlyContinue |
        Where-Object { $_.InterfaceDescription -match 'Wi-?Fi|Wireless' }
}
