<#
.NOTES
    Do not run this file directly. Dot-sourced by provision.ps1.
#>

# ---------------------------------------------------------------------------
# Test-IcsDnsReachable
#   Asks whether a SPECIFIC resolver answers - typically the ICS DNS proxy on
#   the host-side vEthernet IP, the exact UDP/53 path a VM on that switch is
#   about to use. $true only when that resolver answered cleanly; see
#   Test-DnsProbeName for why every error reduces to $false.
#
#   Kept as a named wrapper rather than folding callers onto the private
#   helper: the name is what makes a call site readable as the question being
#   asked, and it is the mockable seam the preflight's tests pin.
# ---------------------------------------------------------------------------

function Test-IcsDnsReachable {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Server
    )

    Test-DnsProbeName -Server $Server
}
