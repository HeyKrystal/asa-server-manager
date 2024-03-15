<#
    .SYNOPSIS
    Manage an Ark Survival Ascended dedicated server.

    .DESCRIPTION
    The primary goal in developing this script was to make an ark management tool that embodied "set it and forget it. This tool provides several functions for starting and maintaining an Ark Survival Ascended server that, when paired with task scheduler, provides a very low maintenance experience. You can schedule nightly restarts that will automatically backup saves to a specified location. The server will automatically check for updates and install them before running. Backups and updates can also be requested on demand, as long as the server is not already running to prevent corruption. Backups are also compressed to save space. (Install WinRAR for better compression. The script will use it automatically if you have it installed.)  Protections are also in place so that only one instance of this script can be executed at any given time, again to prevent corruption. This script also has a setup function that will download the tools you need and setup the project structure required by the script. Actions for this script are kept in logs to help determine unexpected issues. This script also allows you to queue up changes to your config files for next restart.

    .PARAMETER serverop
    Specifies the server operation you would like to perform.
        - restart: Kicks off a 1 hour delayed shutdown sequence that includes warnings in server chat. Server starts back up immediately after.
        - shutdown: Kicks off a 1 hour delayed shutdown sequence that includes warnings in server chat.
        - backup: Compresses the server's "Saved" folder and copies it to the backup patch specified in the ASAServer.properties file.
        - update: Runs steamcmd and updates the server application.
        - setup: Should only be used on initial script usage. Sets up project structure, downloads required tools, and downloads the server application.
        - crashdetect: This should be scheduled to run periodically; every 30 seconds is effective. It checks if the ark server is running and restarts it if it is not.

    .PARAMETER now
    This flag will force the shutdown sequence to skip the 1 hour delay. Can only be used on -serverop shutdown or -serverop restart.

    .PARAMETER eventroulette
    This flag will pick a random event from the $events list.

    .PARAMETER rollforcerespawndinos
    This flag introduces a chance that -ForceRespawnDinos will be set on server startup, thus respawning all wild dinos. The weight for this chance can be specified in the ASAServerProperties file. This flag will only be triggered on -serverop restart.
#>
param (
    # The server operation to perform.
    [Parameter(Mandatory)]
    [ValidateSet("restart", "shutdown", "backup", "update", "setup", "crashdetect")]
    [string]$serverop,

    # Rolls for -ForceRespawnDinos on restart.
    [Parameter()]
    [switch]$rollforcerespawndinos = $false,
    # Skips the 1 hour countdown on shutdown/restart.
    [Parameter()]
    [switch]$now = $false
)

# This is a port pool for clustering. (These 8 sets are the most I've ever been able to port forward in Evolved.)
$portPool = @(
    [PortSet]@{ instancePort="7777";rawPort="7778";queryPort="27015";rconPort="32330" }
    [PortSet]@{ instancePort="7779";rawPort="7780";queryPort="27016";rconPort="32332" }
    [PortSet]@{ instancePort="7781";rawPort="7782";queryPort="27017";rconPort="32334" }
    [PortSet]@{ instancePort="7783";rawPort="7784";queryPort="27018";rconPort="32336" }
    [PortSet]@{ instancePort="7785";rawPort="7786";queryPort="27019";rconPort="32338" }
    [PortSet]@{ instancePort="7787";rawPort="7788";queryPort="27020";rconPort="32340" }
    [PortSet]@{ instancePort="7789";rawPort="7790";queryPort="27051";rconPort="32342" }
    [PortSet]@{ instancePort="7791";rawPort="7792";queryPort="27052";rconPort="32344" }
)

# This exists for when clustering becomes available.
$maps = @{
    TheIsland_WP=[Map]@{apiName="TheIsland_WP";label="The Island"}
    Svartalfheim_WP=[Map]@{apiName="Svartalfheim_WP";label="Svartalfheim(Test)"}
    Nyrandil=[Map]@{apiName="Nyrandil";label="Nyrandil(Test)"}
}

