
param(
    [Switch] $DataDrive,
    [ValidateSet('hyperv','default','process')]
    [string]
    $Isolation = 'hyperv'
  )
function Get-daemonJson
{
    param(
        [string[]]
        $Hosts = "tcp://127.0.0.1:2375",
        [ValidateSet('hyperv','default','process')]
        [string]
        $Isolation = 'hyperv',
        [string]
        $DataRoot
    )
    $config = @{}
    if($Hosts)
    {
        $config['hosts']=$Hosts
    }

    $execOpts = @()
    if($Isolation)
    {
        $execOpts += "isolation=$Isolation"
    }

    if($execOpts.Length -gt 0)
    {
        $config['exec-opts'] = $execOpts
    }

    if($DataRoot)
    {
        $config['data-root'] = $DataRoot
    }

    $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) -childPath 'dockerConfigSource'
    New-Item -ItemType Directory -Path $tempDir -Force > $null
    $configFile = Join-Path $tempDir -ChildPath 'config.json'
    $config | Out-File -Path $configFile -Encoding ascii -Force
    
    return $configFile    
}

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

        $DataRoot = $null
        if($DataDrive.IsPresent)
        {
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

            $DataRoot = 'F:\dockerdata'
            File DockerDataFolder {
                Ensure         = "Present"
                DestinationPath = $DataRoot
                Type = 'Directory'
                DependsOn='[xDisk]DockerDataDisk'
            }
        }

        File DockerStaging {
             Ensure         = "Present"
             DestinationPath = 'C:\dockerstaging'
             Type = 'Directory'
        }

        File DockerConfigFolder {
            DestinationPath = "$env:programdata\Docker\config"
            Type = 'Directory'
        }

        File DockerDaemonJson
        {
            DestinationPath = "$env:programdata\Docker\config\daemon.json"
            SourcePath = (Get-daemonJson -Isolation $Isolation -DataRoot $DataRoot)
	    Checksum = SHA-1
            MatchSource = $true
            DependsOn = @(
                '[File]DockerConfigFolder'
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
