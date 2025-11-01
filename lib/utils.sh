#!/usr/bin/env bash
# lib/utils.sh - Core utility functions for mkgamefs

# Color definitions
readonly COLOR_RESET='\033[0m'
readonly COLOR_RED='\033[0;31m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[0;33m'
readonly COLOR_MAGENTA='\033[0;35m'
readonly COLOR_CYAN='\033[0;36m'
readonly COLOR_BOLD='\033[1m'
readonly COLOR_DIM='\033[2m'

# Logging functions
log_info() {
    echo -e "${COLOR_CYAN}ℹ${COLOR_RESET} $*" >&2
}

log_success() {
    echo -e "${COLOR_GREEN}✓${COLOR_RESET} $*" >&2
}

log_warn() {
    echo -e "${COLOR_YELLOW}⚠${COLOR_RESET} $*" >&2
}

log_error() {
    echo -e "${COLOR_RED}✗${COLOR_RESET} $*" >&2
}

log_step() {
    echo -e "${COLOR_BOLD}${COLOR_MAGENTA}▶${COLOR_RESET} ${COLOR_BOLD}$*${COLOR_RESET}" >&2
}

log_detail() {
    echo -e "  ${COLOR_DIM}$*${COLOR_RESET}" >&2
}

# Separator lines
print_separator() {
    echo -e "${COLOR_DIM}────────────────────────────────────────────────────────${COLOR_RESET}" >&2
}

print_header() {
    echo >&2
    print_separator
    echo -e "${COLOR_BOLD}${COLOR_CYAN}$*${COLOR_RESET}" >&2
    print_separator
    echo >&2
}

# Error handling
die() {
    log_error "$*"
    exit 1
}

# Check if running as root
check_not_root() {
    if [[ "$EUID" -eq 0 ]]; then
        die "This script should not be run as root"
    fi
}

# Check command availability
command_exists() {
    command -v "$1" &> /dev/null
}

# Check required dependencies
check_dependencies() {
    local missing=()
    local required=(
        "mkdwarfs:dwarfs"
        "dwarfsextract:dwarfs"
        "dwarfsck:dwarfs"
        "fuse-overlayfs:fuse-overlayfs"
        "file:file"
        "fuser:psmisc"
    )
    
    log_step "Checking dependencies..."
    
    local dep
    local cmd
    local pkg
    for dep in "${required[@]}"; do
        cmd="${dep%%:*}"
        pkg="${dep##*:}"
        
        if ! command_exists "$cmd"; then
            missing+=("$pkg")
            log_error "Missing: $cmd (package: $pkg)"
        else
            log_detail "$cmd: $(command -v "$cmd")"
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo >&2
        log_error "Missing dependencies: ${missing[*]}"
        log_info "Install with: sudo apt install ${missing[*]}"
        return 1
    fi
    
    log_success "All required dependencies found"
    return 0
}

# Check optional dependencies
check_optional_dependencies() {
    local optional=(
        "wine:System Wine"
        "bwrap:Bubblewrap sandboxing"
        "gamescope:Gamescope compositor"
        "gum:Interactive prompts"
    )
    
    log_step "Checking optional dependencies..."
    
    local dep
    local cmd
    local desc
    for dep in "${optional[@]}"; do
        cmd="${dep%%:*}"
        desc="${dep##*:}"
        
        if command_exists "$cmd"; then
            log_success "$desc: $(command -v "$cmd")"
        else
            log_detail "$desc: Not found (optional)"
        fi
    done
}

# Get human-readable size
human_size() {
    local bytes=$1
    local units=("B" "KB" "MB" "GB" "TB")
    local unit=0
    local size=$bytes
    
    while (( size > 1024 && unit < 4 )); do
        size=$((size / 1024))
        ((unit++))
    done
    
    echo "${size} ${units[$unit]}"
}

# Calculate directory size
get_dir_size() {
    local dir=$1
    du -sb "$dir" 2>/dev/null | cut -f1
}