# These are the mod ids for events.
$events = {
    "927083" # Turkey Trial
	"927090" # Winter Wonderland
	"927084" # Love Evolved
}
Write-Host "Known events: $($events)"

function main {
    # Start logging stdout and stderr to file unless crash detect.
    if ($serverop -eq 'crashdetect') { Start-Transcript -Path "./Logs/ASACrashDetection.log" -Append }
    else { Start-Transcript -Path "./Logs/ASAServerManager.log" -Append }

    # Exit script if lockfile exists, otherwise create one.
    if (Test-Path -Path "ASA.lock") {
        Write-Host "Execution blocked by ASA.lock file. An ASA script is already running."
        Write-Host "If you believe you have received this message in error, you can manually delete the ASA.lock file and try again."
        timeout /t 10
        Exit
    }
    else {
        New-Item -Name ASA.lock -Force | Out-Null
        Write-Host "Starting ASAServerManager script and creating lock file."
    }

    # Exit script if properties file doesnt exist.
    if (!(Test-Path -Path "ASAServer.properties") -AND !($serverop -eq 'setup')) {
        Write-Host "Unable to find ASAServer.properties; run script with `"setup`" argument."
        timeout /t 10
        $serverop = ""
    } elseif (Test-Path -Path "ASAServer.properties") {
        # Load properties file.
        $propertiesContent = Get-Content ".\ASAServer.properties" -raw
        $propertiesContentEscaped = $propertiesContent -replace '\\', '\\'
        $properties = ConvertFrom-StringData -StringData $propertiesContentEscaped

        # TODO Validate properties.
        Write-Host "Properties loaded:"
        Write-Host "SessionHeader: $([string]$properties.SessionHeader)"
        Write-Host "ActiveMapIDs: $([string]$properties.ActiveMapIDs)"
        Write-Host "ActiveEventID: $([string]$properties.ActiveEventID)"
        Write-Host "AdditionalCMDFlags: $([string]$properties.AdditionalCMDFlags)"
        Write-Host "BackupPath: $([string]$properties.BackupPath)"
        Write-Host "ForceRespawnChance: $([int]([decimal]$properties.ForceRespawnChance * 100))%"
        Write-Host "MaxPlayers: $([int]$properties.MaxPlayers)"
    }

    # Perform requested operation.
    if ($serverop -eq 'restart') {
        restartServer
    } elseif ($serverop -eq 'shutdown') {
        shutdownServer
    } elseif ($serverop -eq 'backup') {
        backupServer
    } elseif ($serverop -eq 'update') {
        updateServer
    } elseif ($serverop -eq 'setup') {
        setup
    } elseif ($serverop -eq 'crashdetect') {
        crashDetect
    }

    # Wrap up and delete lockfile.
    Write-Host "Exiting ASAServerManager script and removing lock file."
    Remove-Item -Path "ASA.lock"
    
    # Stop logging to file
    Stop-Transcript
}

function restartServer {
    # Attempt shutdown.
    shutdownServer

    #Attempt startup.
    startServer
}

function startServer {
    # Update the server before running.
    updateServer

    # Server operation.
    Write-Host "Startup requested."

    # Return if server is already running.
    if (isServerRunning) { return }

    # Replace ini files with backups.
    Copy-Item -Path "ASAServers\ShooterGame\Saved\Config\WindowsServer\Game_Queued.ini" -Destination "ASAServers\ShooterGame\Saved\Config\WindowsServer\Game.ini" -Force
    Copy-Item -Path "ASAServers\ShooterGame\Saved\Config\WindowsServer\GameUserSettings_Queued.ini" -Destination "ASAServers\ShooterGame\Saved\Config\WindowsServer\GameUserSettings.ini" -Force

    # Determine additional parameters.
    $respawnDinoArgument = ""
    if ($rollforcerespawndinos)
    {
        $diceRoll = Get-Random -Minimum 1 -Maximum 100
        Write-Host "Rolling for -ForceRespawnDinos: $($diceRoll)"
        if ($diceRoll -lt $([decimal]$properties.ForceRespawnChance * 100)) {
            $respawnDinoArgument = "-ForceRespawnDinos"
            Write-Host "Dinos will be force respawed."
        }
    }
    $modIds = getActiveModIds

    # Start up all maps with a few minutes of stagger inbetween.
    Write-Host "Starting up server."
    $activeMapIds = getActiveMapIds
    for ($i = 0; $i -lt $activeMapIds.Length; $i++) {
        Write-Host "Loading map id $($activeMapIds[$i])."
        $commandLine = "cmd /c start '' /b ASAServers\ShooterGame\Binaries\Win64\ArkAscendedServer.exe $($maps[$activeMapIds[$i]].apiName)?SessionName='$($properties.SessionHeader) - $($maps[$activeMapIds[$i]].label)'?AltSaveDirectoryName=KC$($maps[$activeMapIds[$i]].apiName)Save?Port=$($portPool[$i].instancePort)?QueryPort=$($portPool[$i].queryPort)?RCONPort=$($portPool[$i].rconPort) $($respawnDinoArgument) -clusterID=$($properties.ClusterId) -WinLiveMaxPlayers=$($properties.MaxPlayers) -mods=$($modIds) $($properties.AdditionalCMDFlags)"
        Write-Host $commandLine
        Invoke-Expression $commandLine
        timeout /t 60 /nobreak
    }
}

function shutdownServer {
    # Server operation.
    Write-Host "Shutdown requested."

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
        timeout /t 55 /nobreak
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
    Write-Host "rcon: ServerChat [Server]: Server will be back online in approximately 10 minutes."
    for ($i = 0; $i -lt $listeningPorts.Length; $i++) { rcon "$($listeningPorts[$i])" "ServerChat [Server]: Server will be back online in approximately 10 minutes." }
    timeout /t 5 /nobreak
    Write-Host "rcon: ServerChat [Server]: That doesn't mean wait for it, go touch some grass.. :|"
    for ($i = 0; $i -lt $listeningPorts.Length; $i++) { rcon "$($listeningPorts[$i])" "ServerChat [Server]: That doesn't mean wait for it, go touch some grass.. :|" }
    timeout /t 1 /nobreak

    # Shutdown all maps.
    Write-Host "rcon: DoExit"
    for ($i = 0; $i -lt $listeningPorts.Length; $i++) { rcon "$($listeningPorts[$i])" "DoExit" }

    # Timeout up to 2 minutes for process to close before backup.
    Write-Host "Waiting for process to exit before performing backup."
    $backedUp = $false
    for ($i = 0; $i -lt 12; $i++) {
        timeout /t 10 /nobreak
        if (-Not (isServerRunning)) {
            # Create archive after shutdown.
            backupServer
            $backedUp = $true

            break
        }
    }

    # If true there may be an orphaned server running requiring a process kill.
    if (!$backedUp)
    {
        Write-Host "Backup failed because server was still running. ArkAscendedServer processes may need to be killed manually before proceeding."
        Write-Host "Also double check ASAServer.properties file. If invalid ActiveMapIDs are listed, they will cause zombie servers like this."
    }
}

function updateServer {
    # Server operation.
    Write-Host "Update requested."

    # Confirm server is not running.
    if (isServerRunning) {
        Write-Host "Cannot patch server while updating."
        return
    }

    # Update server using steamcmd.
    SteamCMD\steamcmd.exe +force_install_dir ../ASAServers/ +login anonymous +app_update 2430930 validate +quit
}

function backupServer {
    # Server operation.
    Write-Host "Backup requested."

    # Confirm server is not running.
    if (isServerRunning) {
        Write-Host "Cannot archive save data while server is running."
        return
    }

    # Archive backup of the Saved folder with YYYY-MM-DD-HHMM format.
    $archiveName = Get-Date -Format "yyyy-MM-dd_HHmm"
    Write-Host "Archiving Shootergame\Saved to $([string]$properties.BackupPath)\$($archiveName).rar"

    # If WinRAR installed use that, otherwise use default compression.
    if (Test-Path -Path "C:\Program Files\WinRAR\Rar.exe") {
        & "C:\Program Files\WinRAR\Rar.exe" a "$([string]$properties.BackupPath)\$archiveName.rar" "ASAServers\ShooterGame\Saved"
    } else {
        Compress-Archive -Path "ASAServers\ShooterGame\Saved" -DestinationPath "$([string]$properties.BackupPath)\$archiveName.zip" -CompressionLevel Optimal
    }
}

function crashDetect {
    # Confirm server is not running.
    if (isServerRunning) {
        Write-Host "No crash detected."
        return
    }

    # Crash detected, run restart now.
    $Script:now = $true
    $Script:rollforcerespawndinos = $false
    restartServer
}

function setup {
    # Setup project structure.
    Write-Host "Setting up project structure."
    New-Item -Path "ASAServers" -ItemType Directory
    New-Item -Path "Backups" -ItemType Directory
    New-Item -Path "RCON" -ItemType Directory
    New-Item -Path "SteamCMD" -ItemType Directory

    # Create properties file with initial values.
    $initialPropertiesValues = "" +
    "# Determines which map the server will host. (In future, comma delimited will allow clusters.)`n" +
    "ActiveMapIDs=TheIsland_WP`n" +
    "# Change this to overwride the default backup folder. (Use UNC paths for network folders.)`n" +
    "BackupPath=./Backups`n" +
    "# Chance that wild dinos will force respawn when using the -RollForceRespawnDinos argument. (0.25 = 25%, 0.75 = 75%, etc.)`n" +
    "ForceRespawnChance=0.25`n" +
    "# Sets the maximum concurrent players in your server.`n" +
    "MaxPlayers=20`n" +
    "# Copy the admin password you've set in GameUserSettings.ini here. (This allows the tool broadcast, save, and shutdown.)`n" +
    "AdminPassword=password123`n"
    New-Item -Path "ASAServer.properties" -ItemType File -Value $initialPropertiesValues
    
    # Download the utilities used by the script.
    Write-Host "Downloading & unpacking utilities used by the script."
    Invoke-WebRequest -Uri "https://github.com/gorcon/rcon-cli/releases/download/v0.10.3/rcon-0.10.3-win64.zip" -Outfile RCON.zip
    Expand-Archive -Path "RCON.zip" -DestinationPath "./RCON/"
    Invoke-WebRequest -Uri "https://steamcdn-a.akamaihd.net/client/installer/steamcmd.zip" -Outfile SteamCMD.zip
    Expand-Archive -Path "SteamCMD.zip" -DestinationPath "./SteamCMD/"
    
    # Relocate rcon-cli for easier access.
    Move-Item -Path "./RCON/rcon-0.10.3-win64/*" -Destination "./RCON"
    
    # Cleanup.
    Write-Host "Cleaning up."
    Remove-Item -Path "RCON.zip"
    Remove-Item -Path "SteamCMD.zip"
    Remove-Item -Path "./RCON/rcon-0.10.3-win64" -Recurse
    
    #Update steamcmd..
    Write-Host "Updating steamcmd"
    SteamCMD\steamcmd.exe +quit
    
    # Update the server before running.
    updateServer

    # Next steps.
    New-Item -Path "ASAServers/ShooterGame/Saved/Config/WindowsServer" -ItemType Directory
    Write-Host "`nSetup complete, check out the ASAServer.properties for important settings before starting the server."
    Write-Host "Also if you have GameUserSetting.ini and Game.ini you are planning on using, right now(before pressing enter) would be a great time"
    Write-Host "to copy them into the `"./ASAServers/ShooterGame/Saved/Config/WindowsServer folder`"."
    Pause

    # Create queued versions of ini files for easier configuration updates.
    if ((Test-Path -Path "./ASAServers/ShooterGame/Saved/Config/WindowsServer/Game.ini") -AND !(Test-Path -Path "./ASAServers/ShooterGame/Saved/Config/WindowsServer/Game_Queued.ini")) {
        Write-Host "Creating queues version of Game.ini"
        Copy-Item -Path "./ASAServers/ShooterGame/Saved/Config/WindowsServer/Game.ini" -Destination "./ASAServers/ShooterGame/Saved/Config/WindowsServer/Game_Queued.ini"
    } elseif (!(Test-Path -Path "./ASAServers/ShooterGame/Saved/Config/WindowsServer/Game.ini") -AND !(Test-Path -Path "./ASAServers/ShooterGame/Saved/Config/WindowsServer/Game_Queued.ini")) {
        Write-Host "Creating regular and queues versions of Game.ini"
        New-Item -Name "./ASAServers/ShooterGame/Saved/Config/WindowsServer/Game.ini" | Out-Null
        New-Item -Name "./ASAServers/ShooterGame/Saved/Config/WindowsServer/Game_Queued.ini" | Out-Null
    }
    if ((Test-Path -Path "./ASAServers/ShooterGame/Saved/Config/WindowsServer/GameUserSettings.ini")  -AND !(Test-Path -Path "./ASAServers/ShooterGame/Saved/Config/WindowsServer/GameUserSetting_Queued.ini")) {
        Write-Host "Creating queues version of GameUserSetting.ini"
        Copy-Item -Path "./ASAServers/ShooterGame/Saved/Config/WindowsServer/GameUserSettings.ini" -Destination "./ASAServers/ShooterGame/Saved/Config/WindowsServer/GameUserSetting_Queued.ini"
    }
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
    $activeModsLine = Get-Content -Path "ASAServers\ShooterGame\Saved\Config\WindowsServer\GameUserSettings.ini" | Where-Object { $_ -match "ActiveMods=" }

    #Testing adding events here,
    #$activeEventModId = "927084"
    $activeModsLine = "$($activeModsLine)"


    $activeMods = $activeModsLine -split "="

    return "$($properties.ActiveEventID),$($activeMods[1])"
}

# Get active maps from server properties.
function getActiveMapIds {

    # Get active map ids from properties.
    Write-Host "ActiveMapIDs: $($properties.ActiveMapIDs)"
    $activeMapIds = @($properties.ActiveMapIDs.split(",") | Select-Object -Unique)
    Write-Host "ActiveMap Count: $(Write-Output -NoEnumerate $activeMapIds.Length)"

    return Write-Output -NoEnumerate $activeMapIds
}

# Get which ports from the pool are being used.
function getListeningPorts {
    Write-Host "Checking for listening ports."
    [string[]]$listeningPorts = @()
    $listeningPortIndex = 0
    for ($i = 0; $i -lt $portPool.Length; $i++) {
        Write-Host "Loop i:$($i)"
        if (Test-NetConnection -ComputerName "127.0.0.1" -Port "$($portPool[$i].rconPort)" -InformationLevel Quiet)
        {
            Write-Host "Port $($portPool[$i].rconPort) is listening.."
            #[string[]]$listeningPorts[$listeningPortIndex] = $($portPool[$i].rconPort)
            [string[]]$listeningPorts += ,$($portPool[$i].rconPort)
            $listeningPortIndex++
        }
        else
        {
            Write-Host "Port $($portPool[$i].rconPort) is not listening.."
        }
    }

    Write-Host "Array $($listeningPorts)"
    
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
    Write-Host $commandLine
    Invoke-Expression $commandLine
}

# Class definition for map.
class Map {
    [String]$apiName
    [String]$label
}

# Class definition for port set.
class PortSet {
    [String]$instancePort
    [String]$rawPort
    [String]$queryPort
    [String]$rconPort
}

# Execute main logic.
main