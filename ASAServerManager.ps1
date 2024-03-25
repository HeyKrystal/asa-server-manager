<#
    .SYNOPSIS
    Manage an Ark Survival Ascended dedicated server.

    .DESCRIPTION
    The primary goal in developing this script was to make an ark management tool that embodied "set it and forget it. This tool provides several functions for starting and maintaining an Ark Survival Ascended server that, when paired with task scheduler, provides a very low maintenance experience. You can schedule nightly restarts that will automatically backup saves to a specified location. The server will automatically check for updates and install them before running. Backups and updates can also be requested on demand, as long as the server is not already running to prevent corruption. Backups are also compressed to save space. (Install WinRAR for better compression. The script will use it automatically if you have it installed.)  Protections are also in place so that only one instance of this script can be executed at any given time, again to prevent corruption. This script also has a setup function that will download the tools you need and setup the project structure required by the script. Actions for this script are kept in logs to help determine unexpected issues. This script also allows you to queue up changes to your config files for next restart.

    .PARAMETER setup
    Should only be used on initial script usage. Sets up project structure, downloads required tools, and installs the server application.

    .PARAMETER shutdown
    Kicks off a 1 hour delayed shutdown sequence that includes warnings in server chat using RCON.
    
    .PARAMETER restart
    Kicks off a 1 hour delayed shutdown sequence that includes warnings in server chat using RCON. Server starts back up immediately after.

    .PARAMETER crashdetect
    Checks if the ark server is running and restarts it if it is not. This should be scheduled to run periodically; every 30 seconds is effective.

    .PARAMETER backup
    Compresses the server's "Saved" folder and copies it to the backup path specified in the ASAServer.properties file.

    .PARAMETER update
    Triggers steamcmd to update and validate the Ark Ascended Server application. Recommended to set this flag during server restarts.

    .PARAMETER eventroulette
    This parameter allows you to provide a comma separated list of event mod ids to activate at random on restart. To avoid loss, only use events that have been added to the core game. Technically this will work with general mods too, but its not recommended. This will not overrided events specified in the ASAServer.properties file. 

    .PARAMETER roulettechance
    Paired with -eventroulette, this paramater allows you to specify the percentage chance that an event roulette will occur. Must provide a value of 0-100. Default value is 100.

    .PARAMETER rollforcerespawndinos
    This flag introduces a chance that -ForceRespawnDinos will be set on server startup, thus respawning all wild dinos. The value provided specifies the percentage chance that a forced respawn will occur and must be a value of 0-100. This flag can only be triggered on operation -restart.

    .PARAMETER now
    This flag will force the shutdown sequence to skip the 1 hour delay. Can only be used on -shutdown or -restart operations.

    .PARAMETER preservestate
    This flag can be used during restarts to keep events active that were rolled from -eventroulette; The -crashdetect operation has -preservestate set to true by default.

    .PARAMETER skip
    This flag is for troubleshooting/development. When set, major server operations are simulated. Some minor functions and logging still occur. Not for general use.

    .PARAMETER istest
    This flag is for skipping the pause in the setup operation. Not for general use.
#>
[CmdletBinding(DefaultParameterSetName='Default')]
param (

    # Primary Operations
    [Parameter()]
    [switch]$setup = $false,

    [Parameter()]
    [switch]$shutdown = $false,

    [Parameter()]
    [switch]$restart = $false,

    [Parameter()]
    [switch]$crashdetect = $false,

    # Sub Operations
    [Parameter()]
    [switch]$backup = $false,

    [Parameter()]
    [switch]$update = $false,

    # Special Settings
    [Parameter()]
    [ValidatePattern("^\d{6,8}(,\d{6,8})*$")]
    [String]$eventroulette,

    [Parameter()]
    [ValidateRange(0,100)]
    [int]$roulettechance = -1,

    [Parameter()]
    [ValidateRange(0,100)]
    [int]$rollforcerespawndinos,

    # Conditions
    [Parameter()]
    [switch]$now = $false,

    [Parameter()]
    [switch]$preservestate = $false,

    [Parameter()]
    [switch]$skip = $false,

    [Parameter()]
    [switch]$istest = $false
)

