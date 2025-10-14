[ [INSTALL](#installation) | [CONFIG](#configuration) | [USAGE](#usage) | [ADV CONFIG](#advanced-configuration) | [TROUBLESHOOTING](#troubleshooting) ]

# autorsm 

v420.69 *autors for autists* 

---
A robust server management script for running multiple dedicated server configurations with automatic restart capabilities, in-game server switching, and persistent configuration management.

- **Multiple Server Configurations**: Manage and switch between different JKA server mods and engines
- **Automatic Restart**: Servers automatically restart on close/quit/crash
- **In-Game Server Switching**: Uses jkas `rcon writeconfig` feature to monitor for filewrites, allowing an rcon user to switch between different server configurations without leaving the game
- **Screen Session Management**: Servers run in persistent screen sessions
- **Cross-Platform Engine Support**: Supports both Linux native and Windows (via Wine) server binaries
- **Automated Setup**: First-time setup installs all dependencies automatically
- **Scheduled Reboots**: Optional daily server reboots via cron
- **Auto-Start on Boot**: Automatically starts last run server config after system reboots

---

## INSTALLATION

- *System Requirements*
   - *Debian or Ubuntu-based Linux distribution (Debian preferred for server performance)*
   - *sudo privileges for initial setup*

1. Clone or download this repository to your server
   ```bash
   sudo apt-get install -y git && cd $HOME && git clone https://github.com/nihirisuto/jka
   ```
2. Ensure `autors.sh` is executable & run the first-time setup with sudo (sudo is only needed for first time setup):
   ```bash
   cd $HOME/jka && chmod +x autors.sh && sudo ./autors.sh
   ```
3. Follow prompt (y/n) to proceed with installation 
   - The setup process will check for and install:
      - GNU screen
      - Any required system compat packages (32bit architecture support, i386 libs) required to run jka servers
      - Wine (only if Windows servers are configured)
      - JKA base asset files & libcxa.so.1
   - The setup process will additionally:
      - Set up passwordless sudo for `/sbin/reboot`
      - Create user crontab entry jobs for auto-start and daily reboots (reboot set at 11am utc, 4am pst)
      - Create a `svr` symlink in `~/.local/bin` so that `svr` can be used from anywhere
4. Run `source ~/.bashrc` if you don't want to logout/login to proceed
5. Review [configuration](#configuration) section & then proceed to [usage](#usage).
---

## CONFIGURATION
[🔝](#autorsm)

#### Server Configuration File (servers.ini)

- The `servers.ini` file defines all available server configurations. Each section represents a different server setup.

   - Required Fields
      - `engine`: Path to the server engine binary (relative to script directory)
      - `gamefile`: Path to the game module (.so for Linux, .dll for Windows)
      - `servercfg`: Path to the server configuration file
      - `desc`: Human-readable description of the server
      - `public`: Set to "true" to make server public on master server list (default: "false")

   - Optional fields
      - `fs_game`: The fs_game directory name (defaults to "base" if not specified)
      - `server_say_prefix`: Console command for in-game messages (default: "say")
      - `writedirs`: Custom write directories to monitor for `rcon writeconfig` files (comma-separated)

- Example Configuration

   Note: All configurations will share assets/maps stored in `/base`

   ```ini
   [baselinux]
   desc=basejka (original 2003)
   engine=baselinux/linuxjampded
   gamefile=baselinux/jampgamei386.so
   servercfg=servercfg_global.cfg          # using global shared config file
   public=false                            # server is private, not broadcast to master.jkhub.org

   [basewin]
   desc=basejka (original 2003)
   engine=basewin/jampDed.exe
   gamefile=basewin/jampgamex86.dll
   servercfg=basewin/server.cfg            # using a server.cfg custom to this server configuration only
   public=true                             # server is public, broadcast to master.jkhub.org

   [basedjkalinux]
   desc=basedjka
   engine=basedjkalinux/linuxjampded
   gamefile=basedjkalinux/jampgamei386.so
   server_say_prefix=print                 # this engine uses "print" to broadcast messages from server to clients (default: say)
   servercfg=servercfg_global.cfg          # using global shared config file
   public=false                            # server is private, not broadcast to master.jkhub.org

   [japro]
   desc=japro
   engine=japro/linuxjampded
   gamefile=japro/jampgamex86_64.so
   servercfg=japro/server.cfg              # using a server.cfg custom to this server configuration only
   fs_game=japro                           # not using default fs_game 'base', game is launched with fs_game=japro
   writedirs=~/.local/share/TaystJK/japro  # rcon writeconfig writes to this directory using taystjk's japro build
   public=false
   ```

   *YBEProxy Note*: When `fs_game` is not provided and defaults to `base`, the script copies `jampgame` into the `base/` directory. For **ybeproxy** specifically, `JKA_YBEProxy.so` must also be copied into the `fs_game` directory (or `base/` if `fs_game` is not specified). This file is automatically copied & removed during cleanup.

- Custom Write Directories
   - Some mods write to non-standard directories. For in-game server switch detection, this script monitors write directories for .cfg files written with certain names. If when running a mod the writeconfig commands aren't being detected, find out where cfg files are written to and use the `writedirs` parameter in servers.ini to provide an override to that write location. Fully `svr stop` and `svr start` to re-initialize the scripts detection:

      ```ini
      [japro]
      engine=japro/linuxjampded
      gamefile=japro/jampgamex86_64.so
      servercfg=japro/server.cfg
      fs_game=japro
      writedirs=~/.local/share/TaystJK/japro
      ```

*Directory Structure*
```
autors/
├── autors.sh              # main script
├── servers.ini            # server configuration file
├── servercfg_global.cfg   # global server config, you can use one config for all servers if you'd like (specify in servers.ini)
├── .autors/               # internal script files
│   ├── autors_functions.sh
│   └── autors_onreboot.sh
|
├── base/                  # jka asset files directory
│   ├── assets0.pk3
│   ├── assets1.pk3
│   ├── assets2.pk3
│   ├── assets3.pk3
│   ├── ffa_gliese.pk3     # custom maps
│   └── ...
|
├── baselinux/             # example linux server bundle directory
│   ├── linuxjampded
│   └── jampgamei386.so
|
├── basewin/               # example windows server bundle directory
|   ├── jampDed.exe
|   ├── jampgamex86.dll
|   └── server.cfg         # example custom server.cfg for this server bundle only (specify in servers.ini)
|
└── ... other custom server config folders
```

---

## USAGE
[🔝](#autorsm)

After installation & configuration (make sure you set your RCON pass!), you can use the `svr` command from anywhere (after sourcing `source ~/.bashrc` or re-login).

#### Basic Commands

- `svr` - shows status of server and avail commands
   ```bash
   -----------------------------------------------------------------------
   Server Status:        RUNNING
   Port:                 29078
   Game:                 basedjkalinux
   Description:          basedjka
   Screen:               jka
   -----------------------------------------------------------------------
   
   Available Commands:
      svr resume        - Attach to screen console of running server
                        (Use Ctrl+A Ctrl+D to detach from screen)
      svr stop          - Stop the server
      svr restart       - Restart server
      svr <game> [port] - Start/restart server with specified game
   
   Available games:
      basedjkadocker basedjkalinux basedjkawin baselinux basewin japlus
      japro thesis ybeproxy
   
   Last used configuration: basedjkalinux on port 29078
   
   -----------------------------------------------------------------------
   ```

- `svr start` - start server with last used configuration
   ```bash
   (SVR) 2025-10-14 21:27:41  Starting server: basedjkalinux on port 29078
   
   -----------------------------------------------------------------------
   Server Status:        RUNNING
   Port:                 29078
   Game:                 basedjkalinux
   Description:          basedjka
   Screen:               jka
   -----------------------------------------------------------------------
   ...
   ```

- `svr stop` - stop the server
   ```bash
    (SVR) 2025-10-14 21:30:00  Stopping server...
   (SVR) 2025-10-14 21:30:02  Server stopped.
   
   -----------------------------------------------------------------------
   Server Status:        NOT RUNNING
   -----------------------------------------------------------------------
   ...
   ```

- `svr resume` - attach to the servers screen session (equivalent to `screen -r jka`). To detach use [Ctrl+A Ctrl+D]
   ```bash
   (SVR) 2025-10-14 21:31:03  Attaching to screen session 'jka'...
   ```
   ```bash
   (attached to screen session)
   ----------------------
   47488 files in pk3 files
   Loading dll file jampgame.
   Sys_LoadDll(/home/username/jka/basedjkalinux/jampgamei386.so)...
   Sys_LoadDll(jampgame) found **vmMain** at  0xf33e56c4
   Sys_LoadDll(jampgame) succeeded!
   ------- Game Initialization -------
   gamename: basejka
   gamedate: Oct 10 2025
   ------------------------------------------------------------
   InitGame: \dmflags\0\fraglimit\21\timelimit\10\capturelimit\0\g_privateDuel\0\g_saberLocking\0\g_maxForceRank\7\duel_fraglimit\10\g_forceBasedTeams\0\g_duelWeaponDisable\524279\g_gametype\6\g_needpass\0\sv_hostname\muppet\sv_maxclients\32\sv_maxRate\25000\sv_minPing\0\sv_maxPing\0\sv_floodProtect\1\sv_allowDownload\0\bg_fighteraltcontrol\0\g_debugmelee\0\g_forceregentime\200\g_saberwalldamagescale\0.4\g_stepslidefix\1\g_weapondisable\524279\g_forcepowerdisable\163837\g_maxGameClients\0\g_jediVmerc\0\g_siegeRespawn\20\g_siegeTeamSwitch\1\g_siegeTeam1\none\g_siegeTeam2\none\version\JAmp: v1.0.1.0 linux-i386 Oct 10 2025\g_maxHolocronCarry\3\protocol\26\mapname\mp/ffa3\sv_privateClients\0\g_noSpecMove\0\gamename\basejka\g_allowNPC\1\g_showDuelHealths\0
   Gametype changed, clearing session data.
   Hitch warning: 639 msec frame time
   ```
   To detach use [Ctrl+A Ctrl+D]
   ```bash
   [detached from 27630.jka]
   (you should be back at your main terminal)
   ```

- `svr restart` - restart the running server (shuts down and starts up with the currently used config)
- `svr <server config>` - start a server using the configuration provided
- `svr baselinux 29070` - start server with specific game and port
- `svr 29079` - Start server with specified port (using whatever server config was run last)
- `svr [game] [port]` - If a server is already running, you can change the server config or port
   ```bash
   svr basewin       # changes to basewin on currently running port
   svr 29078         # changes to port 29078 on currently running game
   svr basewin 29078 # changes to basewin and port 29078 
   ```

#### In-Game Commands

While the server is running, RCON users can use these in-game commands:

```
/rcon writeconfig <server_config>  # Switch to a different server configuration defined in servers.ini
/rcon writeconfig list             # Display all available server configurations (note: this broadcasts to everyone in server)
/rcon writeconfig restart          # Restart the current server
/rcon writeconfig reboot           # Reboot the entire machine
/rcon writeconfig cointoss         # Flip a coin (not sponsored by FaceIT unfortunately)
```

---

## Advanced Configuration
[🔝](#autorsm)

#### Auto-Start on Reboot

The `crontab -e` cron job `@reboot` entry executes `.autors/autors_onreboot.sh` which:
1. Waits 15 seconds for system initialization. Without waiting 15 seconds, `@reboot` entries will execute prematurely and the server won't start
2. Starts the server with the last used configuration
3. Logs output to `.autors/start_attempt.log`

#### Scheduled Daily Reboot

A cron entry is created for `0 11 * * *` (11:00 AM UTC) to execute `sudo /sbin/reboot`. This ensures the server gets a fresh start daily. The script configures passwordless sudo for the reboot command. To adjust this entry, use `crontab -e`

#### Wine Support

Wine is only installed if the script detects Windows server binaries (`.exe` files) in your `servers.ini` configuration.

If you add a Windows server configuration after initial setup where Wine wasn't installed and try to run it:
1. The script will detect Wine is missing
2. You'll be prompted to install Wine (y/n)
3. If you choose yes, Wine will be installed automatically
4. The server will then start normally

#### Disabling Daily Reboots

Edit your crontab to remove or comment out the reboot entry:
```bash
crontab -e
```

### Files

- **Configuration**: `servers.ini`
  - Contains definitions of server configurations that can be switched to
- **State files**: `.autors/autors_last_*`
  - State files persist the last-run server configuration so that they can be relaunched on reboot or by running `svr start`
- **PID files**: `.autors/autors_monitor_pid`
  - Contains PID number for the monitoring process that is listening for `rcon writeconfig <cmd>`. This is used internally by the script itself
- **Switch flags**: `.autors/autors_*_flag`
  - Used by the server manager to define switches that have been detected. 
- **Setup flag**: `.autors/.dependencies_installed`
  - After running the initial setup this file will be created & subsequent runs of this server manager will not prompt for dependency installation. If you need to run dependency installation again, remove this file and launch with sudo (`sudo ./autors.sh`)
- **Sudoers file**: `/etc/sudoers.d/autors-reboot`
  - This file is created to grant the current user passwordless permissions to reboot the machine. This is used for the automatic reboot (default 11am UTC) and the in-game `rcon writeconfig reboot` command. 

### Security Considerations

- The script requires sudo only for initial setup and system reboots
- Passwordless sudo is configured ONLY for `/sbin/reboot` command
- Server processes run as the regular user (not root)
- RCON password should be set in your server configuration files

---

## Troubleshooting
[🔝](#autorsm)

#### Server Won't Start

Check the screen session:
```bash
svr resume
```

View auto-start logs:
```bash
cat .autors/start_attempt.log
```

#### Wine Not Working for Windows Servers

Ensure Wine is installed:
```bash
wine --version
```

If not installed, run a Windows server to trigger installation:
```bash
svr basewin
```

#### Cron Jobs Not Working

Check crontab entries:
```bash
crontab -l
```

Verify sudo permissions:
```bash
sudo cat /etc/sudoers.d/autors-reboot
```

#### Screen Session Not Attaching

List all screen sessions:
```bash
screen -ls
```

Manually attach to the jka session:
```bash
screen -r jka
```

#### Asset Files Missing

The script automatically downloads asset files on first run. If they're missing:
```bash
ls -la base/assets*.pk3
```

Re-run first-time setup if needed (after removing `.autors/.dependencies_installed`):
```bash
rm .autors/.dependencies_installed
sudo ./autors.sh
```
