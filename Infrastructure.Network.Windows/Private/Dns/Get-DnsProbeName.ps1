<#
.NOTES
    Do not run this file directly. Dot-sourced by the module psm1. Internal:
    not exported, so callers outside the module cannot pin themselves to the
    probe name.
#>

# ---------------------------------------------------------------------------
# Get-DnsProbeName
#   The hostname every DNS probe in this module resolves, and the one any
#   operator-facing message prints. One source for both: a message that
#   suggested a different name than the probe used would tell the operator to
#   verify something other than what failed.
#
#   archive.ubuntu.com is the choice because it is what a freshly provisioned
#   VM must resolve first - cloud-init's apt phase reaches for it - so a
#   successful probe proves the path the VM actually needs rather than an
#   arbitrary reachable name.
# ---------------------------------------------------------------------------

function Get-DnsProbeName {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    'archive.ubuntu.com'
}
