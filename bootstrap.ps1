param(
  [Switch] $DataDrive,
  [Switch] $SkipWua,
  [ValidateSet('hyperv','default','process')]
  [string]
  $Isolation = 'hyperv'
)
Write-Verbose -message ('Running Vsts Docker Agent Bootstrap: DataDrive: ''{0}'' SkipWua: ''{1}'' Isolation: ''{2}''' -f $DataDrive.IsPresent, $SkipWua.IsPresent, $Isolation) -verbose
# Exclude Azure VM Agent folders from virus scan (
Write-Verbose -message 'Setting up defender preferences...' -verbose
$null = Set-MpPreference -ExclusionPath 'C:\Packages\', 'C:\WindowsAzure\'
Write-Verbose -message 'Bootstrapping nuget...' -verbose
$null = Get-PackageProvider -Name nuget -ForceBootstrap -Force

# Install docker and set machine variable that indicates we have installed it.
# note: setting the machine variable does not update the enviroment of the current process.
#Install-Module -Name DockerMsftProvider -Force
#Install-Package -Name docker -ProviderName DockerMsftProvider -Force
#[System.Environment]::SetEnvironmentVariable('DOCKER',"Staged",'Machine')

Write-Verbose -message 'Setting package sources as trusted...' -verbose
$null = Get-PackageSource | Set-PackageSource -Trusted -ErrorAction SilentlyContinue

$moduleList = @(
  'xWindowsUpdate'
  'xPSDesiredStateConfiguration'
  'xStorage'
  'PSDscResources'
  'DockerMsftProvider'
  'PackageManagementProviderResource'
)

foreach($module in $moduleList)
{
  if(Get-module -listAvailable -name $module -ErrorAction SilentlyContinue)
  {
    Write-Verbose -message "Updating module $module (in case of re-run)..." -verbose
    Update-Module -name $module -ErrorAction SilentlyContinue
  }
}

Write-Verbose -message "Checking for side by side resources, DSC doesn't like this.." -verbose
foreach($module in $moduleList)
{
  $versions=Get-InstalledModule -AllVersions -Name $module -ErrorAction SilentlyContinue
  $count = $versions.count -1
  if($count -ge 1)
  {
    Write-Verbose -message "Removing duplicate version of $module ..." -verbose
    $versions | 
      ForEach-Object {
        $netVer = [Version]$_.Version 
        Add-Member -MemberType NoteProperty -Name NetVersion -Value $netVer -InputObject $_
        $_
      }| 
        Sort-Object -Property NetVersion -Descending | 
          Select-Object -Last $Count | 
            Uninstall-Module    
  }
}



# Set the machine to use microsoft Update and install security updates
foreach($module in $moduleList)
{
  if(!(Get-module -listAvailable -name $module -ErrorAction SilentlyContinue))
  {
    Write-Verbose -message "Installing module $module ..." -verbose
    Install-module -Name $module -Confirm:$false
  }
}


Write-Verbose -message 'Setting DockerMsftProvider sources as trusted...' -verbose
$null = Get-PackageSource | Set-PackageSource -Trusted -ErrorAction SilentlyContinue

# version 17.06.2-ee-7-tp2 was broken
Write-Verbose -message 'Finding docker package...' -verbose
$dockerPackage = find-package -ProviderName DockerMsftProvider -MinimumVersion 17.06.2-ee  -AllVersions | 
  Where-Object {$_.Version -notin '17.06.2-ee-7-tp2','17.06.2-ee-5','17.06.2-ee-7'} | 
    Sort-Object -Property Version -Descending | 
      Select-Object -First 1

Write-Verbose -message "Installing docker: $($docker.Name)-$($docker.Version)..." -verbose

        $dockerPackage | Install-Package -force -PackageManagementProvider DockerMsftProvider

Write-Verbose -message 'Configuring LCM...' -verbose
[DscLocalConfigurationManager()]
configuration LCM {
  Settings {
    RebootNodeIfNeeded = $true
    ActionAfterReboot = 'ContinueConfiguration'
    ConfigurationMode = 'ApplyOnly'
  }
}

$metaFile = LCM
Set-DscLocalConfigurationManager -Path .\LCM -Verbose

Write-Verbose -message 'Downloading and running Configuration...' -verbose
# run Install-ContainerHost.ps1
$installContainerHostPath = Join-Path -Path $PSScriptRoot -ChildPath 'Install-ContainerHost.ps1'
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/TravisEz13/VstsDockerAgentBootstrap/master/install-containerhost.ps1" -OutFile $installContainerHostPath
&$installContainerHostPath -DataDrive:$DataDrive.IsPresent -Isolation $Isolation -SkipWua:$SkipWua.IsPresent

#'{ "hosts": ["tcp://127.0.0.1:2375"] }'|out-file -Encoding ascii -FilePath "$env:programdata/Docker/config/daemon.json"		
#[System.Environment]::SetEnvironmentVariable('DOCKER_HOST',"tcp://localhost:2375",'Machine')

# reboot if the current process doesn't have the variable that indicates docker was installed
#if($env:DOCKER -notin @('Staged','Installed'))
#{
#  Restart-Computer -force
#}
