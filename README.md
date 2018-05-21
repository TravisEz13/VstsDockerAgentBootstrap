# VstsDockerAgentBootstrap

To use in setting up a VSTS agent for docker.

In azure, you can use the custom script agent, or the dev test lab `Run PowerShell` artifact to run the following:

```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest https://raw.githubusercontent.com/TravisEz13/VstsDockerAgentBootstrap/master/bootstrap.ps1 -OutFile bootstrap.ps1
.\bootstrap.ps1
```

For vms prior to V3, the use the following command to use process isolation

```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest https://raw.githubusercontent.com/TravisEz13/VstsDockerAgentBootstrap/master/bootstrap.ps1 -OutFile bootstrap.ps1
.\bootstrap.ps1 -Isolation process
```

**Note:** The script expects a later task to reboot, because when I use it I always have a later tasks which reboots the machin.