# This is a port pool for clustering. (These 8 sets are the most I've ever been able to port forward in Evolved.)
# Port list for router config: 7777,7778,7779,7780,7781,7782,7783,7784,7785,7786,7787,7788,7789,7790,7791,7792,27015,27016,27017,27018,27019,27020,27051,27052
$portPool = @(
    [PortSet]@{ instancePort="7777"; rawPort="7778"; queryPort="27015"; rconPort="32330" }
    [PortSet]@{ instancePort="7779"; rawPort="7780"; queryPort="27016"; rconPort="32332" }
    [PortSet]@{ instancePort="7781"; rawPort="7782"; queryPort="27017"; rconPort="32334" }
    [PortSet]@{ instancePort="7783"; rawPort="7784"; queryPort="27018"; rconPort="32336" }
    [PortSet]@{ instancePort="7785"; rawPort="7786"; queryPort="27019"; rconPort="32338" }
    [PortSet]@{ instancePort="7787"; rawPort="7788"; queryPort="27020"; rconPort="32340" }
    [PortSet]@{ instancePort="7789"; rawPort="7790"; queryPort="27051"; rconPort="32342" }
    [PortSet]@{ instancePort="7791"; rawPort="7792"; queryPort="27052"; rconPort="32344" }
)

# Used for dynamically labeling servers.
$maps = @{
    TheIsland_WP=[ASAMap]@{ apiName="TheIsland_WP"; mapLabel="The Island" }
    Svartalfheim_WP=[ASAMap]@{ apiName="Svartalfheim_WP"; mapLabel="Svartalfheim(Test)" }
    Nyrandil=[ASAMap]@{ apiName="Nyrandil"; mapLabel="Nyrandil(Test)" }
}

# These are the mod ids for core events.
$events = @(
    [ASAEvent]@{ modId="927083"; eventLabel="Turkey Trial" }
	[ASAEvent]@{ modId="927090"; eventLabel="Winter Wonderland" }
	[ASAEvent]@{ modId="927084"; eventLabel="Love Ascended" }
)

