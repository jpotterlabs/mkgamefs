#!/usr/bin/env bash
# lib/info.sh - Package information display

# Show package information
show_package_info() {
    local package_dir=$1
    local dwarfs_file="$package_dir/files/game-root.dwarfs"
    
    print_header "📦 Package Information"
    
    # Check if package exists
    if [[ ! -d "$package_dir" ]]; then
        log_error "Package directory not found: $package_dir"
        return 1
    fi
    
    if [[ ! -f "$dwarfs_file" ]]; then
        log_error "DwarFS archive not found: $dwarfs_file"
        return 1
    fi
    
    # Get DwarFS info
    log_step "Analyzing DwarFS archive..."
    local dwarfs_output
    dwarfs_output=$(dwarfsck -i "$dwarfs_file" 2>&1)
    
    echo
    print_separator
    echo -e "${COLOR_BOLD}${COLOR_CYAN}Archive Details${COLOR_RESET}"
    print_separator
    
    # Parse and display info
    if echo "$dwarfs_output" | grep -q "compressed size"; then
        local compressed
        compressed=$(echo "$dwarfs_output" | grep "compressed size" | sed 's/.*: //')
        echo -e "  ${COLOR_BOLD}Compressed Size:${COLOR_RESET} $compressed"
    fi
    
    if echo "$dwarfs_output" | grep -q "uncompressed size"; then
        local uncompressed
        uncompressed=$(echo "$dwarfs_output" | grep "uncompressed size" | sed 's/.*: //')
        echo -e "  ${COLOR_BOLD}Uncompressed Size:${COLOR_RESET} $uncompressed"
    fi
    
    if echo "$dwarfs_output" | grep -q "compression ratio"; then
        local ratio
        ratio=$(echo "$dwarfs_output" | grep "compression ratio" | sed 's/.*: //')
        echo -e "  ${COLOR_BOLD}Compression Ratio:${COLOR_RESET} $ratio"
    fi
    
    if echo "$dwarfs_output" | grep -q "inodes"; then
        local inodes
        inodes=$(echo "$dwarfs_output" | grep "inodes" | awk '{print $1}')
        echo -e "  ${COLOR_BOLD}Files/Directories:${COLOR_RESET} $inodes"
    fi
    
    if echo "$dwarfs_output" | grep -q "blocks"; then
        local blocks
        blocks=$(echo "$dwarfs_output" | grep "blocks" | awk '{print $1}')
        echo -e "  ${COLOR_BOLD}Blocks:${COLOR_RESET} $blocks"
    fi
    
    print_separator
    echo
    
    # Check for launcher scripts
    print_separator
    echo -e "${COLOR_BOLD}${COLOR_CYAN}Launcher Files${COLOR_RESET}"
    print_separator
    
    if [[ -f "$package_dir/actions.sh" ]]; then
        echo -e "  ${COLOR_GREEN}✓${COLOR_RESET} actions.sh"
    else
        echo -e "  ${COLOR_RED}✗${COLOR_RESET} actions.sh"
    fi
    
    if [[ -f "$package_dir/start.sh" ]]; then
        echo -e "  ${COLOR_GREEN}✓${COLOR_RESET} start.sh"
    else
        echo -e "  ${COLOR_RED}✗${COLOR_RESET} start.sh"
    fi
    
    if [[ -f "$package_dir/script_default_settings" ]]; then
        echo -e "  ${COLOR_GREEN}✓${COLOR_RESET} script_default_settings"
    else
        echo -e "  ${COLOR_RED}✗${COLOR_RESET} script_default_settings"
    fi
    
    print_separator
    echo
    
    # Check for Vulkan components
    if [[ -f "$package_dir/files/vulkan.tar.xz" ]]; then
        print_separator
        echo -e "${COLOR_BOLD}${COLOR_CYAN}Bundled Components${COLOR_RESET}"
        print_separator
        echo -e "  ${COLOR_GREEN}✓${COLOR_RESET} Vulkan components (vulkan.tar.xz)"
        print_separator
        echo
    fi
    
    return 0
}

# Export functions
export -f show_package_info