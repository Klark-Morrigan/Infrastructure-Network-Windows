<#
.NOTES
    Do not run this file directly. Dot-sourced by the module psm1. Internal:
    the exported probes (Test-IcsDnsReachable / Test-HostDnsReachable) are the
    supported surface, and they read as the question each caller is asking.
#>

# ---------------------------------------------------------------------------
# Test-DnsProbeName
#   The one resolve behind both exported probes. They ask different questions -
#   "does THIS resolver answer" versus "can the host resolve at all" - but the
#   mechanics are identical, and when they were written out twice a change to
#   the error contract or the probe name could land in one and not the other.
#
#   Any error - RST, timeout, NXDOMAIN, missing module - reduces to $false,
#   because the only thing a caller cares about is "the path answers cleanly".
#   A proxy returning NXDOMAIN is just as broken as one timing out, since the
#   name is a stable real-world host the module picks (see Get-DnsProbeName).
# ---------------------------------------------------------------------------

function Test-DnsProbeName {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        # Resolver to ask. Omitted means the host's own configured resolver,
        # which is a different question rather than a default value - see the
        # two exported wrappers.
        [string] $Server
    )

    try {
        # Splatted so the host-side call OMITS -Server entirely. Passing it as
        # an empty string is not the same thing: Resolve-DnsName would reject
        # it, turning "ask the host's resolver" into a silent $false.
        $params = @{
            Name        = Get-DnsProbeName
            DnsOnly     = $true
            ErrorAction = 'Stop'
        }
        if ($Server) { $params['Server'] = $Server }

        return [bool](Resolve-DnsName @params)
    } catch {
        return $false
    }
}
