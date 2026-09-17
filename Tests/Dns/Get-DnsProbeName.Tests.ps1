BeforeAll {
    . "$PSScriptRoot\..\..\Infrastructure.Network.Windows\Private\Dns\Get-DnsProbeName.ps1"
}

Describe 'Get-DnsProbeName' {

    # Pinned because the value is not free: operator-facing messages print it
    # as a command to run, and a VM's first real DNS need is the Ubuntu
    # archive. Changing it is a decision, not a detail.
    It 'returns the Ubuntu archive host' {
        Get-DnsProbeName | Should -Be 'archive.ubuntu.com'
    }

    It 'returns a single string, not a collection' {
        # Callers interpolate the result straight into commands; an array
        # would render as a space-joined mess rather than failing loudly.
        @(Get-DnsProbeName).Count | Should -Be 1
        Get-DnsProbeName          | Should -BeOfType [string]
    }
}
