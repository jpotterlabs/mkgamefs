#!/usr/bin/env bash
# lib/launcher.sh - Launcher script generation

# Generate actions.sh helper script
generate_actions_script() {
    local output_file=$1
    local -n g_info=$2
    local -n r_info=$3
    
    log_step "Generating actions.sh..."
    
    cat > "$output_file" << 'ACTIONS_EOF'
#!/usr/bin/env bash
# actions.sh - Helper functions for game management

# Ensure bash was used
if [ -z "${BASH_VERSION-}" ] || shopt -qo posix; then
    printf '%s\n' "this script only works with bash" >&2
    exit 1
fi

# Ensure script is not run as root
[ "$EUID" -eq 0 ] && { echo "this script should not be run as root"; exit 1; }

# Define runtime dependencies
declare -A DEPENDENCIES=(
    ['dwarfs']='dwarfs'
    ['fuse-overlayfs']='fuse-overlayfs'
    ['fuser']='fuser'
)

for dep_bin in "${!DEPENDENCIES[@]}"; do
    if ! command -v "$dep_bin" &> /dev/null; then
        echo "error: ${DEPENDENCIES[$dep_bin]} is not installed or not executable"
        exit 1
    fi
done

GAME_ROOT="$PWD/files/game-root"

# Mount DwarFS with overlay filesystem
dwarfs-mount() {
    dwarfs-unmount &> /dev/null
    
    HWRAMTOTAL="$(grep MemTotal /proc/meminfo | awk '{print $2}')"
    CACHEONRAM=$((HWRAMTOTAL * 25 / 100))
    
    CORUID="$(id -u $USER)"
    CORGID="$(id -g $USER)"
    
    [ -d "$GAME_ROOT" ] && [ "$(ls -A "$GAME_ROOT")" ] && echo "game is mounted or extracted." && return 0
    
    mkdir -p "$PWD/files/.game-root-mnt" "$PWD/files/overlay-storage" "$PWD/files/.game-root-work" "$GAME_ROOT" || {
        return 1
    }
    
    dwarfs "$PWD/files/game-root.dwarfs" "$PWD/files/.game-root-mnt" \
        -o tidy_strategy=time -o tidy_interval=15m -o tidy_max_age=30m \
        -o cachesize="${CACHEONRAM}k" -o clone_fd && \
        fuse-overlayfs -o squash_to_uid="$CORUID" \
                        -o squash_to_gid="$CORGID" \
                        -o lowerdir="$PWD/files/.game-root-mnt",upperdir="$PWD/files/overlay-storage",workdir="$PWD/files/.game-root-work" \
                        "$GAME_ROOT" && \
    echo "game mounted successfully. extraction not required."
}

# Unmount DwarFS
dwarfs-unmount() {
    fuser -k "$PWD/files/.game-root-mnt" 2>/dev/null
    
    local UMOUNT_DIRS=("$GAME_ROOT" "$PWD/files/.game-root-mnt")
    for dir in "${UMOUNT_DIRS[@]}"; do
        fusermount3 -u -z "$dir" 2>/dev/null
    done
    
    echo "game unmounted."
    
    rm -rf "$PWD/files/.game-root-mnt" "$PWD/files/.game-root-work"
    [ -d "$GAME_ROOT" ] && [ -z "$(ls -A "$GAME_ROOT")" ] && rm -rf "$GAME_ROOT"
}

# Extract DwarFS archive
dwarfs-extract() {
    if [ -d "$GAME_ROOT" ] && [ "$(ls -A "$GAME_ROOT")" ]; then
        echo "game is already mounted or extracted"
        return 0
    fi
    
    mkdir -p "$GAME_ROOT" || {
        return 1
    }
    
    dwarfsextract --stdout-progress -i "$PWD/files/game-root.dwarfs" -o "$GAME_ROOT" || {
        echo "error: failed to extract game files"
        return 1
    }
}

# Check DwarFS integrity
dwarfs-check_integrity() {
    dwarfsck --check-integrity -i "$PWD/files/game-root.dwarfs"
}

# Cleanup handler
jc141-cleanup() {
    cd "$OLDPWD" && dwarfs-unmount
}

# Initialize Wine prefix
wine-initiate_prefix() {
    wineboot -i
    find "$WINEPREFIX/drive_c/users/$USER" -maxdepth 1 -type l -exec test -d {} \; -exec rm {} \; -exec mkdir {} \;
    wineserver -w
}

# Setup Vulkan components
wine-setup_external_vulkan() {
    if [ -f "$PWD/files/vulkan.tar.xz" ]; then
        echo "Installing Vulkan components..."
        local temp_dir=$(mktemp -d)
        tar -xJf "$PWD/files/vulkan.tar.xz" -C "$temp_dir" || {
            echo "error: failed to extract Vulkan components"
            rm -rf "$temp_dir"
            return 1
        }
        
        # Copy DXVK DLLs
        if [ -d "$temp_dir/vulkan/dxvk" ]; then
            for dll in "$temp_dir/vulkan/dxvk"/*.dll; do
                [ -f "$dll" ] && cp "$dll" "$WINEPREFIX/drive_c/windows/system32/"
            done
            echo "  DXVK installed"
        fi
        
        # Copy VKD3D DLLs
        if [ -d "$temp_dir/vulkan/vkd3d" ]; then
            for dll in "$temp_dir/vulkan/vkd3d"/*.dll; do
                [ -f "$dll" ] && cp "$dll" "$WINEPREFIX/drive_c/windows/system32/"
            done
            echo "  VKD3D-Proton installed"
        fi
        
        rm -rf "$temp_dir"
        echo "vulkan installed" > "$WINEPREFIX/vulkan.log"
        return 0
    else
        echo "Vulkan components not bundled, assuming system installation"
        return 0
    fi
}

# Bubblewrap sandboxing
bwrap-run_in_sandbox() {
    [ -z "${XDG_RUNTIME_DIR}" ] && export XDG_RUNTIME_DIR="/run/user/${EUID}"
    BWRAP_FLAGS=(--ro-bind / / --dev-bind-try /dev /dev --bind-try /tmp /tmp)
    
    [ "$ISOLATION_TYPE" = 'wine' ] && BWRAP_FLAGS+=( --bind "$WINEPREFIX" "$WINEPREFIX" )
    [ "$ISOLATION_TYPE" = 'native' ] && BWRAP_FLAGS+=( --bind-try "$JC_DIRECTORY/native-docs" ~/ ) && [ ! -e "$JC_DIRECTORY/native-docs/.Xauthority" ] && ln "$XAUTHORITY" "$JC_DIRECTORY/native-docs" && XAUTHORITY="$HOME/.Xauthority"
    
    [ $BLOCK_NET = 1 ] && BWRAP_FLAGS+=( --unshare-net )
    
    # current dir as last setting
    BWRAP_FLAGS+=( --bind "$PWD" "$PWD" )
    
    bwrap "${BWRAP_FLAGS[@]}" "$@"
}

# Gamescope compositor
gamescope-run_embedded() {
    GAMESCOPE_BIN="$(command -v gamescope)"
    [ $GAMESCOPE_FULLSCREEN -eq 1 ] && GAMESCOPE_ARGS+=(-f)
    [ $GAMESCOPE_BORDERLESS -eq 1 ] && GAMESCOPE_ARGS+=(-b)
    [ -n "$GAMESCOPE_SCREEN_WIDTH" ] && GAMESCOPE_ARGS+=(-W "$GAMESCOPE_SCREEN_WIDTH")
    [ -n "$GAMESCOPE_SCREEN_HEIGHT" ] && GAMESCOPE_ARGS+=(-H "$GAMESCOPE_SCREEN_HEIGHT")
    [ -n "$GAMESCOPE_GAME_WIDTH" ] && GAMESCOPE_ARGS+=(-w "$GAMESCOPE_GAME_WIDTH")
    [ -n "$GAMESCOPE_GAME_HEIGHT" ] && GAMESCOPE_ARGS+=(-h "$GAMESCOPE_GAME_HEIGHT")
    GAMESCOPE_ARGS+=($ADDITIONAL_FLAGS)
    
    "$GAMESCOPE_BIN" "${GAMESCOPE_ARGS[@]}" -- "$@"
}

# Help
help() {
    cat << 'EOF'

Usage: actions.sh [SUBCOMMAND]

  dwarfs-mount                   Mounts the DwarFS archive with overlay for changes
  dwarfs-unmount                 Unmounts the DwarFS archive and cleans up
  dwarfs-extract                 Extracts the DwarFS archive to normal directory
  dwarfs-check_integrity         Checks integrity of the .dwarfs file

EOF
}

# Generate config if not present
jc141-write_config() {
    cat <<- 'EOF' >> "$1"
# automatically unmounts game files after the process ends
UNMOUNT=1

# extract game files instead of mounting the dwarfs archive on launch
EXTRACT=0

# display terminal output
TERMINAL_OUTPUT=1

# wine executable path
SYSWINE="$(command -v wine)"

# bubblewrap

# force games into isolation sandbox
ISOLATE=1

# block network access to the game. Does not work if ISOLATE=0.
BLOCK_NET=1

# sandbox directory path for isolation
JC_DIRECTORY="$HOME/Games/jc141"

# gamescope
GAMESCOPE=0
GAMESCOPE_FULLSCREEN=1
GAMESCOPE_BORDERLESS=0

# output resolution
GAMESCOPE_SCREEN_WIDTH=
GAMESCOPE_SCREEN_HEIGHT=

# game resolution
GAMESCOPE_GAME_WIDTH=
GAMESCOPE_GAME_HEIGHT=

# additional flags
ADDITIONAL_FLAGS=""
EOF
}

# Generate global defaults
jc141-generate_global_defaults() {
    cat <<- 'EOF' > "$HOME/.jc141rc"
# Global jc141 configuration

EOF
    jc141-write_config "$HOME/.jc141rc"
}

# Generate local overrides
jc141-generate_local_overrides() {
    cat <<- 'EOF' > "$PWD/script_default_settings"
# Game-specific settings (overrides ~/.jc141rc)

EOF
    jc141-write_config "$PWD/script_default_settings"
    sed -i -e 's/^\([^#].*\)/#\1/g' "$PWD/script_default_settings"
}

# Load config files
[ ! -f "$HOME/.jc141rc" ] && jc141-generate_global_defaults
[ ! -f "$PWD/script_default_settings" ] && jc141-generate_local_overrides

source "$HOME/.jc141rc"
source "$PWD/script_default_settings"

# Run
(return 0 2> /dev/null) || {
    if type "$1" &> /dev/null; then
        "$1" "${@:2}"
    else
        help
    fi
}
ACTIONS_EOF
    
    chmod +x "$output_file"
    log_success "Generated actions.sh"
}

# Generate start.sh launcher
generate_start_script() {
    local output_file=$1
    local -n g_info=$2
    local -n r_info=$3
    
    log_step "Generating start.sh..."
    
    # Temporarily disable unbound variable check for array access
    set +u
    local game_type="${g_info[type]:-native}"
    local executable="${g_info[executable]:-start.sh}"
    local needs_wine="${r_info[needs_wine]:-false}"
    set -u
    
    cat > "$output_file" << 'START_EOF'
#!/usr/bin/env bash
# Main launcher script

cd "$(dirname "$(readlink -f "$0")")" || { echo "Failed to navigate to script directory"; exit 1; }

# Display support message
cat << EOF
mkgamefs Game Package
Support: https://github.com/mhx/dwarfs
EOF

# Source helper functions
source "$PWD/actions.sh"

if [ -z "$EXTRACT" ]; then
    echo "Config file issue detected. Delete ~/.jc141rc and run again."
    exit 1
fi

START_EOF
    
    # Add game-specific logic
    if [[ "$needs_wine" == "true" ]]; then
        cat >> "$output_file" << 'WINE_EOF'

# Windows game - Wine/Proton required
[ ! -d "$JC_DIRECTORY" ] && mkdir -p "$JC_DIRECTORY"
echo "Wine prefix location: $JC_DIRECTORY/wine-prefix"

# Setup Wine prefix
export WINEPREFIX="$JC_DIRECTORY/wine-prefix"
if [ ! -d "$WINEPREFIX" ]; then
    echo "Initializing Wine prefix..."
    wine-initiate_prefix
    wine-setup_external_vulkan
fi

# Wine environment
export WINEDEBUG=fixme-all
export WINE_LARGE_ADDRESS_AWARE=1
export WINEFSYNC=1
export WINEESYNC=1
export WINE_D3D_CONFIG="renderer=vulkan"
export DXVK_HUD=0
export DXVK_LOG_LEVEL=none
export WINEDLLOVERRIDES="winemenubuilder.exe=d;mscoree=d;mshtml=d"

WINE_EOF
    else
        cat >> "$output_file" << 'NATIVE_EOF'

# Native Linux game
[ ! -d "$JC_DIRECTORY/native-docs" ] && mkdir -p "$JC_DIRECTORY/native-docs"
echo "Isolated home: $JC_DIRECTORY/native-docs"

NATIVE_EOF
    fi
    
    cat >> "$output_file" << 'COMMON_EOF'

# Redirect terminal output if specified
[ $TERMINAL_OUTPUT = 0 ] && exec &> /dev/null

# Manage extraction/mounting
[ $EXTRACT = 0 ] && dwarfs-mount
[ $EXTRACT = 1 ] && dwarfs-extract

# Set cleanup trap
[ $UNMOUNT = 1 ] && trap jc141-cleanup EXIT INT SIGINT SIGTERM

# Define game root
GAMEROOT="$PWD/files/game-root"

COMMON_EOF
    
    # Add execution command
    if [[ "$needs_wine" == "true" ]]; then
        cat >> "$output_file" << EXEC_WINE_EOF

# Launch command (Wine)
CMD=(wine "./${executable:-game.exe}" "\$@")
EXEC_WINE_EOF
    else
        cat >> "$output_file" << EXEC_NATIVE_EOF

# Launch command (Native)
CMD=("./${executable:-start.sh}" "\$@")
EXEC_NATIVE_EOF
    fi
    
    cat >> "$output_file" << 'LAUNCH_EOF'

# Prepare runtime
declare -a RUN

# Gamescope support
if command -v gamescope &>/dev/null && [ "$GAMESCOPE" == "1" ]; then
    RUN+=( gamescope-run_embedded )
fi

# Sandboxing support
if command -v bwrap &>/dev/null && [ "$ISOLATE" == "1" ]; then
    export ISOLATION_TYPE='wine'
    [ "$NEEDS_WINE" != "true" ] && export ISOLATION_TYPE='native'
    RUN+=( bash 'actions.sh' bwrap-run_in_sandbox --chdir "$GAMEROOT" )
else
    cd "$GAMEROOT" || { echo "Failed to navigate to game root"; exit 1; }
fi

# Execute
RUN+=( "${CMD[@]}" )
"${RUN[@]}"
LAUNCH_EOF
    
    chmod +x "$output_file"
    log_success "Generated start.sh"
}

# Generate configuration file
generate_config_file() {
    local output_file=$1
    
    log_step "Generating script_default_settings..."
    
    cat > "$output_file" << 'CONFIG_EOF'
# Game-specific settings (overrides ~/.jc141rc)
# Uncomment lines to enable

# automatically unmounts game files after the process ends
#UNMOUNT=1

# extract game files instead of mounting the dwarfs archive on launch
#EXTRACT=0

# display terminal output
#TERMINAL_OUTPUT=1

# wine executable path
#SYSWINE="$(command -v wine)"

# bubblewrap

# force games into isolation sandbox
#ISOLATE=1

# block network access to the game. Does not work if ISOLATE=0.
#BLOCK_NET=1

# sandbox directory path for isolation
#JC_DIRECTORY="$HOME/Games/jc141"

# gamescope
#GAMESCOPE=0
#GAMESCOPE_FULLSCREEN=1
#GAMESCOPE_BORDERLESS=0

# output resolution
#GAMESCOPE_SCREEN_WIDTH=
#GAMESCOPE_SCREEN_HEIGHT=

# game resolution
#GAMESCOPE_GAME_WIDTH=
#GAMESCOPE_GAME_HEIGHT=

# additional flags
#ADDITIONAL_FLAGS=""
CONFIG_EOF
    
    log_success "Generated script_default_settings"
}

# Generate all launcher files
generate_launcher_files() {
    local package_dir=$1
    local -n g_info=$2
    local -n r_info=$3
    
    print_header "Generating Launcher Scripts"
    
    generate_actions_script "$package_dir/actions.sh" g_info r_info
    generate_start_script "$package_dir/start.sh" g_info r_info
    generate_config_file "$package_dir/script_default_settings"
    
    log_success "All launcher files generated"
}

# Export functions
export -f generate_actions_script generate_start_script generate_config_file
export -f generate_launcher_files