# Calculate compression ratio
calc_compression_ratio() {
    local original=$1
    local compressed=$2
    local ratio
    
    if [[ $original -eq 0 ]]; then
        echo "0.0"
        return
    fi
    
    ratio=$(awk "BEGIN {printf \"%.1f\", ($compressed / $original) * 100}")
    echo "$ratio"
}

# Calculate savings percentage
calc_savings() {
    local original=$1
    local compressed=$2
    local savings
    
    if [[ $original -eq 0 ]]; then
        echo "0.0"
        return
    fi
    
    savings=$(awk "BEGIN {printf \"%.1f\", 100 - (($compressed / $original) * 100)}")
    echo "$savings"
}

# Validate input directory
validate_input_dir() {
    local dir=$1
    
    if [[ ! -d "$dir" ]]; then
        log_error "Input directory does not exist: $dir"
        return 1
    fi
    
    if [[ ! -r "$dir" ]]; then
        log_error "Input directory is not readable: $dir"
        return 1
    fi
    
    if [[ -z "$(ls -A "$dir" 2>/dev/null)" ]]; then
        log_error "Input directory is empty: $dir"
        return 1
    fi
    
    return 0
}

# Validate output path
validate_output_path() {
    local path=$1
    local force=$2
    local dir
    
    if [[ -e "$path" ]] && [[ "$force" != "true" ]]; then
        log_error "Output already exists: $path"
        log_info "Use --force to overwrite"
        return 1
    fi
    
    dir=$(dirname "$path")
    if [[ ! -d "$dir" ]]; then
        log_warn "Output directory does not exist, creating: $dir"
        mkdir -p "$dir" || {
            log_error "Failed to create output directory: $dir"
            return 1
        }
    fi
    
    if [[ ! -w "$dir" ]]; then
        log_error "Output directory is not writable: $dir"
        return 1
    fi
    
    return 0
}

# Get absolute path
get_absolute_path() {
    local path=$1
    
    if [[ -d "$path" ]]; then
        (cd "$path" && pwd)
    elif [[ -e "$path" ]]; then
        echo "$(cd "$(dirname "$path")" && pwd)/$(basename "$path")"
    else
        echo "$(cd "$(dirname "$path")" 2>/dev/null && pwd)/$(basename "$path")"
    fi
}

# Create temporary directory
create_temp_dir() {
    local prefix=${1:-mkgamefs}
    mktemp -d -t "${prefix}.XXXXXXXXXX"
}

# Cleanup function
cleanup_temp_dir() {
    local dir=$1
    if [[ -n "$dir" ]] && [[ -d "$dir" ]] && [[ "$dir" == /tmp/* ]]; then
        rm -rf "$dir"
        log_detail "Cleaned up temporary directory: $dir"
    fi
}

# Progress bar for long operations
show_progress() {
    local current=$1
    local total=$2
    local width=50
    local percent
    local filled
    local empty
    
    percent=$((current * 100 / total))
    filled=$((width * current / total))
    empty=$((width - filled))
    
    printf "\r%s" "${COLOR_CYAN}Progress:${COLOR_RESET} ["
    printf "%${filled}s" | tr ' ' '='
    printf "%${empty}s" | tr ' ' ' '
    printf "] %3d%%" "$percent"
}

# Detect system information
get_system_ram() {
    grep MemTotal /proc/meminfo | awk '{print $2}'
}

get_cache_size() {
    local ram_kb
    ram_kb=$(get_system_ram)
    echo $((ram_kb * 25 / 100))
}

get_user_uid() {
    id -u "$USER"
}

get_user_gid() {
    id -g "$USER"
}

# Export functions for use in subshells
export -f log_info log_success log_warn log_error log_step log_detail
export -f print_separator print_header die
export -f command_exists human_size get_dir_size
export -f calc_compression_ratio calc_savings