# VstsDockerAgentBootstrap

To use in setting up a VSTS agent for docker.

In azure, you can use the custom script agent, or the dev test lab `Run PowerShell` artifact to run the following:

```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
https://raw.githubusercontent.com/TravisEz13/VstsDockerAgentBootstrap/master/bootstrap.ps1
```

**Note:** The script expects a later task to reboot, because when I use it I always have a later tasks which reboots the machin.
