#!/usr/bin/env bash
# lib/detect.sh - Game detection and analysis

# Detect game platform (Windows or Native Linux)
detect_game_type() {
    local game_dir=$1
    local exe_count dll_count so_count root_exe_count root_dll_count
    
    # Check root directory first (most reliable)
    root_exe_count=$(find "$game_dir" -maxdepth 1 -type f -iname "*.exe" 2>/dev/null | wc -l)
    root_dll_count=$(find "$game_dir" -maxdepth 1 -type f -iname "*.dll" 2>/dev/null | wc -l)
    
    # Check all files
    exe_count=$(find "$game_dir" -maxdepth 2 -type f -iname "*.exe" 2>/dev/null | wc -l)
    dll_count=$(find "$game_dir" -maxdepth 2 -type f -iname "*.dll" 2>/dev/null | wc -l)
    so_count=$(find "$game_dir" -maxdepth 2 -type f -iname "*.so*" 2>/dev/null | wc -l)
    
    # Strong Windows indicators: exe files in root or many root DLLs
    if [[ $root_exe_count -gt 0 ]] || [[ $root_dll_count -gt 10 ]]; then
        echo "windows"
        return 0
    fi
    
    # Strong Linux indicator: .so files present
    if [[ $so_count -gt 0 ]]; then
        echo "native"
        return 0
    fi
    
    # Weak Windows indicator: many DLLs but in subdirs (could be bundled crash reporters)
    if [[ $dll_count -gt 50 ]] && [[ $exe_count -gt 5 ]]; then
        echo "windows"
        return 0
    fi
    
    # Look for executable files without extensions
    local exec_count=0
    while IFS= read -r -d '' file; do
        if [[ -x "$file" ]] && [[ ! -d "$file" ]]; then
            ((exec_count++))
        fi
    done < <(find "$game_dir" -maxdepth 2 -type f ! -name "*.sh" ! -name "*.txt" ! -name "*.md" -print0 2>/dev/null)
    
    if [[ $exec_count -gt 0 ]]; then
        echo "native"
        return 0
    fi
    
    echo "unknown"
}

