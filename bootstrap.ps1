# Exclude Azure VM Agent folders from virus scan (
Set-MpPreference -ExclusionPath 'C:\Packages\', 'C:\WindowsAzure\'
Get-PackageProvider -Name nuget -ForceBootstrap -Force

# Install docker and set machine variable that indicates we have installed it.
# note: setting the machine variable does not update the enviroment of the current process.
#Install-Module -Name DockerMsftProvider -Force
#Install-Package -Name docker -ProviderName DockerMsftProvider -Force
#[System.Environment]::SetEnvironmentVariable('DOCKER',"Staged",'Machine')

# Set the machine to use microsoft Update and install security updates
Get-PackageSource | Set-PackageSource -Trusted -ErrorAction SilentlyContinue
Install-module -Name xWindowsUpdate -Confirm:$false
Install-Module -Name xPSDesiredStateConfiguration  -Confirm:$false
Install-Module -Name xStorage -Confirm:$false
Install-Module -Name PSDscResources -Confirm:$false
Install-Module -Name DockerMsftProvider  -Confirm:$false
Install-Module -Name PackageManagementProviderResource
Get-PackageSource | Set-PackageSource -Trusted -ErrorAction SilentlyContinue

find-package -ProviderName DockerMsftProvider -MinimumVersion 17.06.1-ee | install-package -force

[DscLocalConfigurationManager()]
configuration LCM {
  Settings {
    RebootNodeIfNeeded = $true
    ActionAfterReboot = 'ContinueConfiguration'
    ConfigurationMode = 'ApplyOnly'
  }
}

LCM
Set-DscLocalConfigurationManager -Path .\LCM -Verbose



# run Install-ContainerHost.ps1
Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/TravisEz13/VstsDockerAgentBootstrap/master/install-containerhost.ps1'))

#'{ "hosts": ["tcp://127.0.0.1:2375"] }'|out-file -Encoding ascii -FilePath "$env:programdata/Docker/config/daemon.json"		
#[System.Environment]::SetEnvironmentVariable('DOCKER_HOST',"tcp://localhost:2375",'Machine')

# reboot if the current process doesn't have the variable that indicates docker was installed
#if($env:DOCKER -notin @('Staged','Installed'))
#{
#  Restart-Computer -force
#}