function main {

    # Script launched
    Write-Host -ForegroundColor Green "======= Script Launched ======="

    # Start logging stdout and stderr to file unless crash detect.
    if ($crashdetect) {
        Start-Transcript -Path "./Logs/ASACrashDetection.log" -Append
    } else {
        Start-Transcript -Path "./Logs/ASAServerManager.log" -Append
    }

    # Exit script if lockfile exists, otherwise create one.
    if (Test-Path -Path "./Status/ASA.lock") {
        Write-Host "Execution blocked by ASA.lock file. An instance of ASAServerManager.ps1 is already running."
        Write-Host "If you believe you have received this message in error, you can manually delete the ASA.lock file in the Status folder and try again."
        exit
    } else {
        $null = New-Item -Name ./Status/ASA.lock -Force
        Write-Host "Starting ASAServerManager script and creating lock file."
    }

    # Validate parameters combinations.
    $setupActual = ($setup -OR !($shutdown -OR $backup -OR $backup -OR $update -OR $restart -OR $crashdetect))
    if (validateParameters) {
        # Exit script if properties file doesnt exist.
        if (!(Test-Path -Path "./ASAServer.properties") -AND !$setupActual) {
            Write-Host "Unable to find ASAServer.properties; run script with `"-setup`" flag."
            timeout /t 10
        } elseif (Test-Path -Path "./ASAServer.properties") {
            # Load properties file.
            $propertiesContent = Get-Content ".\ASAServer.properties" -raw
            $propertiesContentEscaped = $propertiesContent -replace '\\', '\\'
            $properties = ConvertFrom-StringData -StringData $propertiesContentEscaped

            # TODO Validate properties.
            Write-Host -ForegroundColor Green "======= Properties Loaded ======="
            Write-Host "SessionHeader: $([string]$properties.SessionHeader)"
            Write-Host "ActiveMapIDs: $([string]$properties.ActiveMapIDs)"
            Write-Host "MapSpecificMods: $([string]$properties.MapSpecificMods)"
            Write-Host "ActiveEventID: $([string]$properties.ActiveEventID)"
            Write-Host "AdditionalCMDFlags: $([string]$properties.AdditionalCMDFlags)"
            Write-Host "BackupPath: $([string]$properties.BackupPath)"
            Write-Host "MaxPlayers: $([int]$properties.MaxPlayers)"
        }

        # Perform requested operations.
        if ($setupActual) { setup }
        if ($shutdown -OR $restart) { shutdownServer }
        if ($backup) { backupServer }
        if ($update) { updateServer }
        if ($restart) { restartServer }
        if ($crashdetect) { crashDetect }
    }

    # Wrap up and delete lockfile.
    Write-Host -ForegroundColor Green "====== Closing Script ======"
    Write-Host "Exiting ASAServerManager script and removing lock file."
    Remove-Item -Path "./Status/ASA.lock"
    
    # Stop logging to file
    Stop-Transcript
}

function setup {

    # Server operation.
    Write-Host -ForegroundColor Green "======= Setup Requested ======="
    
    # Confirm server is not running.
    if (isServerRunning) {
        Write-Host -ForegroundColor Red "ERROR: Cannot run -setup while server while running."
        return
    }

    # Setup project structure.
    Write-Host "Setting up project structure."
    New-Item -Path "./ASAServers" -ItemType Directory
    New-Item -Path "./Backups" -ItemType Directory
    New-Item -Path "./RCON" -ItemType Directory
    New-Item -Path "./SteamCMD" -ItemType Directory

    # Generate random number for unique cluster id.
    $clusterNumber = Get-Random -Minimum 100000000 -Maximum 999999999

    # Create properties file with initial values.
    $initialPropertiesValues = "" +
    "# Server will show up in the list with this value, followed by a hyphen and the map label. (e.g. `"My Cool Cluster - The Island`")`n" +
    "SessionHeader=My Cool Cluster`n" +
    "# Determines which map the server will host. Comma delimit for clusters. Duplicates won't work.`n" +
    "ActiveMapIDs=TheIsland_WP`n" +
    "# Specify map-specific mods. Useful for preventing a premium mod from paywalling an entire cluster. Or keeping map instances unique. Separate map entries with single spaces. (e.g. `"Svartalfheim_WP:962796 TheIsland_WP:123456,098765`")`n" +
    "MapSpecificMods=`n" +
    "# Put event mod id to activate an event, otherwise leave blank. This property will always override -eventroulette.`n" +
    "ActiveEventID=`n" +
    "# Include additional command line flags you would like here space-separated. (e.g. `"-PassiveMods=927090 -NoTransferFromFiltering -NoBattlEye`")`n" +
    "AdditionalCMDFlags=-NoTransferFromFiltering -NoBattlEye`n" +
    "# If using clusters populate this with a unique Id, otherwise leave blank. (e.g. `"MyCoolCluster123456789`")`n" +
    "ClusterId=MyCoolCluster$($clusterNumber)`n" +
    "# Change this to overwride the default backup folder. (Use UNC paths for network folders.)`n" +
    "BackupPath=./Backups`n" +
    "# Sets the maximum concurrent players in your server.`n" +
    "MaxPlayers=20`n" +
    "# Copy the admin password you've set in your GameUserSettings.ini here. (This tool will not function properly without this.)`")`n" +
    "AdminPassword=`n"
    New-Item -Path "./ASAServer.properties" -ItemType File -Value $initialPropertiesValues
    
    # Download the utilities used by the script.
    Write-Host "Downloading & unpacking utilities used by the script."
    Invoke-WebRequest -Uri "https://github.com/gorcon/rcon-cli/releases/download/v0.10.3/rcon-0.10.3-win64.zip" -Outfile RCON.zip
    Expand-Archive -Path "./RCON.zip" -DestinationPath "./RCON/"
    Invoke-WebRequest -Uri "https://steamcdn-a.akamaihd.net/client/installer/steamcmd.zip" -Outfile SteamCMD.zip
    Expand-Archive -Path "./SteamCMD.zip" -DestinationPath "./SteamCMD/"
    
    # Relocate rcon-cli for easier access.
    Move-Item -Path "./RCON/rcon-0.10.3-win64/*" -Destination "./RCON"
    
    # Cleanup.
    Write-Host "Cleaning up."
    Remove-Item -Path "./RCON.zip"
    Remove-Item -Path "./SteamCMD.zip"
    Remove-Item -Path "./RCON/rcon-0.10.3-win64" -Recurse
    
    #Update steamcmd.
    Write-Host "Updating steamcmd."
    SteamCMD\steamcmd.exe +quit
    
    # Update the server before running.
    updateServer

    # Create placeholders for .ini files.
    New-Item -Name "./Game.ini" | Out-Null
    New-Item -Name "./GameUserSettings.ini" | Out-Null

    # Next steps.
    New-Item -Path "./ASAServers/ShooterGame/Saved/Config/WindowsServer" -ItemType Directory
    Write-Host "`nSetup complete, check out the ASAServer.properties for important settings before starting the server."
    Write-Host "Also if you have GameUserSettings.ini and Game.ini you are planning on using, right now (before pressing enter) would be a great time to copy them into the same folder as this script. Replace the auto generated ones."
    if (!$istest) { Pause }

    <#
    # Create queued versions of ini files for easier configuration updates.
    if ((Test-Path -Path "./ASAServers/ShooterGame/Saved/Config/WindowsServer/Game.ini") -AND !(Test-Path -Path "./Game.ini")) {
        Write-Host "Creating queues version of Game.ini"
        Copy-Item -Path "./ASAServers/ShooterGame/Saved/Config/WindowsServer/Game.ini" -Destination "./Game.ini"
    } elseif (!(Test-Path -Path "./ASAServers/ShooterGame/Saved/Config/WindowsServer/Game.ini") -AND !(Test-Path -Path "./Game.ini")) {
        Write-Host "Creating regular and queued versions of Game.ini"
        New-Item -Name "./ASAServers/ShooterGame/Saved/Config/WindowsServer/Game.ini" | Out-Null
        New-Item -Name "./Game.ini" | Out-Null
    }

    if ((Test-Path -Path "./ASAServers/ShooterGame/Saved/Config/WindowsServer/GameUserSettings.ini") -AND !(Test-Path -Path "./GameUserSettings.ini")) {
        Write-Host "Creating queues version of GameUserSettings.ini"
        Copy-Item -Path "./ASAServers/ShooterGame/Saved/Config/WindowsServer/GameUserSettings.ini" -Destination "./GameUserSettings.ini"
    } elseif (!(Test-Path -Path "./ASAServers/ShooterGame/Saved/Config/WindowsServer/GameUserSettings.ini") -AND !(Test-Path -Path "./GameUserSettings.ini")) {
        Write-Host "Creating regular and queued versions of GameUserSettings.ini"
        New-Item -Name "./ASAServers/ShooterGame/Saved/Config/WindowsServer/GameUserSettings.ini" | Out-Null
        New-Item -Name "./GameUserSettings.ini" | Out-Null
    }
    #>
}

