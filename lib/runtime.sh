#!/usr/bin/env bash
# lib/runtime.sh - Wine/Proton runtime configuration

# Detect system Wine installations
detect_wine() {
    local -n result=$1
    
    if command_exists wine; then
        result[has_wine]="true"
        result[wine_path]=$(command -v wine)
        result[wine_version]=$(wine --version 2>/dev/null | head -n1)
        log_detail "System Wine: ${result[wine_version]}"
        return 0
    fi
    
    result[has_wine]="false"
    log_detail "System Wine: Not found"
    return 1
}

# Detect Proton installations
detect_proton() {
    local -n result=$1
    local proton_dirs=(
        "$HOME/.steam/steam/steamapps/common/Proton"*
        "$HOME/.local/share/Steam/steamapps/common/Proton"*
        "/usr/share/steam/compatibilitytools.d/Proton"*
    )
    
    result[has_proton]="false"
    result[proton_versions]=""
    local versions=()
    
    for pattern in "${proton_dirs[@]}"; do
        for dir in $pattern; do
            if [[ -d "$dir" ]] && [[ -f "$dir/proton" ]]; then
                local version=$(basename "$dir")
                versions+=("$version:$dir")
                result[has_proton]="true"
            fi
        done
    done
    
    if [[ ${#versions[@]} -gt 0 ]]; then
        result[proton_versions]="${versions[*]}"
        log_detail "Found Proton: ${#versions[@]} version(s)"
        for ver in "${versions[@]}"; do
            log_detail "  - ${ver%%:*}"
        done
        return 0
    fi
    
    log_detail "Proton: Not found"
    return 1
}

# Get latest Proton version
get_latest_proton() {
    local -n versions=$1
    local latest=""
    local latest_path=""
    
    for ver_path in ${versions[proton_versions]}; do
        local ver="${ver_path%%:*}"
        local path="${ver_path##*:}"
        
        # Prefer GE versions, then Experimental, then numbered versions
        if [[ "$ver" =~ GE ]] && [[ -z "$latest" || ! "$latest" =~ GE ]]; then
            latest="$ver"
            latest_path="$path"
        elif [[ "$ver" =~ Experimental ]] && [[ -z "$latest" ]]; then
            latest="$ver"
            latest_path="$path"
        elif [[ -z "$latest" ]]; then
            latest="$ver"
            latest_path="$path"
        fi
    done
    
    echo "$latest_path"
}

# Detect Vulkan components (DXVK, VKD3D-Proton)
detect_vulkan_components() {
    local -n result=$1
    
    log_step "Checking Vulkan components..."
    
    # Check for DXVK in system
    result[has_dxvk]="false"
    if [[ -f /usr/lib/wine/x86_64-windows/dxgi.dll ]] || 
       [[ -f /usr/lib64/wine/dxgi.dll ]] ||
       [[ -f $HOME/.local/share/lutris/runtime/dxvk/*/x64/dxgi.dll ]]; then
        result[has_dxvk]="true"
        log_success "DXVK: Installed"
    else
        log_warn "DXVK: Not found (will download)"
    fi
    
    # Check for VKD3D-Proton
    result[has_vkd3d]="false"
    if [[ -f /usr/lib/wine/x86_64-windows/d3d12.dll ]] ||
       [[ -f /usr/lib64/wine/d3d12.dll ]] ||
       [[ -f $HOME/.local/share/lutris/runtime/vkd3d/*/x64/d3d12.dll ]]; then
        result[has_vkd3d]="true"
        log_success "VKD3D-Proton: Installed"
    else
        log_warn "VKD3D-Proton: Not found (will download)"
    fi
    
    # Check for Vulkan loader
    if command_exists vulkaninfo; then
        result[has_vulkan]="true"
        log_success "Vulkan: Available"
    else
        result[has_vulkan]="false"
        log_error "Vulkan: Not found (install vulkan-tools)"
    fi
}

# Download DXVK
download_dxvk() {
    local target_dir=$1
    local version="2.4"  # Latest stable as of Oct 2024
    local url="https://github.com/doitsujin/dxvk/releases/download/v${version}/dxvk-${version}.tar.gz"
    
    log_step "Downloading DXVK ${version}..."
    
    local temp_dir=$(create_temp_dir "dxvk")
    
    if curl -L -o "$temp_dir/dxvk.tar.gz" "$url" 2>/dev/null; then
        tar -xzf "$temp_dir/dxvk.tar.gz" -C "$temp_dir" || {
            log_error "Failed to extract DXVK"
            cleanup_temp_dir "$temp_dir"
            return 1
        }
        
        mkdir -p "$target_dir/dxvk"
        cp -r "$temp_dir"/dxvk-*/x64/* "$target_dir/dxvk/" || {
            log_error "Failed to copy DXVK files"
            cleanup_temp_dir "$temp_dir"
            return 1
        }
        
        log_success "DXVK downloaded"
        cleanup_temp_dir "$temp_dir"
        return 0
    else
        log_error "Failed to download DXVK"
        cleanup_temp_dir "$temp_dir"
        return 1
    fi
}

# Download VKD3D-Proton
download_vkd3d() {
    local target_dir=$1
    local version="2.13"  # Latest stable
    local url="https://github.com/HansKristian-Work/vkd3d-proton/releases/download/v${version}/vkd3d-proton-${version}.tar.zst"
    
    log_step "Downloading VKD3D-Proton ${version}..."
    
    if ! command_exists zstd; then
        log_error "zstd is required to extract VKD3D-Proton (install zstd package)"
        return 1
    fi
    
    local temp_dir=$(create_temp_dir "vkd3d")
    
    if curl -L -o "$temp_dir/vkd3d.tar.zst" "$url" 2>/dev/null; then
        zstd -d "$temp_dir/vkd3d.tar.zst" -o "$temp_dir/vkd3d.tar" || {
            log_error "Failed to decompress VKD3D-Proton"
            cleanup_temp_dir "$temp_dir"
            return 1
        }
        
        tar -xf "$temp_dir/vkd3d.tar" -C "$temp_dir" || {
            log_error "Failed to extract VKD3D-Proton"
            cleanup_temp_dir "$temp_dir"
            return 1
        }
        
        mkdir -p "$target_dir/vkd3d"
        cp -r "$temp_dir"/vkd3d-proton-*/x64/* "$target_dir/vkd3d/" || {
            log_error "Failed to copy VKD3D-Proton files"
            cleanup_temp_dir "$temp_dir"
            return 1
        }
        
        log_success "VKD3D-Proton downloaded"
        cleanup_temp_dir "$temp_dir"
        return 0
    else
        log_error "Failed to download VKD3D-Proton"
        cleanup_temp_dir "$temp_dir"
        return 1
    fi
}

# Create Vulkan components tarball for package
create_vulkan_tarball() {
    local components_dir=$1
    local output_file=$2
    
    log_step "Creating Vulkan components tarball..."
    
    if [[ ! -d "$components_dir" ]]; then
        log_error "Components directory not found: $components_dir"
        return 1
    fi
    
    tar -cJf "$output_file" -C "$(dirname "$components_dir")" "$(basename "$components_dir")" || {
        log_error "Failed to create tarball"
        return 1
    }
    
    log_success "Vulkan tarball created: $(basename "$output_file")"
    return 0
}

# Configure Wine environment variables
configure_wine_env() {
    local -n config=$1
    
    # Essential Wine settings
    config[WINEDEBUG]="fixme-all"
    config[WINE_LARGE_ADDRESS_AWARE]="1"
    config[WINEFSYNC]="1"
    config[WINEESYNC]="1"
    
    # Vulkan/D3D settings
    config[WINE_D3D_CONFIG]="renderer=vulkan"
    config[DXVK_HUD]="0"
    config[DXVK_LOG_LEVEL]="none"
    
    # Performance
    config[STAGING_SHARED_MEMORY]="1"
    config[__GL_SHADER_DISK_CACHE]="1"
    config[__GL_SHADER_DISK_CACHE_SKIP_CLEANUP]="1"
    
    # Disable Wine menu/browser
    config[WINEDLLOVERRIDES]="winemenubuilder.exe=d;mscoree=d;mshtml=d"
}

# Generate Wine prefix initialization script
generate_wine_prefix_init() {
    local output_file=$1
    
    cat > "$output_file" << 'EOF'
#!/usr/bin/env bash
# Wine prefix initialization

init_wine_prefix() {
    local prefix_dir=$1
    
    if [[ ! -d "$prefix_dir" ]]; then
        echo "Initializing Wine prefix: $prefix_dir"
        export WINEPREFIX="$prefix_dir"
        wineboot -i 2>/dev/null
        
        # Remove symbolic links to user directories (privacy)
        find "$WINEPREFIX/drive_c/users/$USER" -maxdepth 1 -type l -exec rm {} \; 2>/dev/null
        
        # Create real directories instead
        mkdir -p "$WINEPREFIX/drive_c/users/$USER/"{Documents,Desktop,Downloads}
        
        wineserver -w
        echo "Wine prefix initialized"
    else
        echo "Wine prefix already exists"
    fi
}

setup_vulkan_dlls() {
    local prefix_dir=$1
    local vulkan_dir=$2
    
    if [[ ! -d "$vulkan_dir" ]]; then
        echo "Vulkan components not found, skipping DLL setup"
        return 0
    fi
    
    echo "Installing Vulkan DLLs to Wine prefix..."
    
    # Copy DXVK DLLs
    if [[ -d "$vulkan_dir/dxvk" ]]; then
        for dll in "$vulkan_dir/dxvk"/*.dll; do
            [[ -f "$dll" ]] || continue
            cp "$dll" "$prefix_dir/drive_c/windows/system32/"
        done
        echo "  DXVK installed"
    fi
    
    # Copy VKD3D DLLs
    if [[ -d "$vulkan_dir/vkd3d" ]]; then
        for dll in "$vulkan_dir/vkd3d"/*.dll; do
            [[ -f "$dll" ]] || continue
            cp "$dll" "$prefix_dir/drive_c/windows/system32/"
        done
        echo "  VKD3D-Proton installed"
    fi
}

EOF
    
    chmod +x "$output_file"
}

# Determine runtime type for game
determine_runtime() {
    local game_type=$1
    local -n rt_info=$2
    
    if [[ "$game_type" == "native" ]]; then
        rt_info[runtime]="native"
        rt_info[needs_wine]="false"
        return 0
    fi
    
    # Windows game - determine Wine/Proton
    rt_info[needs_wine]="true"
    
    # Check for available runtimes
    detect_wine rt_info
    detect_proton rt_info
    
    # Prefer Proton if available, fallback to Wine
    if [[ "${rt_info[has_proton]}" == "true" ]]; then
        rt_info[runtime]="proton"
        rt_info[runtime_path]=$(get_latest_proton rt_info)
        log_success "Selected runtime: Proton (${rt_info[runtime_path]})"
    elif [[ "${rt_info[has_wine]}" == "true" ]]; then
        rt_info[runtime]="wine"
        rt_info[runtime_path]="${rt_info[wine_path]}"
        log_success "Selected runtime: System Wine"
    else
        rt_info[runtime]="none"
        log_error "No Wine or Proton found - Windows game cannot run"
        return 1
    fi
    
    return 0
}

# Print runtime summary
print_runtime_summary() {
    local -n info=$1
    
    echo
    print_separator
    echo -e "${COLOR_BOLD}${COLOR_CYAN}Runtime Configuration${COLOR_RESET}"
    print_separator
    
    if [[ "${info[needs_wine]}" == "true" ]]; then
        echo -e "  ${COLOR_BOLD}Type:${COLOR_RESET} Windows (requires Wine/Proton)"
        echo -e "  ${COLOR_BOLD}Runtime:${COLOR_RESET} ${info[runtime]}"
        
        if [[ -n "${info[runtime_path]}" ]]; then
            echo -e "  ${COLOR_BOLD}Path:${COLOR_RESET} ${info[runtime_path]}"
        fi
        
        # Vulkan status
        if [[ "${info[has_dxvk]}" == "true" ]]; then
            echo -e "  ${COLOR_BOLD}DXVK:${COLOR_RESET} ${COLOR_GREEN}Available${COLOR_RESET}"
        else
            echo -e "  ${COLOR_BOLD}DXVK:${COLOR_RESET} ${COLOR_YELLOW}Will download${COLOR_RESET}"
        fi
        
        if [[ "${info[has_vkd3d]}" == "true" ]]; then
            echo -e "  ${COLOR_BOLD}VKD3D:${COLOR_RESET} ${COLOR_GREEN}Available${COLOR_RESET}"
        else
            echo -e "  ${COLOR_BOLD}VKD3D:${COLOR_RESET} ${COLOR_YELLOW}Will download${COLOR_RESET}"
        fi
    else
        echo -e "  ${COLOR_BOLD}Type:${COLOR_RESET} Native Linux"
        echo -e "  ${COLOR_BOLD}Runtime:${COLOR_RESET} Direct execution"
    fi
    
    print_separator
    echo
}

# Export functions
export -f detect_wine detect_proton get_latest_proton
export -f detect_vulkan_components download_dxvk download_vkd3d
export -f create_vulkan_tarball configure_wine_env
export -f generate_wine_prefix_init determine_runtime
export -f print_runtime_summary
