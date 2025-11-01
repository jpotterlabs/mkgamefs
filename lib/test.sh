#!/usr/bin/env bash
# lib/test.sh - Testing and validation

# Test package integrity
test_package_integrity() {
    local package_dir=$1
    local dwarfs_file="$package_dir/files/game-root.dwarfs"
    
    print_header "Testing Package Integrity"
    
    if [[ ! -f "$dwarfs_file" ]]; then
        log_error "DwarFS archive not found: $dwarfs_file"
        return 1
    fi
    
    check_dwarfs_integrity "$dwarfs_file" || return 1
    
    log_success "Package integrity test passed"
    return 0
}

# Test mount and unmount
test_mount_unmount() {
    local package_dir=$1
    local dwarfs_file="$package_dir/files/game-root.dwarfs"
    
    print_header "Testing Mount/Unmount"
    
    if [[ ! -f "$dwarfs_file" ]]; then
        log_error "DwarFS archive not found"
        return 1
    fi
    
    local test_mount=$(mktemp -d)
    
    log_step "Testing mount..."
    if dwarfs "$dwarfs_file" "$test_mount" -o ro; then
        log_success "Mount successful"
        
        # Check if files are accessible
        if [[ -n "$(ls -A "$test_mount" 2>/dev/null)" ]]; then
            log_success "Files accessible"
        else
            log_error "Mount appears empty"
            fusermount3 -u "$test_mount" 2>/dev/null
            rmdir "$test_mount"
            return 1
        fi
        
        # Test unmount
        log_step "Testing unmount..."
        if fusermount3 -u "$test_mount"; then
            log_success "Unmount successful"
            rmdir "$test_mount"
            return 0
        else
            log_error "Unmount failed"
            rmdir "$test_mount"
            return 1
        fi
    else
        log_error "Mount failed"
        rmdir "$test_mount"
        return 1
    fi
}

# Test dependencies
test_dependencies() {
    print_header "Testing Dependencies"
    
    check_dependencies || return 1
    check_optional_dependencies
    
    return 0
}

# Test launcher scripts
test_launcher_scripts() {
    local package_dir=$1
    
    print_header "Testing Launcher Scripts"
    
    # Check for required scripts
    local required_scripts=("actions.sh" "start.sh" "script_default_settings")
    local missing=()
    
    for script in "${required_scripts[@]}"; do
        if [[ ! -f "$package_dir/$script" ]]; then
            missing+=("$script")
            log_error "Missing: $script"
        else
            log_success "Found: $script"
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing ${#missing[@]} required file(s)"
        return 1
    fi
    
    # Check if scripts are executable
    if [[ -x "$package_dir/actions.sh" ]]; then
        log_success "actions.sh is executable"
    else
        log_warn "actions.sh is not executable"
    fi
    
    if [[ -x "$package_dir/start.sh" ]]; then
        log_success "start.sh is executable"
    else
        log_warn "start.sh is not executable"
    fi
    
    log_success "Launcher scripts test passed"
    return 0
}

# Run full test suite
run_full_test_suite() {
    local package_dir=$1
    local failed=0
    
    print_header "🧪 Running Full Test Suite"
    echo
    
    # Test 1: Dependencies
    if ! test_dependencies; then
        ((failed++))
    fi
    echo
    
    # Test 2: Package Integrity
    if ! test_package_integrity "$package_dir"; then
        ((failed++))
    fi
    echo
    
    # Test 3: Mount/Unmount
    if ! test_mount_unmount "$package_dir"; then
        ((failed++))
    fi
    echo
    
    # Test 4: Launcher Scripts
    if ! test_launcher_scripts "$package_dir"; then
        ((failed++))
    fi
    echo
    
    # Summary
    print_separator
    if [[ $failed -eq 0 ]]; then
        log_success "All tests passed! ✓"
        return 0
    else
        log_error "$failed test(s) failed"
        return 1
    fi
}

# Export functions
export -f test_package_integrity test_mount_unmount test_dependencies
export -f test_launcher_scripts run_full_test_suite
