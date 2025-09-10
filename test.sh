#!/bin/bash

# OpenNetProbe (ONP) Test Script
# Tests the ONP installation and functionality

set -euo pipefail

# Override exit behavior for network tests
# Continue testing even if network tests fail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test configuration
TEST_TARGETS=("google.com" "cloudflare.com")

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "ERROR")
            echo -e "${RED}[$timestamp] [$level] $message${NC}"
            ;;
        "WARN")
            echo -e "${YELLOW}[$timestamp] [$level] $message${NC}"
            ;;
        "INFO")
            echo -e "${BLUE}[$timestamp] [$level] $message${NC}"
            ;;
        "SUCCESS")
            echo -e "${GREEN}[$timestamp] [$level] $message${NC}"
            ;;
        *)
            echo "[$timestamp] [$level] $message"
            ;;
    esac
}

# Test dependencies
test_dependencies() {
    log "INFO" "Testing dependencies..."
    
    local missing_tools=()
    for tool in ping traceroute curl jq bc; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        log "ERROR" "Missing tools: ${missing_tools[*]}"
        return 1
    fi
    
    log "SUCCESS" "All dependencies available"
    return 0
}

# Test script syntax
test_syntax() {
    log "INFO" "Testing script syntax..."
    
    if bash -n ./onp.sh; then
        log "SUCCESS" "Script syntax is valid"
        return 0
    else
        log "ERROR" "Script syntax errors found"
        return 1
    fi
}

# Test configuration loading
test_config() {
    log "INFO" "Testing configuration loading..."
    
    if [ -f "./onp.conf" ]; then
        log "SUCCESS" "Configuration file exists"
        
        # Test sourcing the config
        if source ./onp.conf 2>/dev/null; then
            log "SUCCESS" "Configuration file is valid"
            return 0
        else
            log "ERROR" "Configuration file has syntax errors"
            return 1
        fi
    else
        log "ERROR" "Configuration file not found"
        return 1
    fi
}

# Test individual functions
test_ping() {
    local target="$1"
    log "INFO" "Testing ping to $target..."
    
    # Use a subshell to prevent exit on failure
    if (ping -c 1 -W 5 "$target" &> /dev/null); then
        log "SUCCESS" "Ping to $target successful"
        return 0
    else
        log "WARN" "Ping to $target failed (this may be expected)"
        return 1
    fi
}

test_http() {
    local target="$1"
    log "INFO" "Testing HTTP to $target..."
    
    # Use a subshell to prevent exit on failure
    if (curl -s -m 10 -o /dev/null "https://$target"); then
        log "SUCCESS" "HTTP to $target successful"
        return 0
    else
        log "WARN" "HTTP to $target failed (this may be expected)"
        return 1
    fi
}

# Test systemd files
test_systemd() {
    log "INFO" "Testing systemd files..."
    
    if [ -f "./onp.service" ] && [ -f "./onp.timer" ]; then
        log "SUCCESS" "Systemd files exist"
        
        # Test service file syntax
        if (systemd-analyze verify ./onp.service &> /dev/null); then
            log "SUCCESS" "Service file syntax is valid"
        else
            log "WARN" "Service file syntax issues (may need systemd context)"
        fi
        
        # Test timer file syntax
        if (systemd-analyze verify ./onp.timer &> /dev/null); then
            log "SUCCESS" "Timer file syntax is valid"
        else
            log "WARN" "Timer file syntax issues (may need systemd context)"
        fi
        
        return 0
    else
        log "ERROR" "Systemd files missing"
        return 1
    fi
}

# Main test function
main() {
    echo "OpenNetProbe (ONP) Test Suite"
    echo "============================="
    echo
    
    # Enable verbose output if DEBUG is set
    if [ "${DEBUG:-}" = "1" ]; then
        set -x
    fi
    
    local tests_passed=0
    local tests_total=0
    
    # Test dependencies
    ((tests_total++))
    log "INFO" "Starting dependency test..."
    if test_dependencies; then
        ((tests_passed++))
        log "SUCCESS" "Dependency test passed"
    else
        log "ERROR" "Dependency test failed"
    fi
    echo
    
    # Test script syntax
    ((tests_total++))
    log "INFO" "Starting syntax test..."
    if test_syntax; then
        ((tests_passed++))
        log "SUCCESS" "Syntax test passed"
    else
        log "ERROR" "Syntax test failed"
    fi
    echo
    
    # Test configuration
    ((tests_total++))
    log "INFO" "Starting configuration test..."
    if test_config; then
        ((tests_passed++))
        log "SUCCESS" "Configuration test passed"
    else
        log "ERROR" "Configuration test failed"
    fi
    echo
    
    # Test systemd files
    ((tests_total++))
    log "INFO" "Starting systemd test..."
    if test_systemd; then
        ((tests_passed++))
        log "SUCCESS" "Systemd test passed"
    else
        log "ERROR" "Systemd test failed"
    fi
    echo
    
    # Test network connectivity
    log "INFO" "Starting network connectivity tests..."
    for target in "${TEST_TARGETS[@]}"; do
        ((tests_total++))
        log "INFO" "Testing ping connectivity to $target..."
        if test_ping "$target"; then
            ((tests_passed++))
            log "SUCCESS" "Ping test to $target passed"
        else
            log "WARN" "Ping test to $target failed (may be expected in CI)"
        fi
        echo
        
        ((tests_total++))
        log "INFO" "Testing HTTP connectivity to $target..."
        if test_http "$target"; then
            ((tests_passed++))
            log "SUCCESS" "HTTP test to $target passed"
        else
            log "WARN" "HTTP test to $target failed (may be expected in CI)"
        fi
        echo
    done
    
    # Summary
    echo "Test Results Summary"
    echo "==================="
    echo "Tests passed: $tests_passed/$tests_total"
    
    if [ $tests_passed -eq $tests_total ]; then
        log "SUCCESS" "All tests passed! OpenNetProbe (ONP) is ready to use."
        echo
        echo "Next steps:"
        echo "1. Run: sudo ./install.sh"
        echo "2. Edit: sudo nano /opt/onp/onp.conf"
        echo "3. Start: sudo systemctl start onp.timer"
        exit 0
    else
        log "ERROR" "Some tests failed. Please fix issues before installation."
        exit 1
    fi
}

# Run main function
main "$@"
