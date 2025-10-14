#!/bin/bash

#set -x

DEFAULT_PORT=29070
CHECK_INTERVAL=5

SCRIPT_PATH="$(readlink -f "$0")"
#SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
CONFIG_FILE="$SCRIPT_DIR/servers.ini"
cd "$SCRIPT_DIR" || exit 1

#state management files
PORT_FILE="$SCRIPT_DIR/.autors/autors_last_port"
GAME_FILE="$SCRIPT_DIR/.autors/autors_last_game"
SWITCH_FLAG="$SCRIPT_DIR/.autors/autors_switch_flag"
RESTART_FLAG="$SCRIPT_DIR/.autors/autors_restart_flag"
REBOOT_FLAG="$SCRIPT_DIR/.autors/autors_reboot_flag"
MONITOR_PID_FILE="$SCRIPT_DIR/.autors/autors_monitor_pid"

SPECIAL_COMMANDS=("restart" "reboot" "list" "help" "cointoss")

# load function library from .autors directory
FUNCTIONS_FILE="$SCRIPT_DIR/.autors/autors_functions.sh"
if [ ! -f "$FUNCTIONS_FILE" ]; then
    echo "Error: Functions library not found: $FUNCTIONS_FILE"
    exit 1
fi
source "$FUNCTIONS_FILE"

load_ini

# =============================================================================
# FIRST TIME DEPENDENCY CHECK
# =============================================================================

if ! in_jka_screen; then
    run_first_time_setup
fi

# =============================================================================
# SCREEN SESSION MANAGEMENT
# =============================================================================

