# Ark Survival Ascended Server Manager 🦖
The primary goal in developing this script was to make an ark management tool for automation enthusiasts that embodied "set it and forget it". This tool provides functions for starting and maintaining an Ark Survival Ascended server that, when paired with Windows Task Scheduler, provides a very low maintenance and unobtrusive experience.

> [!Note]
> I am unfortunately not providing direct support for this project. This is first and foremost for my own server management. It's shared here because I recognize its usefulness and educational value, and I hope it will help people who were in the same boat as me when I started on this quest for automated ASA server management.

> [!WARNING]
> The use of this tool assumes a basic understanding of ASA server hosting. This guide doesn't cover port forwarding, ini configuration, firewalls, etc. Check out the Ark Wiki's [Dedicated server setup](https://ark.wiki.gg/wiki/Dedicated_server_setup) for information on that.

## Features
- [x] Server Setup
- [x] Server Updates
- [x] Compressed Backups
- [x] Starts, Stops, & Restarts
- [x] Crash Detection & Auto Restart
- [x] Script Activity Logging
- [x] Queueable .ini Settings
- [x] Clustered Servers
- [ ] Tells you its proud of you

## Usage
### Primary Operations
```-setup``` : Should only be used on initial script usage. Sets up project structure, downloads required tools, and installs the server application.
<br>```-shutdown``` : Kicks off a 1 hour delayed shutdown sequence that includes warnings in server chat using RCON.
<br>```-restart``` : Kicks off a 1 hour delayed shutdown sequence that includes warnings in server chat using RCON. Server starts back up immediately after.
<br>```-crashdetect``` : Checks if the ark server is running and restarts it if it is not. This should be scheduled to run periodically; every 30 seconds is effective.
### Sub Operations
```-backup``` : Compresses the server's "Saved" folder and copies it to the backup path specified in the ASAServer.properties file.
<br>```-update``` : Triggers steamcmd to update and validate the Ark Ascended Server application. Recommended to set this flag during server restarts.
### Special Settings
```-eventroulette``` : This parameter allows you to provide a comma separated list of event mod ids to activate at random on restart. To avoid loss, only use events that have been added to the core game. Technically this will work with general mods too, but its not recommended. This will not overrided events specified in the ASAServer.properties file. 
<br>```-roulettechance``` : Paired with -eventroulette, this paramater allows you to specify the percentage chance that an event roulette will occur. Must provide a value of 0-100. Default value is 100.
<br>```-rollforcerespawndinos``` : This flag introduces a chance that -ForceRespawnDinos will be set on server startup, thus respawning all wild dinos. The value provided specifies the percentage chance that a forced respawn will occur and must be a value of 0-100. This flag can only be triggered on operation ```-restart```.
### Conditions
```-now``` : This flag will force the shutdown sequence to skip the 1 hour delay. Can only be used on ```-shutdown``` or ```-restart``` operations.
<br>```-preservestate``` : This flag can be used during restarts to keep events active that were rolled from ```-eventroulette```; The ```-crashdetect``` operation has ```-preservestate``` set to true by default.
<br>```-skip``` : This flag is for troubleshooting/development. When set, major server operations are simulated. Some minor functions and logging still occur. Not recommended for general use.
<br>```-istest``` : This flag is for skipping the pause in the setup operation. Not recommended for general use.

## Examples
The following command will shutdown any currently running servers immediately, backup the server, update the server, then start the server back up:
```
$ ./ASAServerManager.ps1 -restart -backup -update -now
```
The following commend will shutdown any currently running servers with a 1 hour delay, backup the server, then update the server:
```
$ ./ASAServerManager.ps1 -shutdown -backup -update
```
The following command will shutdown any currently running servers immediately, then start the server back up, activating one of the provided event mod Ids:
```
$ ./ASAServerManager.ps1 -restart -now -eventroulette '927083,927090,927084'
```
The following command will shutdown any currently running servers immediately, then start the server back up with a 50% chance of activating one of the provided event mod Ids:
```
$ ./ASAServerManager.ps1 -restart -now -eventroulette 927083,927090,927084 -eventweight 50
```
The following command will shutdown any currently running servers immediately, then start the server back up with a 75% chance of wiping all wild dinos:
```
$ ./ASAServerManager.ps1 -restart -now -rollforcerespawndinos 75
```
The following command will make a note of the running event, shutdown any currently running servers immediately, then start the server back up, activating the noted event:
```
$ ./ASAServerManager.ps1 -restart -now -preservestate
```

## Setup
1. Create a folder where you would like install the server.
2. Copy the ASAServerManager.ps1 script into that folder.
3. Right click ASAServerManager.ps1 and select ```Run with PowerShell```
4. Wait for the setup process to finish and close out; following any directions it gives.
5. Edit the ```ASAServer.properties``` file with your preferred configurations. It contains default configs and examples.
6. Edit the ```Game.ini``` and ```GameUserSetting.ini``` with preferred server configurations. This is where you will put any and all .ini configurations for your server. They will automatically be copied into the server configurations on ```-restart```.

### Scheduling
I recommended scheduling these commands with Windows Task Scheduler so that they will run in the backround. Watch a quick video on Task Scheduler if you are unfamiliar. Here is a quick setup for a nightly restart that includes backups and updates.
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
   - For "Add arguments" add ```-File "ASAServerManager.ps1" -restart -backup -update```
   - For "Start in" put the path to the ASAServerManager.ps1 script.
6. Click Ok and you should be all set.

> [!TIP]
> You can make a crash detection entry similarly. Just set the trigger to repeat every 30 seconds or so and set the action arguements to ```-File "ASAServerManager.ps1" -crashdetect```.

## Issues
As mentioned above, this is primarily a personal project. If there are obviously valid problems I will address them [here](https://github.com/HeyKrystal/asa-server-manager/issues/new). However, requests that border enhancements or conveniences will be ignored.

## Contribution
I'm not super familiar with GitHub's collaboration features. I'll try to be accomodating where it makes sense though. If you're wanting to make edits for your own personal use feel free to fork the project and do whatever you'd like to it. 😊