function shutdownServer {

    # Server operation.
    Write-Host -ForegroundColor Green "======= Shutdown Requested ======="

    # Return if server is not running.
    if (-Not (isServerRunning)) { return }
    
    # Announce restart to all active maps over the course of an hour, skip if -now passed as argument.
    # (Hits all port sets to be safe.)
    [string[]]$listeningPorts = getListeningPorts
    if (-Not $now) {
        Write-Host "rcon: ServerChat [Server]: Restarting in 1 hour to perform nightly maintenance & backup."
        for ($i = 0; $i -lt $listeningPorts.Length; $i++) { rcon "$($listeningPorts[$i])" "ServerChat [Server]: Restarting in 1 hour to perform maintenance & backup." }
        timeout /t 1800 /nobreak
        Write-Host "rcon: ServerChat [Server]: Restarting in 30 minutes."
        for ($i = 0; $i -lt $listeningPorts.Length; $i++) { rcon "$($listeningPorts[$i])" "ServerChat [Server]: Restarting in 30 minutes." }
        timeout /t 900 /nobreak
        Write-Host "rcon: ServerChat [Server]: Restarting in 15 minutes."
        for ($i = 0; $i -lt $listeningPorts.Length; $i++) { rcon "$($listeningPorts[$i])" "ServerChat [Server]: Restarting in 15 minutes." }
        timeout /t 600 /nobreak
        Write-Host "rcon: ServerChat [Server]: Restarting in 5 minutes."
        for ($i = 0; $i -lt $listeningPorts.Length; $i++) { rcon "$($listeningPorts[$i])" "ServerChat [Server]: Restarting in 5 minutes." }
        timeout /t 240 /nobreak
        Write-Host "rcon: ServerChat [Server]: Restarting in 1 minute."
        for ($i = 0; $i -lt $listeningPorts.Length; $i++) { rcon "$($listeningPorts[$i])" "ServerChat [Server]: Restarting in 1 minute." }
        timeout /t 30 /nobreak
        Write-Host "rcon: ServerChat [Server]: Restarting in 30 seconds."
        for ($i = 0; $i -lt $listeningPorts.Length; $i++) { rcon "$($listeningPorts[$i])" "ServerChat [Server]: Restarting in 30 seconds." }
        timeout /t 25 /nobreak
    }

    # Announce shutdown to all maps, short notice.
    Write-Host "rcon: ServerChat [Server]: Restarting in 5 seconds."
    for ($i = 0; $i -lt $listeningPorts.Length; $i++) { rcon "$($listeningPorts[$i])" "ServerChat [Server]: Restarting in 5 seconds." }
    timeout /t 5 /nobreak
    Write-Host "rcon: ServerChat [Server]: World save in progress."
    for ($i = 0; $i -lt $listeningPorts.Length; $i++) { rcon "$($listeningPorts[$i])" "ServerChat [Server]: World save in progress." }
    for ($i = 0; $i -lt $listeningPorts.Length; $i++) {
        Write-Host "Save request to $($listeningPorts[$i])" 
        rcon "$($listeningPorts[$i])" "SaveWorld"
        timeout /t 3 /nobreak
    }
    Write-Host "rcon: ServerChat [Server]: Server will be back online momentarily."
    for ($i = 0; $i -lt $listeningPorts.Length; $i++) { rcon "$($listeningPorts[$i])" "ServerChat [Server]: Server will be back online momentarily." }
    timeout /t 5 /nobreak
    Write-Host "rcon: ServerChat [Server]: That doesn't mean wait for it, go touch some grass.. :|"
    for ($i = 0; $i -lt $listeningPorts.Length; $i++) { rcon "$($listeningPorts[$i])" "ServerChat [Server]: That doesn't mean wait for it, go touch some grass.. :|" }
    timeout /t 1 /nobreak

    # Shutdown all maps.
    Write-Host "rcon: DoExit"
    for ($i = 0; $i -lt $listeningPorts.Length; $i++) { if (!$skip) { rcon "$($listeningPorts[$i])" "DoExit" } }

    # Timeout up to 2 minutes for process to close before continuing to other operations.
    $successfullyShutdown = $false
    if ($restart -OR $backup -OR $update) {
        for ($i = 0; $i -lt 12; $i++) {
            Write-Host "Waiting for process to exit before continuing to other operations."
            timeout /t 10 /nobreak
                
            if (-Not (isServerRunning)) {
                $successfullyShutdown = $true
                break
            }
        }

        if (!$successfullyShutdown) {
            Write-Host -ForegroundColor Red "ERROR: Server failed to shutdown. ArkAscendedServer processes may need to be killed manually before proceeding."
            Write-Host -ForegroundColor Yellow "HINT: Also double check ASAServer.properties file. If invalid ActiveMapIDs are listed, they will often cause zombie servers like this."
        }
    }
}

