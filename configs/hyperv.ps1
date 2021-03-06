configuration hyperv {

    param (

        [Parameter(Mandatory)]
        [String]$AzSecPackRole,

        [Parameter(Mandatory)]
        [String]$AzSecPackAcct,

        [Parameter(Mandatory)]
        [String]$AzSecPackNS,

        [Parameter(Mandatory)]
        [String]$AzSecPackCert
    )

    Import-DscResource -ModuleName PsDesiredStateConfiguration
    Import-DscResource -ModuleName ComputerManagementDsc
    Import-DSCResource -ModuleName StorageDsc
    Import-DscResource -ModuleName SChannelDsc

    node localhost {

        $AzSecPackCMD = "
        set MONITORING_DATA_DIRECTORY=C:\Monitoring\Data
        set MONITORING_TENANT=%USERNAME%
        set MONITORING_ROLE=$AzSecPackRole
        set MONITORING_ROLE_INSTANCE=%COMPUTERNAME%
        set MONITORING_GCS_ENVIRONMENT=DiagnosticsProd
        set MONITORING_GCS_ACCOUNT=$AzSecPackAcct
        set MONITORING_GCS_NAMESPACE=$AzSecPackNS
        set MONITORING_GCS_REGION=centralus
        set MONITORING_GCS_AUTH_ID_TYPE=AuthKeyVault
        set MONITORING_GCS_AUTH_ID=$AzSecPackCert
        set MONITORING_CONFIG_VERSION=1.0
        %MonAgentClientLocation%\MonAgentClient.exe -useenv"

        Protocol DisableTLS10 {
            Protocol = "TLS 1.0"
            State    = "Disabled"
        }

        Protocol DisableTLS11 {
            Protocol = "TLS 1.1"
            State    = "Disabled"
        }

        Protocol DisableSSL20 {
            Protocol = "SSL 2.0"
            State    = "Disabled"
        }

        Protocol DisableSSL30 {
            Protocol = "SSL 3.0"
            State    = "Disabled"
        }

        Protocol EnableTLS12 {
            Protocol = "TLS 1.2"
            State    = "Enabled"
        }

        Registry EnableTLS12 {
            Ensure = "Present"
            Key = "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Server"
            ValueName = "Enabled"
            ValueData = "1"
            ValueType = "Dword"
        }

        CipherSuites ConfigureCipherSuites {
            IsSingleInstance  = 'Yes'
            CipherSuitesOrder = @('TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA384,TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA256,TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA384,TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA256')
            Ensure            = "Present"
        }

        File AzSecPackDir {
            Ensure          = 'Present'
            Type            = 'Directory'
            DestinationPath = 'c:\Monitoring'
        }

        File AzSecPackCMD {
            Ensure          = 'Present'
            Type            = 'File'
            DestinationPath = 'c:\Monitoring\runagentClient.cmd'
            Contents        = $AzSecPackCMD
            DependsOn       = '[File]AzSecPackDir'
        }

        ScheduledTask AzSecPack {
            TaskName            = 'Geneva'
            ScheduleType        = 'AtStartup'
            ActionExecutable    = 'C:\Monitoring\runagentClient.cmd'
            BuiltInAccount      = 'System'
        }

        WindowsFeature Hyper-V {
            Ensure = "Present"
            Name = "Hyper-V"
            IncludeAllSubFeature = $true
        }

        WindowsFeature Hyper-V-Tools {
            Ensure = "Present"
            Name = "Hyper-V-Tools"
            IncludeAllSubFeature = $true
        }

        WindowsFeature Hyper-V-PowerShell {
            Ensure = "Present"
            Name = "Hyper-V-PowerShell"
            IncludeAllSubFeature = $true
        }
       
        # Need to use script to configure Hyper-V NAT
        Script natConfig {
            SetScript = {
                New-VMSwitch -Name "NATSwitch" -SwitchType Internal
                $interface = Get-NetAdapter | where-object {$_.Name -like "*NATSwitch*"}
                New-NetIPAddress -IPAddress 192.168.0.1 -PrefixLength 24 -InterfaceIndex $interface.ifIndex
                New-NetNat -Name "InternalNATnet" -InternalIPInterfaceAddressPrefix 192.168.0.0/24
            }
            TestScript = { 
                if (Get-VMSwitch -Name "NATSwitch" -ErrorAction SilentlyContinue) {
                    return $true
                } else {
                   return $false
                } 
            }
            GetScript  = { @{} }
        }
    }
}