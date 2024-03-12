# Ark Survival Ascended Server Manager 🦖
The primary goal in developing this script was to make an ark management tool that embodied "set it and forget it". This tool provides several functions for starting and maintaining an Ark Survival Ascended server that, when paired with Windows Task Scheduler, provides a very low maintenance and unobtrusive experience.

> [!Note]
> I am unfortunately not providing direct support for this project. This is first and foremost for my own server management. It's shared here because I recognize its usefulness and educational value, and I hope it will help people who were in the same boat as me when I started on this quest for ASA server management.

## Features
- [x] Server Setup
- [x] Server Updates
- [x] Compressed Backups
- [x] Starts, Stops, & Restarts
- [x] Crash Detection & Auto Restart
- [x] Server Logging
- [x] Queueable .ini Settings
- [ ] Tells you its proud of you

## Setup
1. Create a folder where you would like install the server.
3. Copy the ASAServerManager.ps1 script into the folder that folder.
4. Using PowerShell, navigate to the directory containing the script, execute the following, then wait for it to finish.
```
$ ./ASAServerManager.ps1 -serverop setup
```
6. Edit the ```ASAServer.properties``` file with your preferred configurations.
7. Edit the ```Game_Queued.ini``` and ```GameUserSetting_Queued.ini``` with preferred server configurations.
8. Continue on to [Usage](README.md#usage)

## Usage
### Parameters
**-serverop** : Specifies the server operation you would like to perform.
- ```restart``` - Kicks off a 1 hour delayed shutdown sequence that includes warnings in server chat. Server starts back up immediately after.
- ```shutdown``` - Kicks off a 1 hour delayed shutdown sequence that includes warnings in server chat.
- ```backup``` - Compresses the server's "Saved" folder and copies it to the backup patch specified in the ASAServer.properties file.
- ```update``` - Runs steamcmd and updates the server application.
- ```setup``` - Should only be used on initial script usage. Sets up project structure, downloads required tools, and downloads the server application.
- ```crashdetect``` - This should be scheduled to run periodically; every 30 seconds is effective. Checks if the ark server is running and restarts it if it is not.
```
$ ./ASAServerManager.ps1 -serverop restart
```

<br>**-now** : This flag will force the shutdown sequence to skip the 1 hour delay. Can only be used on ```-serverop shutdown``` or ```-serverop restart```.
```
$ ./ASAServerManager.ps1 -serverop restart -now
```

<br>**-rollforcerespawndinos** : This flag introduces a chance that ```-ForceRespawnDinos``` will be set on server startup, thus respawning all wild dinos. The weight for this chance can be specified in the ASAServerProperties file. This flag will only be triggered on ```-serverop restart```.
```
$ ./ASAServerManager.ps1 -serverop restart -rollforcerespawndinos
```

### Scheduling
I recommended scheduling these commands with Windows Task Scheduler so that they will run in the backround. Watch a quick video on Task Scheduler if you are unfamiliar. Here is a quick setup for a nightly restart.
1. Create Task...
2. Set recognizable name. e.g. ASAServerNightlyRestart.
3. Set security options below if you are not always logged into your machine.
   - [ ] Run only when user is logged on
   - [x] Run whether user is logged in or not
     - [ ] Do not store password. The task will only have access to local resources
   - [x] Run with highest privileges
4. On the Triggers tab, click "New..." to add a new trigger with the following settings.
   - Daily
   - For "Start" set when you want it to run.
   - Uncheck "Repeat task every:"
5. Set a new action to "Start a program".
   - For "Program/Script" add ```Powershell```
   - For "Add arguments" add ```-File "ASAServerManager.ps1" -serverop restart```
   - For "Start in" add the path to your server directory.
6. Click Ok and you should be all set.
   Optional: You can make a crash detection entry similarly. Just set the trigger to repeat every 30 seconds or so and set the action arguements to ```-File "ASAServerManager.ps1" -serverop crashdetect```.

## Issues
As mentioned above, this is primarily a personal project. If there are obviously valid problems I will address them [here](https://github.com/HeyKrystal/asa-server-manager/issues/new). However, requests that border enhancements or conveniences will be ignored.

## Contribution
If you have ideas please feel free to just copy the script and build on top of it.