function restartServer {

    # Server operation.
    Write-Host -ForegroundColor Green "======= Startup Requested ======="

    # Return if server is already running.
    if (isServerRunning) { return }

    # Handle -preservestate related properties.
    if (($preservestate -OR $crashdetect) -AND (Test-Path -Path ".\Status\ASACrashRecovery.properties")) {
        # Load crash recovery properties file.
        $crashRecoveryPropertiesContent = Get-Content ".\Status\ASACrashRecovery.properties" -raw
        $crashRecoveryPropertiesContentEscaped = $crashRecoveryPropertiesContent -replace '\\', '\\'
        $crashRecoveryProperties = ConvertFrom-StringData -StringData $crashRecoveryPropertiesContentEscaped
    
        # Set active event id from recovery file.
        Write-Host "Restoring state from ASACrashRecovery.properties file."
        $properties.ActiveEventID = $crashRecoveryProperties.ActiveEventID
    } else {
        # Replace ini files with queued files.
        Copy-Item -Path "./Game.ini" -Destination "./ASAServers/ShooterGame/Saved/Config/WindowsServer/Game.ini" -Force
        Copy-Item -Path "./GameUserSettings.ini" -Destination "./ASAServers/ShooterGame/Saved/Config/WindowsServer/GameUserSettings.ini.temp" -Force
    }

    # Store ActiveMods line from GameUserSettings.ini, store in ActiveMods.ini, then remove line entirely.
    Write-Host "Relocating ActiveMods to ActiveMods.ini file."
    $activeModsLine = Get-Content -Path "./ASAServers/ShooterGame/Saved/Config/WindowsServer/GameUserSettings.ini.temp" | Where-Object { $_ -match "ActiveMods=" }
    Get-Content "./ASAServers/ShooterGame/Saved/Config/WindowsServer/GameUserSettings.ini.temp" | Where-Object {$_ -notmatch "ActiveMods="} | Set-Content "./ASAServers/ShooterGame/Saved/Config/WindowsServer/GameUserSettings.ini" -Force
    $null = New-Item -Path "./ASAServers/ShooterGame/Saved/Config/WindowsServer/ActiveMods.ini" -ItemType File -Value "$($activeModsLine)" -Force

    # Determine if dinos will be force respawned.
    $respawnDinoArgument = ""
    if (!$null -eq $rollforcerespawndinos)
    {
        $diceRoll = Get-Random -Minimum 1 -Maximum 101
        Write-Host "Rolled a $($diceRoll) against -ForceRespawnDinos $($rollforcerespawndinos)."
        if ($diceRoll -le $rollforcerespawndinos) {
            $respawnDinoArgument = "-ForceRespawnDinos"
            Write-Host "Dinos will be force respawed."
        } else {
            Write-Host "Dinos will not be force respawed."
        }
    }

    # Check if event specified or roulette requested.
    if (!$null -eq $eventroulette) {
        $eventRouletteArray = $eventroulette.Split(",")
    }
    # There must be no active event to utilize event roulette.
    if ($properties.ActiveEventID -eq "" -AND $eventRouletteArray.Count -gt 0) {
        if ($roulettechance -lt 0) {
            Write-Host "Setting default roulettechance of 100."
            $roulettechance = 100
        }
        $diceRoll = Get-Random -Minimum 1 -Maximum 100
        Write-Host "Rolled a $($diceRoll) against -roulettechance $($roulettechance)."
        if ($diceRoll -le $roulettechance) {
            $diceRoll = Get-Random -Minimum 0 -Maximum ($eventRouletteArray.Count)
            $activeEventId = $eventRouletteArray[$diceRoll]
        }
    } elseif (!$properties.ActiveEventID -eq "") {
        $activeEventId = $properties.ActiveEventID
    }
    $eventIdentified = $false;
    for ($i = 0; $i -lt $events.Length; $i++) {
        if ($activeEventId -eq ($events[$i].modId)) {
            Write-Host "Including $($events[$i].eventLabel) event."
            $eventIdentified = $true;
        }
    }
    if (!$activeEventId -eq "" -AND !$eventIdentified) {
        Write-Host "Including $($activeEventId) mod."
    }
    
    # Build and add mods parameter if applicable.
    $activeModIds = getActiveModIds

    # Collect map specific mods if applicable.
    $mapSpecificMods = $properties.MapSpecificMods.split(" ")

    # Set crash recovery properties.
    Write-Host "Storing state in ASACrashRecovery.properties file."
    $null = New-Item -Path "./Status/ASACrashRecovery.properties" -ItemType File -Value "# Crash Recovery Properties`nActiveEventID=$($activeEventId)" -Force

    # Start up all maps with a short stagger period inbetween.
    $activeMapIds = getActiveMapIds
    for ($i = 0; $i -lt $activeMapIds.Length; $i++) {
        # Log server launch start.
        Write-Host -ForegroundColor Green "====== Launching server $($i+1) of $($activeMapIds.Length) ======"
        
        # Check for map specific mod ids.
        for ($j = 0; $j -lt $mapSpecificMods.Length; $j++) {
            if ($mapSpecificMods[$j].StartsWith("$($activeMapIds[$i])")) {
                $mapSpecificModsIds = $mapSpecificMods[$j].split(":")[1]
                Write-Host "Including map specific mods $($mapSpecificMods[$j])"
                break
            } else {
                $mapSpecificModsIds = ""
            }
        }

        # Build mod parameter.
        $allMods = New-Object Collections.Generic.List[String]
        if (!$activeEventId -eq "") { $allMods.add($activeEventId) }
        if (!$activeModIds -eq "") { $allMods.add($activeModIds) }
        if (!$mapSpecificModsIds -eq "") { $allMods.add($mapSpecificModsIds) }
        if ($allMods.Length -gt 0) { $modsParameter = "-mods=$($allMods -join ",")" } else { $modsParameter = "" }

        # Launch server command.
        $commandLine = "cmd /c start '' /b ASAServers\ShooterGame\Binaries\Win64\ArkAscendedServer.exe $($maps[$activeMapIds[$i]].apiName)?SessionName='\`"$($properties.SessionHeader) - $($maps[$activeMapIds[$i]].mapLabel)\`"'?AltSaveDirectoryName=KC$($maps[$activeMapIds[$i]].apiName)Save?Port=$($portPool[$i].instancePort)?RCONPort=$($portPool[$i].rconPort) $($respawnDinoArgument) -clusterID=$($properties.ClusterId) -WinLiveMaxPlayers=$($properties.MaxPlayers) `"$modsParameter`" $($properties.AdditionalCMDFlags)"
        Write-Host $commandLine
        if (!$skip) {
            Invoke-Expression $commandLine
            timeout /t 60 /nobreak
        }
    }
}