if ! in_jka_screen; then
    if [ $# -eq 0 ]; then
        if screen -list | grep -q "\.jka[[:space:]]"; then
            show_server_info
            exit 0
        fi
    fi

    if [ $# -eq 1 ]; then
        case "${1,,}" in
            start|stop|restart|resume)
                handle_svr_command "${1,,}"
                exit 0
                ;;
        esac
    fi

    if screen -list | grep -q "\.jka[[:space:]]"; then
        if [ $# -gt 0 ]; then
            if is_valid_game "$1" || [[ $1 =~ ^[0-9]+$ ]]; then
                cecho -c yellow "Server already running. Stopping current server..."
                screen -S jka -X stuff "quit^M"
                sleep 3
                screen -S jka -X quit 2>/dev/null
                cecho "Starting new server..."
                screen -dmS jka bash "$SCRIPT_PATH" "$@"
                sleep 2
                show_server_info
                exit 0
            fi
        else
            cecho "Screen session 'jka' found. Attaching..."
            exec screen -r jka
        fi
    else
        if [ $# -eq 0 ]; then
            show_server_info
            exit 0
        fi
        cecho "Creating new screen session 'jka'..."
        screen -dmS jka bash "$SCRIPT_PATH" "$@"
        sleep 2
        show_server_info
        exit 0
    fi
    exit 0
fi

# =============================================================================
# INITIALIZATION (Inside Screen Session)
# =============================================================================

cecho -c green "Running inside screen session 'jka'"

# create default state files if they don't exist
if [ ! -f "$PORT_FILE" ]; then
    echo "$DEFAULT_PORT" > "$PORT_FILE"
fi
if [ ! -f "$GAME_FILE" ]; then
    echo "basedjkalinux" > "$GAME_FILE"
fi

# load last used game
LAST_GAME=""
if [ -f "$GAME_FILE" ]; then
    LAST_GAME=$(cat "$GAME_FILE")
fi

# clean up any existing game config files and flags
cleanup_game_configs
rm -f "$SWITCH_FLAG" "$RESTART_FLAG" "$REBOOT_FLAG" "$MONITOR_PID_FILE"

# =============================================================================
# COMMAND LINE ARGUMENT PARSING
# =============================================================================

PORT=""
selectedgame=""
VALID_GAMES=($(get_valid_games))

if [ $# -eq 0 ]; then
    # no arguments - use last port or default, and last game if exists
    PORT=$([ -f "$PORT_FILE" ] && cat "$PORT_FILE" || echo $DEFAULT_PORT)
    [ -n "$LAST_GAME" ] && selectedgame="$LAST_GAME"
    
elif [ $# -eq 1 ]; then
    # one argument - could be game or port
    if is_valid_game "$1"; then
        selectedgame="${1,,}"
        PORT=$([ -f "$PORT_FILE" ] && cat "$PORT_FILE" || echo $DEFAULT_PORT)
    elif [[ $1 =~ ^[0-9]+$ ]]; then
        PORT=$1
        [ -n "$LAST_GAME" ] && selectedgame="$LAST_GAME"
    else
        cecho -c red "Error: Argument must be a port number or one of: ${VALID_GAMES[*]}"
        exit 1
    fi
    
elif [ $# -eq 2 ]; then
    # two arguments - first should be game, second should be port
    if is_valid_game "$1"; then
        selectedgame="${1,,}"
        if [[ $2 =~ ^[0-9]+$ ]]; then
            PORT=$2
        else
            cecho -c red "Error: Second argument must be a port number"
            exit 1
        fi
    else
        cecho -c red "Error: First argument must be one of: ${VALID_GAMES[*]}"
        exit 1
    fi
else
    cecho -c red "Usage: $0 [game_option] [port_number]"
    cecho -c red "Game options: ${VALID_GAMES[*]}"
    cecho -c red "Default port: $DEFAULT_PORT"
    exit 1
fi

# validate that a game was selected
if [ -z "$selectedgame" ]; then
    cecho -c red "Error: No game selected and no previous game found."
    cecho -c red "Please specify a game: ${VALID_GAMES[*]}"
    exit 1
fi

# save state
echo "$PORT" > "$PORT_FILE"
echo "$selectedgame" > "$GAME_FILE"

cecho "Using port: $PORT"
cecho "Game selected: $selectedgame"

trap cleanup EXIT

# =============================================================================
# MAIN SERVER LOOP
# =============================================================================

while true; do
    # setup the game environment from INI config
    setup_game_environment "$selectedgame"

    # start background monitor for game switches
    game_switch_monitor &
    MONITOR_PID=$!

    echo $MONITOR_PID > "$MONITOR_PID_FILE"

    # start server in foreground (SERVER_CFG is already just the filename now)
    LAUNCHSERVER="$PREFIX +set fs_game $FS_GAME +set dedicated \"$DEDICATED\" +exec $SERVER_CFG +set net_port $PORT +set sv_master1 \"$SV_MASTER1\" +set g_motd $FS_GAME"
    cecho -c green "$LAUNCHSERVER"
    $LAUNCHSERVER
    status=$?

    # Clean up the server config file after server exits
    if [ -f "$FS_GAME/.__svrcfg.cfg" ]; then
        rm -f "$FS_GAME/.__svrcfg.cfg"
        cecho " > Cleaned up $FS_GAME/.__svrcfg.cfg"
    fi
    
    # Kill the monitor
    kill $MONITOR_PID 2>/dev/null
    wait $MONITOR_PID 2>/dev/null
    rm -f "$MONITOR_PID_FILE"
    
    # =============================================================================
    # HANDLE SERVER EXIT CONDITIONS
    # =============================================================================
    
    # check if this was a reboot request
    if [ -f "$REBOOT_FLAG" ]; then
        rm -f "$REBOOT_FLAG"
        cecho -c red "Reboot requested! Rebooting machine now..."
        sudo reboot
        exit 0
    fi
    
    # check if this was a restart request
    if [ -f "$RESTART_FLAG" ]; then
        rm -f "$RESTART_FLAG"
        cecho -c yellow "Restart requested! Restarting screen..."
        nohup bash -c "sleep 3; cd '$SCRIPT_DIR'; screen -dmS jka bash '$SCRIPT_PATH'" > /dev/null 2>&1 &
        disown
        sleep 1
        exit 0
    fi
    
    # check if this was a game switch
    if [ -f "$SWITCH_FLAG" ]; then
        new_game=$(cat "$SWITCH_FLAG")
        rm -f "$SWITCH_FLAG"
        selectedgame="$new_game"
        echo "$selectedgame" > "$GAME_FILE"
        cecho -c yellow "Game switch detected! Restarting screen with: $selectedgame"
        nohup bash -c "sleep 3; cd '$SCRIPT_DIR'; screen -dmS jka bash '$SCRIPT_PATH'" > /dev/null 2>&1 &
        disown
        sleep 1
        exit 0
    fi

    # handle other exit statuses
    if [ $status -eq 69 ]; then
        cecho -c green "Server quit gracefully (status: $status)"
        cecho -c white "Exiting"
        exit 0
    elif [ $status -ne 0 ]; then
        cecho -c red "Server crashed (status: $status)"
    else
        cecho -c cyan "Server shutdown gracefully."
    fi

    sleep 3
done

cecho -c white "Exiting"