
param(
    [Switch] $DataDrive,
    [Switch] $SkipWua,
    [ValidateSet('hyperv','default','process')]
    [string]
    $Isolation = 'hyperv',
    [string]
    $AgentUser = ([System.Security.Principal.WindowsIdentity]::GetCurrent().Name),
    [string]
    $DockerGroup = 'DockerUsers'
  )
[Environment]::SetEnvironmentVariable('DOCKER_HOST',$null,'Machine')
function Get-daemonJson
{
    param(
        [string[]]
        $Hosts = "tcp://127.0.0.1:2375",
        [ValidateSet('hyperv','default','process')]
        [string]
        $Isolation = 'hyperv',
        [string]
        $DataRoot,
        [string]
        $Group
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

    $tempDir = "$env:programdata\Docker\config\"
    New-Item -ItemType Directory -Path $tempDir -Force > $null
    $configFile = Join-Path $tempDir -ChildPath 'daemon-desired-state.json'
    $config | ConvertTo-Json -Depth 10 | Out-File -FilePath $configFile -Encoding ascii -Force
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

        # config file must be ascii
	# so you cannot use contents
        File DockerDaemonJson
        {
            DestinationPath = "$env:programdata\Docker\config\daemon.json"
            SourcePath = (Get-daemonJson -Isolation $Isolation -DataRoot $DataRoot -Hosts $null -Group $DockerGroup)
	    Checksum = 'SHA-1'
            MatchSource = $true
            DependsOn = @(
                '[File]DockerConfigFolder'
            )
        }

        Environment DockerHost {
            Name = "DOCKER_HOST"
            Value = ""
        }

        Group DockerGroup
        {
            GroupName = $DockerGroup
            Ensure = 'Present'
            Members = @( $AgentUser )
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
                '[Group]DockerGroup'
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

	Environment MemoryGB {
            Name = "MemoryGB"
            Value = ([int]((Get-CimInstance win32_computersystem).TotalPhysicalMemory /1GB))
        }

	Environment CpuCoreCount {
            Name = "CpuCoreCount"
            Value = (Get-CimInstance -class win32_processor | Measure-Object -Property NumberOfLogicalProcessors -Sum | Select-Object -ExpandProperty Sum)
        }

        Registry VSmbDisableOplocks {
          Ensure = 'Present'
          Key = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Virtualization\Containers'
          ValueName = 'VSmbDisableOplocks'
          ValueData = 1
          ValueType = 'Dword'
        }

        if(!$SkipWua.IsPresent)
	{
		xWindowsUpdateAgent wua {
		    IsSingleInstance = 'Yes'
		    UpdateNow        = $true
		    Category         = @('Security')
		    Source           = 'MicrosoftUpdate'
		}
	}
    }
}

$configFile = Win10ContainerHost
Start-DscConfiguration .\Win10ContainerHost -Wait -Verbose -Force