function crashDetect {

    # Confirm server is not running.
    if (isServerRunning) {
        Write-Host "No crash detected."
        return
    }

    # Crash detected, run restart now.
    restartServer
}

function backupServer {

    # Server operation.
    Write-Host -ForegroundColor Green "======= Backup Requested ======="

    # Confirm server has a planned shutdown.
    if ((isServerRunning) -AND !($restart -OR $shutdown)) {
        Write-Host -ForegroundColor Red "ERROR: Cannot perform backup while server is running."
        return
    }

    # Timeout up to 2 minutes for process to close before backup.
    if (-Not (isServerRunning)) {
        # Archive backup of the Saved folder with YYYY-MM-DD-HHMM format.
        $archiveName = Get-Date -Format "yyyy-MM-dd_HHmm"

        # If WinRAR installed, use that, otherwise use default compression.
        if (Test-Path -Path "C:\Program Files\WinRAR\Rar.exe") {
            Write-Host "Archiving ASAServers\Shootergame\Saved to $([string]$properties.BackupPath)\$($archiveName).rar using WinRar."
            if (!$skip) { & "C:\Program Files\WinRAR\Rar.exe" a "$([string]$properties.BackupPath)\$($archiveName).rar" "ASAServers\ShooterGame\Saved" }
        } else {
            Write-Host "Archiving ASAServers\Shootergame\Saved to $([string]$properties.BackupPath)\$($archiveName).rar using default compression."
            if (!$skip) { Compress-Archive -Path "ASAServers\ShooterGame\Saved" -DestinationPath "$([string]$properties.BackupPath)\$($archiveName).zip" -CompressionLevel Optimal }
        }
    }
}

