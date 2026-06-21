BeforeAll {
    . "$PSScriptRoot\..\..\Infrastructure.Network.Windows\Public\Ics\Reset-IcsSharing.ps1"

    function New-FakeShareConfig {
        # Mimics the INetSharingConfigurationForINetConnection COM
        # surface the function exercises. Tracks every method call
        # so tests can assert the canonical "disable both, then
        # enable WAN=0 / LAN=1" sequence.
        param([bool] $Shared)
        $obj = [PSCustomObject]@{
            SharingEnabled = $Shared
            Calls          = [System.Collections.Generic.List[string]]::new()
        }
        $obj | Add-Member -MemberType ScriptMethod -Name DisableSharing -Value {
            $this.Calls.Add('Disable')
        }
        $obj | Add-Member -MemberType ScriptMethod -Name EnableSharing -Value {
            param($mode)
            $this.Calls.Add("Enable:$mode")
        }
        $obj
    }

    function New-FakeHNetCfg {
        # HNetCfg.HNetShare exposes NetConnectionProps and
        # INetSharingConfigurationForINetConnection as COM
        # method-like surfaces the function calls .Invoke() on.
        # Scriptblocks have a native .Invoke method, so returning
        # one from a ScriptProperty gives the function the COM
        # shape it expects without an actual ComObject.
        param([hashtable] $ConfigByName)

        $names = @($ConfigByName.Keys)

        $hnetcfg = [PSCustomObject]@{ EnumEveryConnection = $names }

        $hnetcfg | Add-Member -MemberType ScriptProperty -Name NetConnectionProps -Value {
            { param($n) [PSCustomObject]@{ Name = $n } }
        }

        $cap = $ConfigByName
        $hnetcfg | Add-Member -MemberType ScriptProperty `
            -Name INetSharingConfigurationForINetConnection -Value (
                [scriptblock]::Create("{ param(`$n) `$cfg = @{ $(
                    ($ConfigByName.Keys | ForEach-Object { "'$_' = `$null" }) -join '; '
                ) }; `$cfg[`$n] }")
            )
        # The inline scriptblock above cannot close over $cap easily.
        # Replace via Add-Member -Force with a clean closure-based shape.
        $hnetcfg.psobject.Properties.Remove('INetSharingConfigurationForINetConnection')
        $wrapper = [PSCustomObject]@{ ConfigByName = $cap }
        $wrapper | Add-Member -MemberType ScriptMethod -Name Invoke -Value {
            param($n)
            $this.ConfigByName[$n]
        }
        $hnetcfg | Add-Member -MemberType NoteProperty `
            -Name INetSharingConfigurationForINetConnection -Value $wrapper
        # Same trick for NetConnectionProps so we can call .Invoke($n).Name.
        $hnetcfg.psobject.Properties.Remove('NetConnectionProps')
        $propsWrapper = [PSCustomObject]@{}
        $propsWrapper | Add-Member -MemberType ScriptMethod -Name Invoke -Value {
            param($n)
            [PSCustomObject]@{ Name = $n }
        }
        $hnetcfg | Add-Member -MemberType NoteProperty `
            -Name NetConnectionProps -Value $propsWrapper
        $hnetcfg
    }
}

Describe 'Reset-IcsSharing' {

    BeforeEach {
        $script:wan = New-FakeShareConfig -Shared $true
        $script:lan = New-FakeShareConfig -Shared $true
        $script:hnetcfg = New-FakeHNetCfg -ConfigByName @{
            'Wi-Fi'              = $script:wan
            'vEthernet (Shared)' = $script:lan
        }
        Mock New-Object { $script:hnetcfg } -ParameterFilter { $ComObject -eq 'HNetCfg.HNetShare' }
    }

    It 'disables both connections then enables WAN=Public(0) and LAN=Private(1)' {
        Reset-IcsSharing -WanInterfaceName 'Wi-Fi' `
                         -LanInterfaceName 'vEthernet (Shared)'

        $script:wan.Calls | Should -Be @('Disable', 'Enable:0')
        $script:lan.Calls | Should -Be @('Disable', 'Enable:1')
    }

    It 'skips DisableSharing on a connection that is not currently shared' {
        $script:wan = New-FakeShareConfig -Shared $false
        $script:lan = New-FakeShareConfig -Shared $false
        $script:hnetcfg = New-FakeHNetCfg -ConfigByName @{
            'Wi-Fi'              = $script:wan
            'vEthernet (Shared)' = $script:lan
        }
        Mock New-Object { $script:hnetcfg } -ParameterFilter { $ComObject -eq 'HNetCfg.HNetShare' }

        Reset-IcsSharing -WanInterfaceName 'Wi-Fi' `
                         -LanInterfaceName 'vEthernet (Shared)'

        $script:wan.Calls | Should -Be @('Enable:0')
        $script:lan.Calls | Should -Be @('Enable:1')
    }

    It 'throws when the WAN interface is not found' {
        $script:lan = New-FakeShareConfig -Shared $true
        $script:hnetcfg = New-FakeHNetCfg -ConfigByName @{
            'vEthernet (Shared)' = $script:lan
        }
        Mock New-Object { $script:hnetcfg } -ParameterFilter { $ComObject -eq 'HNetCfg.HNetShare' }

        { Reset-IcsSharing -WanInterfaceName 'Wi-Fi' `
                           -LanInterfaceName 'vEthernet (Shared)' } |
            Should -Throw -ExpectedMessage "*WAN interface 'Wi-Fi' not found*"
    }
}