# Detect game engine
detect_game_engine() {
    local game_dir=$1
    
    # Unity engine detection
    if [[ -d "$game_dir/MonoBleedingEdge" ]] || 
       [[ -f "$game_dir/UnityPlayer.dll" ]] ||
       [[ -d "$game_dir"/*_Data ]] ||
       find "$game_dir" -type f -name "UnityPlayer.so" 2>/dev/null | grep -q .; then
        echo "unity"
        return 0
    fi
    
    # Unreal Engine detection
    if [[ -d "$game_dir/Engine/Binaries" ]] ||
       [[ -d "$game_dir/Engine/Content" ]] ||
       find "$game_dir" -type f -name "*.pak" 2>/dev/null | grep -q .; then
        echo "unreal"
        return 0
    fi
    
    # Godot engine detection
    if find "$game_dir" -type f -name "*.pck" 2>/dev/null | grep -q .; then
        echo "godot"
        return 0
    fi
    
    # Source engine detection
    if [[ -d "$game_dir/bin" ]] && find "$game_dir" -type f -name "*.vpk" 2>/dev/null | grep -q .; then
        echo "source"
        return 0
    fi
    
    # GameMaker detection
    if find "$game_dir" -type f -name "data.win" -o -name "game.droid" 2>/dev/null | grep -q .; then
        echo "gamemaker"
        return 0
    fi
    
    # RPG Maker detection
    if [[ -f "$game_dir/Game.exe" ]] && [[ -d "$game_dir/www" ]]; then
        echo "rpgmaker"
        return 0
    fi
    
    echo "unknown"
}

# Find the main game executable
find_main_executable() {
    local game_dir=$1
    local game_type=$2
    local candidates=()
    
    if [[ "$game_type" == "windows" ]]; then
        # Look for .exe files in the root directory first, excluding installers and tools
        while IFS= read -r -d '' exe; do
            local basename=$(basename "$exe")
            # Skip installers, crash handlers, and validation tools
            if [[ ! "$basename" =~ ^(unins|UnityCrashHandler|glslang|validator) ]]; then
                candidates+=("$exe")
            fi
        done < <(find "$game_dir" -maxdepth 1 -type f -iname "*.exe" -print0 2>/dev/null)
        
        # If no root .exe, look in subdirectories
        if [[ ${#candidates[@]} -eq 0 ]]; then
            while IFS= read -r -d '' exe; do
                candidates+=("$exe")
            done < <(find "$game_dir" -maxdepth 3 -type f -iname "*.exe" ! -iname "unins*.exe" ! -iname "UnityCrashHandler*.exe" -print0 2>/dev/null)
        fi
        
        # Return the largest .exe (usually the main game)
        if [[ ${#candidates[@]} -gt 0 ]]; then
            local largest=""
            local largest_size=0
            for exe in "${candidates[@]}"; do
                local size=$(stat -c%s "$exe" 2>/dev/null || echo 0)
                if [[ $size -gt $largest_size ]]; then
                    largest_size=$size
                    largest="$exe"
                fi
            done
            echo "${largest#$game_dir/}"
            return 0
        fi
    else
        # Native Linux game
        # Look for executable files, excluding common tool/test binaries
        while IFS= read -r -d '' file; do
            local basename=$(basename "$file")
            # Skip scripts and common validation tools
            if [[ -x "$file" ]] && 
               [[ ! "$file" =~ \.(sh|py|pl)$ ]] && 
               [[ ! "$basename" =~ ^(glslang|test|validator|crash_reporter|pdx.*test) ]]; then
                candidates+=("$file")
            fi
        done < <(find "$game_dir" -maxdepth 2 -type f -print0 2>/dev/null)
        
        # Return the largest executable
        if [[ ${#candidates[@]} -gt 0 ]]; then
            local largest=""
            local largest_size=0
            for file in "${candidates[@]}"; do
                local size=$(stat -c%s "$file" 2>/dev/null || echo 0)
                if [[ $size -gt $largest_size ]]; then
                    largest_size=$size
                    largest="$file"
                fi
            done
            echo "${largest#$game_dir/}"
            return 0
        fi
        
        # Look for .sh scripts as fallback
        local script=$(find "$game_dir" -maxdepth 1 -type f -name "start*.sh" -o -name "run*.sh" -o -name "launch*.sh" | head -n 1)
        if [[ -n "$script" ]]; then
            echo "${script#$game_dir/}"
            return 0
        fi
    fi
    
    echo ""
}

# Detect if game has existing Wine prefix
detect_wine_prefix() {
    local game_dir=$1
    
    if [[ -d "$game_dir/prefix" ]] || [[ -d "$game_dir/wine-prefix" ]] || [[ -d "$game_dir/.wine" ]]; then
        echo "true"
        return 0
    fi
    
    echo "false"
}

# Analyze game for additional metadata
analyze_game() {
    local game_dir=$1
    local -n result=$2
    
    log_step "Analyzing game directory..."
    
    # Detect game type
    result[type]=$(detect_game_type "$game_dir")
    log_detail "Platform: ${result[type]}"
    
    # Detect engine
    result[engine]=$(detect_game_engine "$game_dir")
    log_detail "Engine: ${result[engine]}"
    
    # Find executable
    result[executable]=$(find_main_executable "$game_dir" "${result[type]}")
    if [[ -n "${result[executable]}" ]]; then
        log_detail "Executable: ${result[executable]}"
    else
        log_warn "Could not find main executable"
    fi
    
    # Check for existing Wine prefix
    result[has_wine_prefix]=$(detect_wine_prefix "$game_dir")
    
    # Detect save game locations (common patterns)
    detect_save_locations "$game_dir" result
    
    # Count files and calculate size
    result[file_count]=$(find "$game_dir" -type f 2>/dev/null | wc -l)
    result[dir_size]=$(get_dir_size "$game_dir")
    
    log_detail "Files: ${result[file_count]}"
    log_detail "Size: $(human_size ${result[dir_size]})"
}

# Detect common save game locations
detect_save_locations() {
    local game_dir=$1
    local -n save_result=$2
    local save_dirs=()
    
    # Common save directories
    local patterns=(
        "*/Saves"
        "*/SaveGames"
        "*/save"
        "*/saves"
        "*/SaveData"
        "*/UserData"
    )
    
    for pattern in "${patterns[@]}"; do
        while IFS= read -r -d '' dir; do
            save_dirs+=("${dir#$game_dir/}")
        done < <(find "$game_dir" -type d -path "$pattern" -print0 2>/dev/null)
    done
    
    if [[ ${#save_dirs[@]} -gt 0 ]]; then
        save_result[save_locations]="${save_dirs[*]}"
        log_detail "Save locations: ${save_dirs[*]}"
    else
        save_result[save_locations]=""
    fi
}

# Recommend compression settings based on game type
recommend_compression() {
    local engine=$1
    local size=$2
    
    case "$engine" in
        unity|unreal)
            # These engines benefit from categorization
            echo "--categorize"
            ;;
        *)
            echo ""
            ;;
    esac
}

# Print detection summary
print_detection_summary() {
    local -n info=$1
    
    echo
    print_separator
    echo -e "${COLOR_BOLD}${COLOR_CYAN}Game Detection Summary${COLOR_RESET}"
    print_separator
    
    # Platform
    local type_color="${COLOR_GREEN}"
    [[ "${info[type]}" == "unknown" ]] && type_color="${COLOR_YELLOW}"
    echo -e "  ${COLOR_BOLD}Platform:${COLOR_RESET} ${type_color}${info[type]}${COLOR_RESET}"
    
    # Engine
    local engine_color="${COLOR_MAGENTA}"
    [[ "${info[engine]}" == "unknown" ]] && engine_color="${COLOR_DIM}"
    echo -e "  ${COLOR_BOLD}Engine:${COLOR_RESET} ${engine_color}${info[engine]}${COLOR_RESET}"
    
    # Executable
    if [[ -n "${info[executable]}" ]]; then
        echo -e "  ${COLOR_BOLD}Executable:${COLOR_RESET} ${info[executable]}"
    else
        echo -e "  ${COLOR_BOLD}Executable:${COLOR_RESET} ${COLOR_DIM}Not found${COLOR_RESET}"
    fi
    
    # Size
    echo -e "  ${COLOR_BOLD}Size:${COLOR_RESET} $(human_size ${info[dir_size]})"
    echo -e "  ${COLOR_BOLD}Files:${COLOR_RESET} ${info[file_count]}"
    
    # Save locations
    if [[ -n "${info[save_locations]}" ]]; then
        echo -e "  ${COLOR_BOLD}Save Dirs:${COLOR_RESET} ${info[save_locations]}"
    fi
    
    print_separator
    echo
}

# Export functions
export -f detect_game_type detect_game_engine find_main_executable
export -f detect_wine_prefix analyze_game detect_save_locations
export -f recommend_compression print_detection_summary