function updateServer {

    # Server operation.
    Write-Host -ForegroundColor Green "======= Update Requested ======="

    # Confirm server is not running.
    if (isServerRunning) {
        Write-Host -ForegroundColor Red "Cannot patch server while updating."
        return
    }

    # Update server using steamcmd.
    Write-Host "Requesting steamcmd to update and validate the Ark Ascended Server application."
    if (!$skip) { SteamCMD\steamcmd.exe +force_install_dir ../ASAServers/ +login anonymous +app_update 2430930 validate +quit }
}

# Check if ArkAscendedServer.exe is running.
function isServerRunning {

    $processName = "ArkAscendedServer"
    Write-Host "Checking for instance of $processName."
    $isRunning = (Get-Process | Where-Object { $_.Name -eq $processName }).Count -gt 0
    if ($isRunning) {
        Write-Host "Instance of $processName found."
    } else {
        Write-Host "No Instance of $processName found."
    }

    return $isRunning
}

# Get active mods from GameUserSettings.ini
function getActiveModIds {

    # Read ini file to get ActiveMods
    $activeModsLine = Get-Content -Path "./ASAServers/ShooterGame/Saved/Config/WindowsServer/ActiveMods.ini" | Where-Object { $_ -match "ActiveMods=" }
    $activeModsArray = $activeModsLine -split "="
    $activeModIds = "$($activeModsArray[1])"

    return $activeModIds
}

# Get active maps from server properties.
function getActiveMapIds {

    # Get active map ids from properties.
    $activeMapIds = @($properties.ActiveMapIDs.split(",") | Select-Object -Unique)

    return Write-Output -NoEnumerate $activeMapIds
}

# Get which ports from the pool are being used.
function getListeningPorts {

    Write-Host "Checking for listening ports."
    [string[]]$listeningPorts = @()
    $listeningPortIndex = 0
    for ($i = 0; $i -lt $portPool.Length; $i++) {
        if (Test-NetConnection -ComputerName "127.0.0.1" -Port "$($portPool[$i].rconPort)" -InformationLevel Quiet) {
            Write-Host "Port $($portPool[$i].rconPort) is listening."
            [string[]]$listeningPorts += ,$($portPool[$i].rconPort)
            $listeningPortIndex++
        }
    }
    
    return Write-Output -NoEnumerate $listeningPorts
}

