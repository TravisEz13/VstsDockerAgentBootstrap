
configuration Win10ContainerHost {
    Import-DscResource -ModuleName xPSDesiredStateConfiguration -Name xRemoteFile
    Import-DscResource -ModuleName PSDscResources
    Import-DscResource -ModuleName xWindowsUpdate
    Import-DscResource -ModuleName xStorage
    Import-DscResource -Module PackageManagementProviderResource    
    
    node localhost {
        WindowsFeature hyperv
        {
            Name = 'hyper-v'
            Ensure = 'Present'
        }
        xWaitforDisk Disk2
        {
            DiskId = 2
            RetryIntervalSec = 60
            RetryCount = 30
        }
        
        xDisk DockerDataDisk
        {
            DiskId = 2
            DriveLetter = 'F'
	        DependsOn='[xWaitForDisk]Disk2'
        }

        File DockerDataFolder {
             Ensure         = "Present"
             DestinationPath = 'F:\dockerdata'
             Type = 'Directory'
	         DependsOn='[xDisk]DockerDataDisk'
        }

        File DockerStaging {
             Ensure         = "Present"
             DestinationPath = 'C:\dockerstaging'
             Type = 'Directory'
        }
        
        xRemoteFile DockerConfigStaging {
          DestinationPath = 'C:\dockerstaging\daemon.json'
          Uri = 'https://raw.githubusercontent.com/TravisEz13/VstsDockerAgentBootstrap/master/daemon.json'
          DependsOn = '[File]DockerStaging'
        }
        
        File DockerConfigFolder {
            DestinationPath = "$env:programdata\Docker\config"
            Type = 'Directory'
        }

        File DockerDaemonJson
        {
            SourcePath = 'C:\dockerstaging\daemon.json'
            DestinationPath = "$env:programdata\Docker\config\daemon.json"
            Checksum = 'SHA-512'
            MatchSource = $true
            DependsOn = @(
                '[File]DockerConfigFolder'
                '[xRemoteFile]DockerConfigStaging'
            )
        }

        Environment DockerHost {
            Name = "DOCKER_HOST"
            Value = "tcp://localhost:2375"
        }
        
        Environment DockerEnv {
          Path = $true
          Name = 'Path'
          Value = 'C:\Program Files\docker\'
        }

        Service DockerD
        {
            Name = 'Docker'
            Ensure = 'Present'
            StartupType = 'Automatic'
            State = 'Running'
            DependsOn = @(
                '[File]DockerDaemonJson'
                '[WindowsFeature]hyperv'
              )
        }
        
        Script DockerServer 
        {
          GetScript = {
            $DockerVersion = 'NotInstalled'
            $isolation = 'default'
            try {
                $DockerVersion = docker version --format '{{.Server.Version}}'
                $runtimeIsolation = docker info --format '{{.Isolation}}'
		$dockerRoot = docker info --format '{{ .DockerRootDir }}'
                if($runtimeIsolation)
                {
                    $isolation = $runtimeIsolation
                }
            }
            catch 
            {
            }
            $envValue = [System.Environment]::GetEnvironmentVariable('DOCKER_SERVER','Machine')
            $result = @($envValue, $DockerVersion, $isolation, $dockerRoot)
            return @{
              GetScript = $GetScript
              SetScript = $SetScript
              TestScript = $TestScript
              Result = $Result
            }
          }
          SetScript = {
            $DockerVersion = 'NotInstalled'
            $isolation = 'default'
            try {
                $DockerVersion = docker version --format '{{.Server.Version}}'
                $runtimeIsolation = docker info --format '{{.Isolation}}'
		$dockerRoot = docker info --format '{{ .DockerRootDir }}'
                if($runtimeIsolation)
                {
                    $isolation = $runtimeIsolation
                }
            }
            catch 
            {
            }
            [System.Environment]::SetEnvironmentVariable('DOCKER_SERVER',$DockerVersion,'Machine')
            [System.Environment]::SetEnvironmentVariable('DOCKER_ISOLATION',$isolation,'Machine')
            [System.Environment]::SetEnvironmentVariable('DOCKER_ROOT',$dockerRoot,'Machine')
            $global:DSCMachineStatus = 1
          }
          TestScript = {
            $DockerVersion = 'NotInstalled'
            $isolation = 'default'
            try {
                $DockerVersion = docker version --format '{{.Server.Version}}'
                $runtimeIsolation = docker info --format '{{.Isolation}}'
		$dockerRoot = docker info --format '{{ .DockerRootDir }}'
                if($runtimeIsolation)
                {
                    $isolation = $runtimeIsolation
                }
            }
            catch 
            {
            }
            $envValue = [System.Environment]::GetEnvironmentVariable('DOCKER_SERVER','Machine')
            $envIsolationValue = [System.Environment]::GetEnvironmentVariable('DOCKER_ISOLATION','Machine')
            $envRootValue = [System.Environment]::GetEnvironmentVariable('DOCKER_ROOT','Machine')
            return ($DockerVersion -eq $envValue -and $isolation -eq $envIsolationValue -and $envRootValue -eq $dockerRoot)
          }
          DependsOn = "[Service]DockerD"        
        }
        
        Environment Docker {
            Name = "DOCKER"
            Value = "Installed"
            DependsOn = "[Service]DockerD"
        }

        Registry VSmbDisableOplocks {
          Ensure = 'Present'
          Key = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Virtualization\Containers'
          ValueName = 'VSmbDisableOplocks'
          ValueData = 1
          ValueType = 'Dword'
        }

        xWindowsUpdateAgent wua {
            IsSingleInstance = 'Yes'
            UpdateNow        = $true
            Category         = @('Security')
            Source           = 'MicrosoftUpdate'
        }
    }
}
Win10ContainerHost
Start-DscConfiguration .\Win10ContainerHost -Wait -Verbose -Force
