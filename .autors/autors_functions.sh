#!/bin/bash

declare -A config

has_windows_servers() {
    for key in "${!config[@]}"; do
        if [[ $key =~ \.engine$ ]]; then
            local engine_path="${config[$key]}"
            if [[ "$engine_path" =~ \.exe$ ]]; then
                return 0
            fi
        fi
    done
    return 1
}

cecho() {
    local color="white"
    local message=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--color)
                color="$2"
                shift 2
                ;;
            *)
                message="$*"
                break
                ;;
        esac
    done
    
    case "${color,,}" in
        green)  color_code="\033[30;42m" ;;
        red)    color_code="\033[30;41m" ;;
        cyan)   color_code="\033[30;46m" ;;
        yellow) color_code="\033[30;43m" ;;
        white)  color_code="\033[30;47m" ;;
        *)      color_code="\033[30;47m" ;;
    esac
    
    echo -e "${color_code} (SVR) $(date '+%Y-%m-%d %H:%M:%S') \033[m $message"
}

load_ini() {
    local section=""
    
    if [ ! -f "$CONFIG_FILE" ]; then
        cecho -c red "Error: Configuration file '$CONFIG_FILE' not found!"
        exit 1
    fi
    
    while IFS= read -r line || [ -n "$line" ]; do  # Added: || [ -n "$line" ]
        line=$(echo "$line" | xargs)
        [[ -z $line || $line =~ ^# ]] && continue
        if [[ $line =~ ^\[(.+)\]$ ]]; then
            section="${BASH_REMATCH[1]}"
        elif [[ $line =~ ^([^=]+)=(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
            key=$(echo "$key" | xargs)
            value=$(echo "$value" | xargs)
            config["${section}.${key}"]="$value"
        fi
    done < "$CONFIG_FILE"
}

get_valid_games() {
    local games=()
    for key in "${!config[@]}"; do
        if [[ $key =~ ^([^.]+)\. ]]; then
            local section="${BASH_REMATCH[1]}"
            # Check if this section has required fields
            if [[ -n "${config[$section.engine]}" ]]; then
                games+=("$section")
            fi
        fi
    done
    # Remove duplicates and sort
    printf '%s\n' "${games[@]}" | sort -u
}

get_all_write_dirs() {
    local all_dirs=()
    local valid_games=($(get_valid_games))
    local g

    for g in "${valid_games[@]}"; do
        local writedirs="${config[$g.writedirs]}"
        if [[ -n "$writedirs" ]]; then
            IFS=',' read -ra dirs <<< "$writedirs"
            for dir in "${dirs[@]}"; do
                dir=$(echo "$dir" | xargs)
                dir=$(eval echo "$dir")
                all_dirs+=("$dir")
            done
        else
            local fs_game="${config[$g.fs_game]}"
            if [[ -z "$fs_game" ]]; then
                fs_game="$g"
            fi

            local engine_path="${config[$g.engine]}"
            if [[ "$engine_path" =~ \.exe$ ]]; then
                all_dirs+=("$fs_game")
            else
                all_dirs+=("$HOME/.ja/$fs_game")
                all_dirs+=("$HOME/.ja/base")
            fi
        fi
    done
    printf '%s\n' "${all_dirs[@]}" | sort -u
}

is_valid_game() {
    local arg="${1,,}"
    local valid_games=($(get_valid_games))
    
    for g in "${valid_games[@]}"; do
        if [ "$arg" == "${g,,}" ]; then
            return 0
        fi
    done
    return 1
}

in_jka_screen() {
    [[ "$STY" =~ jka ]] && return 0
    return 1
}

cleanup_game_configs() {
    
    cecho "Cleaning up game config files..."
    local valid_games=($(get_valid_games))
    local write_dirs=($(get_all_write_dirs))
    local cmd
    
    for dir in "${write_dirs[@]}"; do
        if [ -d "$dir" ]; then
            # Clean up game configs
            for g in "${valid_games[@]}"; do
                local cfg_file="$dir/${g}.cfg"
                if [ -f "$cfg_file" ]; then
                    cecho " > Removing $cfg_file"
                    rm -f "$cfg_file"
                fi
            done
            # Clean up special command configs
            for cmd in "${SPECIAL_COMMANDS[@]}"; do
                local cfg_file="$dir/${cmd}.cfg"
                if [ -f "$cfg_file" ]; then
                    cecho " > Removing $cfg_file"
                    rm -f "$cfg_file"
                fi
            done
        fi
    done
    
}

check_for_game_switch() {
    local valid_games=($(get_valid_games))
    local write_dirs=($(get_all_write_dirs))
    
    for dir in "${write_dirs[@]}"; do
        if [ -d "$dir" ]; then
            for g in "${valid_games[@]}"; do
                local cfg_file="$dir/${g}.cfg"
                if [ -f "$cfg_file" ]; then
                    rm -f "$cfg_file"
                    echo "$g"
                    return 0
                fi
            done
        fi
    done
    return 1
}

coin_toss() {
    result=$((RANDOM % 2))
    if [ $result -eq 0 ]; then
        echo "Heads"
    else
        echo "Tails"
    fi
}


check_for_special_command() {
    local write_dirs=($(get_all_write_dirs))
    
    for dir in "${write_dirs[@]}"; do
        if [ -d "$dir" ]; then
            if [ -f "$dir/restart.cfg" ]; then
                rm -f "$dir/restart.cfg"
                echo "restart"
                return 0
            fi
            if [ -f "$dir/reboot.cfg" ]; then
                rm -f "$dir/reboot.cfg"
                echo "reboot"
                return 0
            fi
            if [ -f "$dir/list.cfg" ]; then
                rm -f "$dir/list.cfg"
                echo "list"
                return 0
            fi
            if [ -f "$dir/help.cfg" ]; then
                rm -f "$dir/help.cfg"
                echo "help"
                return 0
            fi
            if [ -f "$dir/cointoss.cfg" ]; then
                rm -f "$dir/cointoss.cfg"
                echo "cointoss"
                return 0
            fi
        fi
    done
    return 1
}

show_game_list() {
    local valid_games=($(get_valid_games))
    local g  # Declare loop variable as local

    cecho -c cyan "Displaying game list in-game..."

    local max_game_length=0
    for g in "${valid_games[@]}"; do
        local len=${#g}
        if [ $len -gt $max_game_length ]; then
            max_game_length=$len
        fi
    done

    local restart_cmd="restart"
    local reboot_cmd="reboot"
    if [ ${#restart_cmd} -gt $max_game_length ]; then
        max_game_length=${#restart_cmd}
    fi
    if [ ${#reboot_cmd} -gt $max_game_length ]; then
        max_game_length=${#reboot_cmd}
    fi

    local max_desc_length=0
    for g in "${valid_games[@]}"; do
        local desc="${config[$g.desc]}"
        if [ -z "$desc" ]; then
            desc="No description"
        fi
        local len=${#desc}
        if [ $len -gt $max_desc_length ]; then
            max_desc_length=$len
        fi
    done

    local restart_desc="restarts server"
    local reboot_desc="reboots machine"
    if [ ${#restart_desc} -gt $max_desc_length ]; then
        max_desc_length=${#restart_desc}
    fi
    if [ ${#reboot_desc} -gt $max_desc_length ]; then
        max_desc_length=${#reboot_desc}
    fi

    for g in "${valid_games[@]}"; do
        local desc="${config[$g.desc]}"
        if [ -z "$desc" ]; then
            desc="No description"
        fi

        local engine_path="${config[$g.engine]}"
        local platform
        if [[ "$engine_path" =~ \.exe$ ]]; then
            platform="[Windows]"
        else
            platform="[Linux]"
        fi
        
        local game_padding_length=$((max_game_length - ${#g}))
        local game_padding=""
        if [ $game_padding_length -gt 0 ]; then
            game_padding=$(printf '.%.0s' $(seq 1 $game_padding_length))
        fi
        
        local desc_padding_length=$((max_desc_length - ${#desc}))
        local desc_padding=""
        if [ $desc_padding_length -gt 0 ]; then
            desc_padding=$(printf '.%.0s' $(seq 1 $desc_padding_length))
        fi
        
        screen -S jka -p 0 -X stuff "$SERVER_SAY_PREFIX \^2rcon writeconfig $g\^0$game_padding\^7 $desc\^0$desc_padding\^7 $platform^M"
        sleep 0.3
    done
    
    sleep 0.2
    
    local restart_game_padding_length=$((max_game_length - ${#restart_cmd}))
    local restart_game_padding=""
    if [ $restart_game_padding_length -gt 0 ]; then
        restart_game_padding=$(printf '.%.0s' $(seq 1 $restart_game_padding_length))
    fi
    local restart_desc_padding_length=$((max_desc_length - ${#restart_desc}))
    local restart_desc_padding=""
    if [ $restart_desc_padding_length -gt 0 ]; then
        restart_desc_padding=$(printf '.%.0s' $(seq 1 $restart_desc_padding_length))
    fi
    screen -S jka -p 0 -X stuff "$SERVER_SAY_PREFIX \^2rcon writeconfig restart\^0$restart_game_padding\^7 $restart_desc\^0$restart_desc_padding^M"
    sleep 0.3
    
    local reboot_game_padding_length=$((max_game_length - ${#reboot_cmd}))
    local reboot_game_padding=""
    if [ $reboot_game_padding_length -gt 0 ]; then
        reboot_game_padding=$(printf '.%.0s' $(seq 1 $reboot_game_padding_length))
    fi
    local reboot_desc_padding_length=$((max_desc_length - ${#reboot_desc}))
    local reboot_desc_padding=""
    if [ $reboot_desc_padding_length -gt 0 ]; then
        reboot_desc_padding=$(printf '.%.0s' $(seq 1 $reboot_desc_padding_length))
    fi
    screen -S jka -p 0 -X stuff "$SERVER_SAY_PREFIX \^2rcon writeconfig reboot\^0$reboot_game_padding\^7  $reboot_desc\^0$reboot_desc_padding^M"
}

game_switch_monitor() {
    while true; do
        if special_cmd=$(check_for_special_command); then
            case "$special_cmd" in
                restart)
                    cecho -c yellow "Found restart.cfg - restarting server..."
                    screen -S jka -p 0 -X stuff "$SERVER_SAY_PREFIX \^3*** Server Restart Requested *** \^9restarting in 5 seconds ...^M"
                    sleep 5
                    touch "$RESTART_FLAG"
                    screen -S jka -p 0 -X stuff "quit^M"
                    exit 0
                    ;;
                reboot)
                    cecho -c yellow "Found reboot.cfg - rebooting server machine..."
                    screen -S jka -p 0 -X stuff "$SERVER_SAY_PREFIX \^1*** SERVER REBOOT REQUESTED *** \^9machine will reboot in 10 seconds ...^M"
                    sleep 10
                    touch "$REBOOT_FLAG"
                    screen -S jka -p 0 -X stuff "quit^M"
                    exit 0
                    ;;
                list|help)
                    cecho -c cyan "Found ${special_cmd}.cfg - displaying game list..."
                    show_game_list
                    ;;
                cointoss)
                    cointoss=$(coin_toss)
                    cecho -c yellow "Found cointoss.cfg - printing cointoss msg..."
                    screen -S jka -p 0 -X stuff "$SERVER_SAY_PREFIX \^3*** COINTOSS *** \^7Result: \^5${cointoss} ^M"
                    ;;
            esac
        fi
        
        if new_game=$(check_for_game_switch); then
            cecho -c yellow "Found ${new_game}.cfg - sending quit command to server..."
            screen -S jka -p 0 -X stuff "$SERVER_SAY_PREFIX \^2*** Switch Requested *** \^9server will switch to \^3${new_game}\^9 in 5 seconds ...^M"
            sleep 5
            echo "$new_game" > "$SWITCH_FLAG"
            screen -S jka -p 0 -X stuff "quit^M"
            exit 0
        fi
        
        sleep $CHECK_INTERVAL
    done
}

cleanup_copied_files() {

    cecho "Cleaning up copied engine and game module files..."
    local valid_games=($(get_valid_games))
    local g

    for g in "${valid_games[@]}"; do
        local engine_path="${config[$g.engine]}"
        local gamefile_path="${config[$g.gamefile]}"
        local fs_game="${config[$g.fs_game]}"

        # Default fs_game to "base" if not provided
        if [ -z "$fs_game" ]; then
            fs_game="base"
        fi

        if [ -n "$engine_path" ]; then
            local engine_basename="$(basename "$engine_path")"
            if [ -f "$engine_basename" ]; then
                cecho " > Removing $engine_basename"
                rm -f "$engine_basename"
            fi
        fi

        if [ -n "$gamefile_path" ]; then
            local gamefile_basename="$(basename "$gamefile_path")"
            if [ -f "$gamefile_basename" ]; then
                cecho " > Removing $gamefile_basename"
                rm -f "$gamefile_basename"
            fi

            # Also remove from base directory if fs_game is "base"
            if [[ "$fs_game" == "base" ]] && [ -f "base/$gamefile_basename" ]; then
                cecho " > Removing base/$gamefile_basename"
                rm -f "base/$gamefile_basename"
            fi

            # YBEProxy edge case: remove JKA_YBEProxy.so from fs_game directory
            if [ -f "$fs_game/JKA_YBEProxy.so" ]; then
                cecho " > Removing $fs_game/JKA_YBEProxy.so"
                rm -f "$fs_game/JKA_YBEProxy.so"
            fi
        fi

        if [ -n "$fs_game" ] && [ -d "$fs_game" ]; then
            if [ -f "$fs_game/.__svrcfg.cfg" ]; then
                cecho " > Removing $fs_game/.__svrcfg.cfg"
                rm -f "$fs_game/.__svrcfg.cfg"
            fi
        fi
    done

}

setup_game_environment() {
    local g="$1"

    if [[ -z "${config[$g.engine]}" ]]; then
        cecho -c red "Error: Game '$g' not found in configuration!"
        exit 1
    fi

    cleanup_copied_files

    local engine_path="${config[$g.engine]}"
    local gamefile_path="${config[$g.gamefile]}"
    local servercfg_path="${config[$g.servercfg]}"
    local fs_game="${config[$g.fs_game]}"
    local say_prefix="${config[$g.server_say_prefix]}"
    local public="${config[$g.public]}"

    # Default fs_game to "base" if not provided
    if [ -z "$fs_game" ]; then
        fs_game="base"
    fi

    if [ -z "$say_prefix" ]; then
        say_prefix="say"
    fi

    local sv_master1=""
    local dedicated=""
    if [[ "${public,,}" == "true" ]]; then
        sv_master1="master.jkhub.org"
        dedicated="2"
    else
        sv_master1=" "
        dedicated="1"
    fi

    local is_windows=false
    if [[ "$engine_path" =~ \.exe$ ]]; then
        is_windows=true

        # Check if Wine is installed
        if ! command -v wine &> /dev/null; then
            cecho -c red "Error: This server requires Wine but it is not installed."
            cecho -c yellow "Wine is required to run Windows server binaries (.exe files)."
            echo ""
            read -p "Would you like to install Wine now? (y/n): " -n 1 -r
            echo ""

            if [[ $REPLY =~ ^[Yy]$ ]]; then
                check_sudo

                cecho -c cyan "Installing Wine..."
                if install_wine; then
                    cecho -c green "Wine installed successfully. Continuing with server start..."
                else
                    cecho -c red "Wine installation failed. Cannot start Windows server."
                    exit 1
                fi
            else
                cecho -c yellow "Wine installation declined. Cannot start Windows server."
                cecho -c yellow "To run this server later, install Wine manually or run with a Linux server."
                exit 1
            fi
        fi
    fi

    cecho "Using configs for server start from: [$g]"
    cecho " > [engine]            $engine_path"
    cecho " > [gamefile]          $gamefile_path"
    cecho " > [fs_game]           $fs_game"
    cecho " > [servercfg]         $servercfg_path"
    cecho " > [server_say_prefix] $say_prefix"
    cecho " > [public]            ${public:-false}"
    

    cecho "Placing files for server start"
    if [ -f "$engine_path" ]; then
        local engine_basename="$(basename "$engine_path")"
        cp "$engine_path" "$engine_basename"
        chmod +x "$engine_basename" 2>/dev/null
        cecho " >      copied engine: $engine_basename"
        if [ "$is_windows" = true ]; then
            export PREFIX="wine $engine_basename"
            cecho " >     setting prefix: $PREFIX (windows using wine)"
        else
            export PREFIX="./$engine_basename"
            cecho " >     setting prefix: $PREFIX (linux)"
        fi
    else
        cecho -c red "Error: Engine file not found: $engine_path"
        exit 1
    fi
    
    if [ -n "$gamefile_path" ] && [ -f "$gamefile_path" ]; then
        local gamefile_basename="$(basename "$gamefile_path")"
        cp "$gamefile_path" .
        cecho " > copied game module: $gamefile_basename"

        # Also copy to base directory if fs_game is "base"
        if [[ "$fs_game" == "base" ]]; then
            if [ ! -d "base" ]; then
                mkdir -p "base"
                cecho " >   created base directory"
            fi
            cp "$gamefile_path" "base/$gamefile_basename"
            cecho " >  copied game module to base: base/$gamefile_basename"
        fi
    elif [ -n "$gamefile_path" ]; then
        cecho -c red "Warning: Game module file not found: $gamefile_path"
    fi

    # YBEProxy edge case: copy JKA_YBEProxy.so to fs_game directory
    local gamefile_dir="$(dirname "$gamefile_path")"
    local ybeproxy_file="$gamefile_dir/JKA_YBEProxy.so"
    if [ -f "$ybeproxy_file" ]; then
        if [ ! -d "$fs_game" ]; then
            mkdir -p "$fs_game"
            cecho " > created fs_game directory: $fs_game"
        fi
        cp "$ybeproxy_file" "$fs_game/JKA_YBEProxy.so"
        cecho " > copied YBEProxy module: $fs_game/JKA_YBEProxy.so"
    fi

    if [ -n "$servercfg_path" ] && [ -f "$servercfg_path" ]; then
        if [ ! -d "$fs_game" ]; then
            mkdir -p "$fs_game"
            cecho " > created fs_game directory: $fs_game"
        fi
        cp "$servercfg_path" "$fs_game/.__svrcfg.cfg"
        cecho " >  copied server cfg: $fs_game/.__svrcfg.cfg"
        export SERVER_CFG=".__svrcfg.cfg"
    elif [ -n "$servercfg_path" ]; then
        cecho -c red "Warning: Server config file not found: $servercfg_path"
        export SERVER_CFG="server.cfg"
    else
        export SERVER_CFG="server.cfg"
    fi

	

    export FS_GAME="$fs_game"
    export SERVER_SAY_PREFIX="$say_prefix"
    export SV_MASTER1="$sv_master1"
    export DEDICATED="$dedicated"
}

cleanup() {
    if [ -f "$MONITOR_PID_FILE" ]; then
        MONITOR_PID=$(cat "$MONITOR_PID_FILE")
        kill $MONITOR_PID 2>/dev/null
        rm -f "$MONITOR_PID_FILE"
    fi
}


# =============================================================================
# FIRST-TIME SETUP FUNCTIONS
# =============================================================================

check_sudo() {
    if [ "$EUID" -ne 0 ]; then
        cecho -c red "Error: First-time setup requires sudo privileges."
        cecho -c yellow "Please run: sudo bash $SCRIPT_PATH"
        exit 1
    fi
}

install_asset_files() {
    cecho -c cyan "Checking for asset files..."
    
    if [ -d "$SCRIPT_DIR/base" ] && \
       [ -f "$SCRIPT_DIR/base/assets0.pk3" ] && \
       [ -f "$SCRIPT_DIR/base/assets1.pk3" ] && \
       [ -f "$SCRIPT_DIR/base/assets2.pk3" ] && \
       [ -f "$SCRIPT_DIR/base/assets3.pk3" ]; then
        cecho -c green "Asset files already exist. Skipping."
        return 0
    fi
    
    cecho -c yellow "Installing asset files..."
    cd "$SCRIPT_DIR" || exit 1
    
    git clone --depth 1 https://github.com/nihirisuto/dep.git || {
        cecho -c red "Error: Failed to clone asset repository"
        return 1
    }
    
    mkdir -p base && cd base || {
        cecho -c red "Error: Failed to create base directory"
        return 1
    }
    
    for i in {0..3}; do
        cecho " *** Creating assets${i}.pk3..."
        find ../dep/dep/ -name "dep${i}_*" -type f | sort | xargs cat > assets${i}.pk3 || {
            cecho -c red "Error: Failed to create assets${i}.pk3"
            return 1
        }
    done
    
    if [ -f "../dep/libcxa.so.1" ]; then
        mv ../dep/libcxa.so.1 /usr/lib/libcxa.so.1
        cecho " *** Installed libcxa.so.1 to /usr/lib/"
    fi
    
    cd "$SCRIPT_DIR" || exit 1
    rm -rf dep

    local actual_user="${SUDO_USER:-$USER}"
    chown -R "$actual_user:$actual_user" "$SCRIPT_DIR/base"

    cecho -c green "Asset files created successfully in $SCRIPT_DIR/base"
    return 0
}

install_system_packages() {
    cecho -c cyan "Checking system packages..."
    
    local need_install=false
    
    if ! dpkg --print-foreign-architectures | grep -q i386; then
        need_install=true
    fi
    
    if ! command -v git &> /dev/null; then
        need_install=true
    fi
    
    if ! dpkg -l | grep -q "screen"; then
        need_install=true
    fi
    
    if ! dpkg -l | grep -q "libstdc++6:i386"; then
        need_install=true
    fi
    
    if ! dpkg -l | grep -q "libc6-i386"; then
        need_install=true
    fi
    
    if [ "$need_install" = false ]; then
        cecho -c green "All required packages already installed. Skipping."
        return 0
    fi
    
    cecho -c yellow "Installing system packages..."
    
    dpkg --add-architecture i386 || {
        cecho -c red "Error: Failed to add i386 architecture"
        return 1
    }
    
    apt-get update || {
        cecho -c red "Error: Failed to update package list"
        return 1
    }
    
    apt-get install -y git screen libstdc++6:i386 libc6-i386 || {
        cecho -c red "Error: Failed to install packages"
        return 1
    }
    
    cecho -c green "System packages installed successfully"
    return 0
}

install_wine() {
    cecho -c cyan "Checking for Wine..."
    
    if command -v wine &> /dev/null; then
        cecho -c green "Wine already installed. Skipping."
        return 0
    fi
    
    cecho -c yellow "Installing Wine..."
    
    if ! command -v gpg &> /dev/null; then
        cecho " *** Installing gpg (required for Wine installation)..."
        apt-get install -y gnupg || {
            cecho -c red "Error: Failed to install gnupg"
            return 1
        }
    fi
    
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_ID="${ID,,}"
        OS_VERSION_CODENAME="${VERSION_CODENAME}"
    else
        cecho -c red "Error: Cannot detect OS version"
        return 1
    fi
    
    case "$OS_ID" in
        debian)
            cecho " *** Detected Debian ($OS_VERSION_CODENAME)"
            mkdir -pm755 /etc/apt/keyrings
            wget -O /etc/apt/keyrings/winehq-archive.key https://dl.winehq.org/wine-builds/winehq.key || {
                cecho -c red "Error: Failed to download Wine repository key"
                return 1
            }
            
            wget -NP /etc/apt/sources.list.d/ https://dl.winehq.org/wine-builds/debian/dists/${OS_VERSION_CODENAME}/winehq-${OS_VERSION_CODENAME}.sources || {
                cecho -c red "Error: Failed to add Wine repository"
                return 1
            }
            ;;
            
        ubuntu)
            cecho " *** Detected Ubuntu ($OS_VERSION_CODENAME)"
            mkdir -pm755 /etc/apt/keyrings
            wget -O /etc/apt/keyrings/winehq-archive.key https://dl.winehq.org/wine-builds/winehq.key || {
                cecho -c red "Error: Failed to download Wine repository key"
                return 1
            }
            
            wget -NP /etc/apt/sources.list.d/ https://dl.winehq.org/wine-builds/ubuntu/dists/${OS_VERSION_CODENAME}/winehq-${OS_VERSION_CODENAME}.sources || {
                cecho -c red "Error: Failed to add Wine repository"
                return 1
            }
            ;;
            
        *)
            cecho -c red "Error: Unsupported OS: $OS_ID"
            cecho -c red "Wine installation only supports Debian and Ubuntu"
            return 1
            ;;
    esac
    
    apt-get update || {
        cecho -c red "Error: Failed to update package list after adding Wine repository"
        return 1
    }
    
    apt-get install -y --install-recommends winehq-stable || {
        cecho -c red "Error: Failed to install Wine"
        return 1
    }
    
    cecho -c green "Wine installed successfully"
    return 0
}

setup_sudo_permissions() {
    cecho -c cyan "Setting up sudo permissions for reboot..."

    local actual_user="${SUDO_USER:-$USER}"
    local sudoers_file="/etc/sudoers.d/autors-reboot"
    local sudoers_entry="$actual_user ALL=(ALL) NOPASSWD: /sbin/reboot"

    if [ -f "$sudoers_file" ]; then
        if grep -q "$actual_user.*NOPASSWD.*reboot" "$sudoers_file"; then
            cecho -c green "Sudo permissions already configured"
            return 0
        fi
    fi

    cecho " *** Adding passwordless sudo for /sbin/reboot"
    echo "$sudoers_entry" > "$sudoers_file" || {
        cecho -c red "Error: Failed to create sudoers file"
        return 1
    }

    chmod 0440 "$sudoers_file" || {
        cecho -c red "Error: Failed to set permissions on sudoers file"
        return 1
    }

    visudo -c -f "$sudoers_file" &>/dev/null || {
        cecho -c red "Error: Invalid sudoers syntax, removing file"
        rm -f "$sudoers_file"
        return 1
    }

    cecho -c green "Sudo permissions configured successfully"
    return 0
}

setup_crontab() {
    cecho -c cyan "Setting up crontab entries..."

    local onreboot_script="$SCRIPT_DIR/.autors/autors_onreboot.sh"
    local reboot_entry="@reboot $onreboot_script"
    local daily_reboot_entry="0 11 * * * sudo /sbin/reboot"

    if [ -f "$onreboot_script" ]; then
        chmod +x "$onreboot_script"
        cecho " *** Made autors_onreboot.sh executable"
    else
        cecho -c yellow "Warning: $onreboot_script not found. You may need to create it."
    fi

    local actual_user="${SUDO_USER:-$USER}"
    local current_cron=$(crontab -u "$actual_user" -l 2>/dev/null || echo "")
    local needs_update=false

    if ! echo "$current_cron" | grep -F "$onreboot_script" > /dev/null; then
        cecho " *** Adding @reboot entry for autors_onreboot.sh"
        current_cron="${current_cron}${current_cron:+$'\n'}$reboot_entry"
        needs_update=true
    else
        cecho -c green "@reboot entry already exists"
    fi

    if ! echo "$current_cron" | grep -q "^0 11 \* \* \* sudo /sbin/reboot"; then
        cecho " *** Adding daily 11am UTC reboot entry"
        current_cron="${current_cron}${current_cron:+$'\n'}$daily_reboot_entry"
        needs_update=true
    else
        cecho -c green "Daily reboot entry already exists"
    fi

    if [ "$needs_update" = true ]; then
        echo "$current_cron" | crontab -u "$actual_user" - || {
            cecho -c red "Error: Failed to update crontab"
            return 1
        }
        cecho -c green "Crontab updated successfully"
    fi

    return 0
}

setup_symlink() {
    cecho -c cyan "Setting up symlink and PATH..."
    
    local actual_user="${SUDO_USER:-$USER}"
    local actual_home=$(eval echo "~$actual_user")
    local local_bin="$actual_home/.local/bin"
    local symlink_path="$local_bin/svr"
    local bashrc="$actual_home/.bashrc"
    
    if [ ! -d "$local_bin" ]; then
        mkdir -p "$local_bin"
        chown "$actual_user:$actual_user" "$local_bin"
        cecho " *** Created $local_bin"
    fi
    
    if [ -L "$symlink_path" ]; then
        rm -f "$symlink_path"
        cecho " *** Removed old symlink"
    fi
    
    ln -s "$SCRIPT_PATH" "$symlink_path" || {
        cecho -c red "Error: Failed to create symlink"
        return 1
    }
    
    chown -h "$actual_user:$actual_user" "$symlink_path"
    cecho -c green "Created symlink: svr -> $SCRIPT_PATH"
    
    if ! grep -q 'PATH.*\.local/bin' "$bashrc"; then
        cecho " *** Adding ~/.local/bin to PATH in .bashrc"
        echo '' >> "$bashrc"
        echo '# Added by autors setup' >> "$bashrc"
        echo 'if [ -d "$HOME/.local/bin" ]; then' >> "$bashrc"
        echo '    export PATH="$HOME/.local/bin:$PATH"' >> "$bashrc"
        echo 'fi' >> "$bashrc"
        chown "$actual_user:$actual_user" "$bashrc"
        cecho -c green "Updated .bashrc with PATH"
    else
        cecho -c green "PATH already includes ~/.local/bin"
    fi
    
    cecho -c cyan "You can now run 'svr' from anywhere (after sourcing .bashrc or re-login)"
    
    return 0
}

show_server_info() {
    echo " "
    echo "-----------------------------------------------------------------------"
    if screen -list | grep -q "\.jka[[:space:]]"; then
        # server info section
        echo " Server Status:        RUNNING"

        if [ -f "$PORT_FILE" ]; then
            local current_port=$(cat "$PORT_FILE")
            echo " Port:                 $current_port"
        fi

        if [ -f "$GAME_FILE" ]; then
            local current_game=$(cat "$GAME_FILE")
            echo " Game:                 $current_game"

            local desc="${config[$current_game.desc]}"
            if [ -n "$desc" ]; then
                echo " Description:          $desc"
            fi
        fi

        echo " Screen:               jka"
        serverrunning=1
    else
        echo " Server Status:        NOT RUNNING"
        serverrunning=0
    fi

    # cmd help info
    echo "-----------------------------------------------------------------------"
    echo "  "
    echo " Available Commands:"
    if [ $serverrunning -eq 1 ]; then
        echo "   svr resume        - Attach to screen console of running server"
        echo "                       (Use Ctrl+A Ctrl+D to detach from screen)"
    else
        echo "   svr start         - Start server with last/default configuration"
    fi
    echo "   svr stop          - Stop the server"
    echo "   svr restart       - Restart server"
    echo "   svr <game> [port] - Start/restart server with specified game"
    echo "  "
    local games_list="$(get_valid_games | tr '\n' ' ')"
    local games_line=" Available games: $games_list"
    if [ ${#games_line} -gt 69 ]; then
        echo " Available games:"
        echo "$games_list" | fmt -w 67 | while read -r line; do
            echo "   $line"
        done
    else
        echo "$games_line"
    fi

    if [ -f "$PORT_FILE" ] && [ -f "$GAME_FILE" ]; then
        local last_port=$(cat "$PORT_FILE")
        local last_game=$(cat "$GAME_FILE")
        echo "  "
        echo " Last used configuration: $last_game on port $last_port"
    fi

    echo "  "
    echo "-----------------------------------------------------------------------"
    echo " "
}

handle_svr_command() {
    local cmd="$1"
    shift

    case "$cmd" in
        resume)
            if screen -list | grep -q "\.jka[[:space:]]"; then
                cecho "Attaching to screen session 'jka'..."
                exec screen -r jka
            else
                cecho -c red "No server is running. Use 'svr start' or 'svr <game> [port]' to start one."
                exit 1
            fi
            ;;

        restart)
            if screen -list | grep -q "\.jka[[:space:]]"; then
                cecho -c yellow "Restarting server..."
                screen -S jka -X stuff "quit^M"
                sleep 3
                screen -S jka -X quit 2>/dev/null

                local port=$([ -f "$PORT_FILE" ] && cat "$PORT_FILE" || echo $DEFAULT_PORT)
                local game=$([ -f "$GAME_FILE" ] && cat "$GAME_FILE" || echo "")

                if [ -z "$game" ]; then
                    cecho -c red "Error: No previous game configuration found"
                    exit 1
                fi

                screen -dmS jka bash "$SCRIPT_PATH" "$game" "$port"
                sleep 2
                show_server_info
                exit 0
            else
                cecho -c red "No server is running to restart."
                exit 1
            fi
            ;;

        start)
            if screen -list | grep -q "\.jka[[:space:]]"; then
                cecho -c red "Server is already running. Use 'svr restart' to restart or 'svr stop' to stop first."
                exit 1
            fi

            local port=$([ -f "$PORT_FILE" ] && cat "$PORT_FILE" || echo $DEFAULT_PORT)
            local game=$([ -f "$GAME_FILE" ] && cat "$GAME_FILE" || echo "")

            if [ -z "$game" ]; then
                local valid_games=($(get_valid_games))
                if [ ${#valid_games[@]} -gt 0 ]; then
                    game="${valid_games[0]}"
                    cecho -c yellow "No previous game found, using default: $game"
                else
                    cecho -c red "Error: No games configured in servers.ini"
                    exit 1
                fi
            fi

            cecho -c green "Starting server: $game on port $port"
            screen -dmS jka bash "$SCRIPT_PATH" "$game" "$port"
            sleep 2
            show_server_info
            exit 0
            ;;

        stop)
            if screen -list | grep -q "\.jka[[:space:]]"; then
                cecho -c yellow "Stopping server..."
                screen -S jka -X stuff "quit^M"
                sleep 2
                screen -S jka -X quit 2>/dev/null
                cleanup_copied_files
                cecho -c green "Server stopped."
                sleep 2
                show_server_info
            else
                cecho -c red "No server is running."
            fi
            exit 0
            ;;

        *)
            return 1
            ;;
    esac
}

run_first_time_setup() {
    local deps_installed_flag="$SCRIPT_DIR/.autors/.dependencies_installed"

    if [ -f "$deps_installed_flag" ]; then
        return 0
    fi

    cecho -c cyan "FIRST-TIME SETUP DETECTED"
    cecho "This will install dependencies for running JKA servers:"
    cecho " - Git, Screen, i386 libraries"

    if has_windows_servers; then
        cecho " - Wine (for Windows server binaries)"
    fi

    cecho " - JKA asset files (assets0-3.pk3)"
    cecho " - Crontab entries (@reboot and daily 4am reboot)"
    cecho " - 'svr' command symlink"

    read -p "Do you want to proceed with installation? (Y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]] && [[ -n $REPLY ]]; then
        cecho -c yellow "Installation cancelled by user"
        exit 0
    fi

    check_sudo

    local failed=false

    install_system_packages || failed=true

    if [ "$failed" = false ] && has_windows_servers; then
        install_wine || failed=true
    fi

    [ "$failed" = false ] && install_asset_files || failed=true
    [ "$failed" = false ] && setup_sudo_permissions || failed=true
    [ "$failed" = false ] && setup_crontab || failed=true
    [ "$failed" = false ] && setup_symlink || failed=true

    if [ "$failed" = true ]; then
        cecho -c red "SETUP FAILED"
        cecho -c red "Please fix the errors above and re-run with sudo"
        exit 1
    fi

    touch "$deps_installed_flag"

    cecho -c "  "
    cecho -c green "SETUP COMPLETED SUCCESSFULLY"
    cecho -c "  "
    cecho -c cyan " > To get started, run: svr"
    cecho -c cyan " > If you cannot run 'svr', first run: source ~/.bashrc"
    echo " "
    exit 0
}