# Helper rcon function.
function rcon {
    param (
        [Parameter(Mandatory)]
        [string]$targetPort,
        [Parameter(Mandatory)]
        [string]$command
    )

    # User rcon to send command to server.
    $commandLine = "cmd /c start '' /b ./RCON/rcon -a `"localhost:$($targetPort)`" -p `"$($properties.AdminPassword)`" -l `"./RCON/rcon.log`" -s `"$($command)`""
    Write-Host "cmd /c start '' /b ./RCON/rcon -a `"localhost:$($targetPort)`" -p ************* -l `"./RCON/rcon.log`" -s `"$($command)`""
    Invoke-Expression $commandLine
}

# Call for parameter validation.
function validateParameters {

    # Return value
    $validParameters = $true

    # Primary operation flags
    if ($setup -AND ($restart -OR $shutdown -OR $crashdetect -OR $backup -OR $update -OR $eventroulette -OR ($roulettechance -ge 0) -OR $rollforcerespawndinos -OR $now -OR $preservestate)) {
        Write-Host -ForegroundColor Red "Invalid Parameters: The -setup flag can only be used by itself."
        $validParameters = $false
    }
    if (($restart -AND ($shutdown -OR $crashdetect)) -OR ($shutdown -AND ($restart -OR $crashdetect)) -OR ($crashdetect -AND ($restart -OR $shutdown))) {
        Write-Host -ForegroundColor Red "Invalid Parameters: Only one of the following primary server operations can be used: -restart, -shutdown, or -crashdetect."
        $validParameters = $false
    }
    if ($shutdown -AND ($eventroulette -OR $rollforcerespawndinos -OR $preservestate)) {
        Write-Host -ForegroundColor Red "Invalid Parameters: The -shutdown operation cannot be used with -eventroulette, -rollforcerespawndinos, or -preservestate."
        $validParameters = $false
    }

    # Special operation flags
    if ($eventroulette.Length -gt 0 -AND !$restart) {
        Write-Host -ForegroundColor Red "Invalid Parameters: The -eventroulette parameter can only be used in conjunction with the -restart operation."
        $validParameters = $false
    }
    if ($eventroulette.Length -gt 0 -AND ($preservestate -OR $crashdetect)) {
        Write-Host -ForegroundColor Red "Invalid Parameters: The -eventroulette parameter cannot be used in conjunction with -preservestate flag."
        $validParameters = $false
    }
    if ($roulettechance -ge 0 -AND $eventroulette.Length -le 0) {
        Write-Host -ForegroundColor Red "Invalid Parameters: The roulettechance parameter must be used in conjunction with -eventroulette."
        $validParameters = $false
    }
    if ($rollforcerespawndinos -gt 0 -AND !($restart -OR $shutdown -OR $crashdetect)) {
        Write-Host -ForegroundColor Red "Invalid Parameters: The -rollforcerespawndinos parameter must be used in conjunction with one of the following primary server operations: -restart, -shutdown, or -crashdetect."
        $validParameters = $false
    }

    # Condition flags
    if ($now -AND !($restart -OR $shutdown)) {
        Write-Host -ForegroundColor Red "Invalid Parameters: The -now flag must be used in conjunction with one of the following primary server operations: -restart or -shutdown."
        $validParameters = $false
    }
    if ($preservestate -AND !($restart -OR $crashdetect)) {
        Write-Host -ForegroundColor Red "Invalid Parameters: The -now flag must be used in conjunction with one of the following primary server operations: -restart or -crashdetect."
        $validParameters = $false
    }
    if ($istest -AND !$setup) {
        Write-Host -ForegroundColor Red "Invalid Parameters: The istest flag can only be used in conjuction with -setup."
        $validParameters = $false
    }

    return $validParameters
}

# Class definitions.
class PortSet {
    [String]$instancePort
    [String]$rawPort
    [String]$queryPort
    [String]$rconPort
}
Class ASAEvent {
    [String]$modId
    [String]$eventLabel
}
Class ASAMap {
    [String]$apiName
    [string]$mapLabel
}

# Execute main logic.
main