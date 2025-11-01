#!/usr/bin/env bash
# lib/compress.sh - DwarFS compression operations

# Compress game directory to DwarFS archive
compress_to_dwarfs() {
    local input_dir=$1
    local output_file=$2
    local -n options=$3
    
    log_step "Compressing to DwarFS archive..."
    
    # Build mkdwarfs command
    local cmd=(
        mkdwarfs
        -i "$input_dir"
        -o "$output_file"
        -l "${options[compression_level]:-7}"
        -B26  # 64 MiB block size
        -S26  # 64 MiB lookback window
        --no-history
        --order=nilsimsa
        --set-owner "$(get_user_uid)"
        --set-group "$(get_user_gid)"
        --set-time=now
        --chmod=Fa+rw,Da+rwx
    )
    
    # Add categorization if engine supports it
    if [[ "${options[categorize]:-false}" == "true" ]]; then
        cmd+=(--categorize)
        log_detail "Categorization enabled"
    fi
    
    # Add force flag if needed
    if [[ "${options[force]:-false}" == "true" ]]; then
        cmd+=(--force)
    fi
    
    # Run compression
    log_detail "Running: ${cmd[*]}"
    
    # Run mkdwarfs and capture output
    if "${cmd[@]}" 2>&1 | tee /tmp/mkdwarfs.log; then
        log_success "Compression completed"
        return 0
    else
        log_error "Compression failed"
        if [[ -f /tmp/mkdwarfs.log ]]; then
            log_detail "See /tmp/mkdwarfs.log for details"
        fi
        return 1
    fi
}

# Extract DwarFS archive
extract_from_dwarfs() {
    local input_file=$1
    local output_dir=$2
    
    log_step "Extracting DwarFS archive..."
    
    mkdir -p "$output_dir" || {
        log_error "Failed to create output directory"
        return 1
    }
    
    if dwarfsextract --stdout-progress -i "$input_file" -o "$output_dir"; then
        log_success "Extraction completed"
        return 0
    else
        log_error "Extraction failed"
        return 1
    fi
}

# Check DwarFS archive integrity
check_dwarfs_integrity() {
    local archive=$1
    
    log_step "Checking archive integrity..."
    
    if dwarfsck --check-integrity -i "$archive" 2>&1 | grep -q "OK"; then
        log_success "Archive integrity verified"
        return 0
    else
        log_error "Archive integrity check failed"
        return 1
    fi
}

# Get DwarFS archive info
get_dwarfs_info() {
    local archive=$1
    local -n info=$2
    local dwarfs_output
    
    dwarfs_output=$(dwarfsck -i "$archive" 2>&1)
    
    # Parse compression ratio
    if echo "$dwarfs_output" | grep -q "compressed size"; then
        info[compressed_size]=$(echo "$dwarfs_output" | grep "compressed size" | awk '{print $NF}' | tr -d '()')
    fi
    
    # Parse original size
    if echo "$dwarfs_output" | grep -q "uncompressed size"; then
        info[original_size]=$(echo "$dwarfs_output" | grep "uncompressed size" | awk '{print $NF}' | tr -d '()')
    fi
    
    # Parse block count
    if echo "$dwarfs_output" | grep -q "blocks"; then
        info[block_count]=$(echo "$dwarfs_output" | grep "blocks" | awk '{print $1}')
    fi
    
    # Parse inode count
    if echo "$dwarfs_output" | grep -q "inodes"; then
        info[inode_count]=$(echo "$dwarfs_output" | grep "inodes" | awk '{print $1}')
    fi
}

# Print compression summary
print_compression_summary() {
    local original_size=$1
    local compressed_size=$2
    local ratio
    local savings
    
    ratio=$(calc_compression_ratio "$original_size" "$compressed_size")
    savings=$(calc_savings "$original_size" "$compressed_size")
    
    echo
    print_separator
    echo -e "${COLOR_BOLD}${COLOR_GREEN}Compression Results${COLOR_RESET}"
    print_separator
    
    echo -e "  ${COLOR_BOLD}Original:${COLOR_RESET}    $(human_size "$original_size")"
    echo -e "  ${COLOR_BOLD}Compressed:${COLOR_RESET}  $(human_size "$compressed_size")"
    echo -e "  ${COLOR_BOLD}Ratio:${COLOR_RESET}       ${ratio}%"
    echo -e "  ${COLOR_BOLD}Savings:${COLOR_RESET}     ${COLOR_GREEN}${savings}%${COLOR_RESET}"
    
    print_separator
    echo
}

# Determine optimal compression settings
determine_compression_settings() {
    local engine=$1
    local size=$2
    local -n settings=$3
    
    # Default settings
    settings[compression_level]=7
    settings[categorize]="false"
    
    # Adjust based on engine
    case "$engine" in
        unity|unreal)
            settings[categorize]="true"
            log_detail "Engine-specific optimization enabled"
            ;;
        *)
            log_detail "Using default compression settings"
            ;;
    esac
    
    # Adjust based on size (optional: higher compression for smaller games)
    if [[ $size -lt $((1024 * 1024 * 1024)) ]]; then
        # Less than 1GB - can afford higher compression
        settings[compression_level]=9
        log_detail "Small game detected, using max compression"
    fi
}

# Export functions
export -f compress_to_dwarfs extract_from_dwarfs check_dwarfs_integrity
export -f get_dwarfs_info print_compression_summary determine_compression_settings