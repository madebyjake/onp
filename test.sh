#!/bin/bash

# netnoise Test Script
# Tests the netnoise installation and functionality

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
TEST_TARGETS=("${TEST_TARGETS[@]:-google.com}" "cloudflare.com")

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
    
    # Check for at least one DNS tool
    local dns_tools_available=false
    if command -v dig &> /dev/null || command -v nslookup &> /dev/null; then
        dns_tools_available=true
    fi
    
    if [ "$dns_tools_available" = false ]; then
        missing_tools+=("dig or nslookup")
    fi
    
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
    
    if bash -n ./netnoise.sh; then
        log "SUCCESS" "Script syntax is valid"
    else
        log "ERROR" "Script syntax errors found"
        return 1
    fi
    
    # Test module syntax
    if [ -d "./modules" ]; then
        log "INFO" "Testing module syntax..."
        for module in modules/*.sh; do
            if [ -f "$module" ]; then
                if bash -n "$module"; then
                    log "SUCCESS" "Module $(basename "$module") syntax is valid"
                else
                    log "ERROR" "Module $(basename "$module") syntax errors found"
                    return 1
                fi
            fi
        done
    fi
    
    return 0
}

# Test configuration loading
test_config() {
    log "INFO" "Testing configuration loading..."
    
    if [ -f "./netnoise.conf" ]; then
        log "SUCCESS" "Configuration file exists"
        
        # Test sourcing the config
        if source ./netnoise.conf 2>/dev/null; then
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

test_dns() {
    local target="$1"
    log "INFO" "Testing DNS resolution for $target..."
    
    # Use a subshell to prevent exit on failure
    local dns_result=""
    if command -v dig &> /dev/null; then
        if dns_result=$(dig +short +time=5 +tries=1 "$target" A 2>/dev/null); then
            if [ -n "$dns_result" ] && [ "$dns_result" != "" ]; then
                log "SUCCESS" "DNS resolution for $target successful (dig: $dns_result)"
                return 0
            fi
        fi
    elif command -v nslookup &> /dev/null; then
        if dns_result=$(nslookup "$target" 2>/dev/null | grep -E 'Address: [0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | head -1); then
            if [ -n "$dns_result" ]; then
                log "SUCCESS" "DNS resolution for $target successful (nslookup: $dns_result)"
                return 0
            fi
        fi
    fi
    
    log "WARN" "DNS resolution for $target failed (this may be expected)"
    return 1
}

test_bandwidth() {
    local target="$1"
    log "INFO" "Testing bandwidth to $target..."
    
    # Use a subshell to prevent exit on failure
    local test_url="https://$target"
    local download_result=""
    local download_file="/tmp/test_bandwidth_$$"
    
    if command -v curl &> /dev/null; then
        if download_result=$(curl -s -w "\n%{speed_download}\n%{time_total}" -o "$download_file" --max-time 10 "$test_url" 2>/dev/null); then
            local speed_bytes=$(echo "$download_result" | tail -n 2 | head -n 1)
            if [[ "$speed_bytes" =~ ^[0-9]+$ ]] && [ "$speed_bytes" -gt 0 ]; then
                local speed_mbps=$(echo "scale=2; $speed_bytes * 8 / 1000000" | bc -l 2>/dev/null || echo "0")
                log "SUCCESS" "Bandwidth test to $target successful (${speed_mbps}Mbps)"
                rm -f "$download_file"
                return 0
            fi
        fi
    elif command -v wget &> /dev/null; then
        if wget -O "$download_file" --timeout=10 --tries=1 "$test_url" 2>/dev/null; then
            local file_size=$(stat -f%z "$download_file" 2>/dev/null || echo "0")
            if [ "$file_size" -gt 0 ]; then
                log "SUCCESS" "Bandwidth test to $target successful (file downloaded: ${file_size} bytes)"
                rm -f "$download_file"
                return 0
            fi
        fi
    fi
    
    rm -f "$download_file"
    log "WARN" "Bandwidth test to $target failed (this may be expected)"
    return 1
}

test_ports() {
    local target="$1"
    log "INFO" "Testing port connectivity to $target..."
    
    # Extract hostname from URL if needed
    local hostname="$target"
    if [[ "$target" =~ ^https?:// ]]; then
        hostname=$(echo "$target" | sed 's|^https\?://||' | cut -d'/' -f1)
    fi
    
    # Test a few common ports
    local test_ports=(22 80 443)
    local open_ports=()
    
    for port in "${test_ports[@]}"; do
        if command -v nc &> /dev/null; then
            if timeout 3 nc -z -w3 "$hostname" "$port" 2>/dev/null; then
                open_ports+=("$port")
                log "SUCCESS" "Port $port on $hostname is open"
            fi
        elif [ -c /dev/tcp ]; then
            if timeout 3 bash -c "exec 3<>/dev/tcp/$hostname/$port" 2>/dev/null; then
                open_ports+=("$port")
                log "SUCCESS" "Port $port on $hostname is open"
                exec 3<&- 2>/dev/null || true
            fi
        fi
    done
    
    if [ ${#open_ports[@]} -gt 0 ]; then
        log "SUCCESS" "Port test to $target successful (open ports: ${open_ports[*]})"
        return 0
    else
        log "WARN" "Port test to $target failed (no open ports found)"
        return 1
    fi
}

test_mtu() {
    local target="$1"
    log "INFO" "Testing MTU discovery to $target..."
    
    # Extract hostname from URL if needed
    local hostname="$target"
    if [[ "$target" =~ ^https?:// ]]; then
        hostname=$(echo "$target" | sed 's|^https\?://||' | cut -d'/' -f1)
    fi
    
    # Test with a simple MTU discovery (test 1500 and 576)
    local test_mtus=(1500 576)
    local found_mtu=0
    
    for mtu in "${test_mtus[@]}"; do
        local payload_size=$((mtu - 28))  # Subtract IP and ICMP headers
        
        # Test with ping Don't Fragment flag (detect OS)
        local ping_cmd="ping -c 1 -s $payload_size -W 3"
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS uses -D for Don't Fragment
            ping_cmd="$ping_cmd -D"
        else
            # Linux uses -M do for Don't Fragment
            ping_cmd="$ping_cmd -M do"
        fi
        
        if timeout 3 "$ping_cmd" "$hostname" &>/dev/null; then
            found_mtu=$mtu
            log "SUCCESS" "MTU $mtu bytes successful on $hostname"
            break
        fi
    done
    
    if [ "$found_mtu" -gt 0 ]; then
        log "SUCCESS" "MTU test to $target successful (found MTU: $found_mtu bytes)"
        return 0
    else
        log "WARN" "MTU test to $target failed (no valid MTU found)"
        return 1
    fi
}

# Test systemd files
test_systemd() {
    log "INFO" "Testing systemd files..."
    
    if [ -f "./netnoise.service" ] && [ -f "./netnoise.timer" ]; then
        log "SUCCESS" "Systemd files exist"
        
        # Test service file syntax
        if (systemd-analyze verify ./netnoise.service &> /dev/null); then
            log "SUCCESS" "Service file syntax is valid"
        else
            log "WARN" "Service file syntax issues (may need systemd context)"
        fi
        
        # Test timer file syntax
        if (systemd-analyze verify ./netnoise.timer &> /dev/null); then
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
    echo "NetNoise Test Suite"
    echo "============================="
    echo
    
    # Enable verbose output if DEBUG is set
    if [ "${DEBUG:-}" = "1" ]; then
        set -x
    fi
    
    tests_passed=0
    tests_total=0
    core_tests_passed=0
    core_tests_total=0
    network_tests_passed=0
    network_tests_total=0
    
    # Test dependencies
    tests_total=$((tests_total + 1))
    core_tests_total=$((core_tests_total + 1))
    log "INFO" "Starting dependency test..."
    if test_dependencies; then
        tests_passed=$((tests_passed + 1))
        core_tests_passed=$((core_tests_passed + 1))
        log "SUCCESS" "Dependency test passed"
    else
        log "ERROR" "Dependency test failed"
    fi
    echo
    
    # Test script syntax
    tests_total=$((tests_total + 1))
    core_tests_total=$((core_tests_total + 1))
    log "INFO" "Starting syntax test..."
    if test_syntax; then
        tests_passed=$((tests_passed + 1))
        core_tests_passed=$((core_tests_passed + 1))
        log "SUCCESS" "Syntax test passed"
    else
        log "ERROR" "Syntax test failed"
    fi
    echo
    
    # Test configuration
    tests_total=$((tests_total + 1))
    core_tests_total=$((core_tests_total + 1))
    log "INFO" "Starting configuration test..."
    if test_config; then
        tests_passed=$((tests_passed + 1))
        core_tests_passed=$((core_tests_passed + 1))
        log "SUCCESS" "Configuration test passed"
    else
        log "ERROR" "Configuration test failed"
    fi
    echo
    
    # Test systemd files
    tests_total=$((tests_total + 1))
    core_tests_total=$((core_tests_total + 1))
    log "INFO" "Starting systemd test..."
    if test_systemd; then
        tests_passed=$((tests_passed + 1))
        core_tests_passed=$((core_tests_passed + 1))
        log "SUCCESS" "Systemd test passed"
    else
        log "ERROR" "Systemd test failed"
    fi
    echo
    
    # Test network connectivity
    log "INFO" "Starting network connectivity tests..."
    for target in "${TEST_TARGETS[@]}"; do
        tests_total=$((tests_total + 1))
        network_tests_total=$((network_tests_total + 1))
        log "INFO" "Testing DNS resolution for $target..."
        if test_dns "$target"; then
            tests_passed=$((tests_passed + 1))
            network_tests_passed=$((network_tests_passed + 1))
            log "SUCCESS" "DNS test to $target passed"
        else
            log "WARN" "DNS test to $target failed (may be expected in CI)"
        fi
        echo
        
        tests_total=$((tests_total + 1))
        network_tests_total=$((network_tests_total + 1))
        log "INFO" "Testing ping connectivity to $target..."
        if test_ping "$target"; then
            tests_passed=$((tests_passed + 1))
            network_tests_passed=$((network_tests_passed + 1))
            log "SUCCESS" "Ping test to $target passed"
        else
            log "WARN" "Ping test to $target failed (may be expected in CI)"
        fi
        echo
        
        tests_total=$((tests_total + 1))
        network_tests_total=$((network_tests_total + 1))
        log "INFO" "Testing bandwidth to $target..."
        if test_bandwidth "$target"; then
            tests_passed=$((tests_passed + 1))
            network_tests_passed=$((network_tests_passed + 1))
            log "SUCCESS" "Bandwidth test to $target passed"
        else
            log "WARN" "Bandwidth test to $target failed (may be expected in CI)"
        fi
        echo
        
        tests_total=$((tests_total + 1))
        network_tests_total=$((network_tests_total + 1))
        log "INFO" "Testing port connectivity to $target..."
        if test_ports "$target"; then
            tests_passed=$((tests_passed + 1))
            network_tests_passed=$((network_tests_passed + 1))
            log "SUCCESS" "Port test to $target passed"
        else
            log "WARN" "Port test to $target failed (may be expected in CI)"
        fi
        echo
        
        tests_total=$((tests_total + 1))
        network_tests_total=$((network_tests_total + 1))
        log "INFO" "Testing MTU discovery to $target..."
        if test_mtu "$target"; then
            tests_passed=$((tests_passed + 1))
            network_tests_passed=$((network_tests_passed + 1))
            log "SUCCESS" "MTU test to $target passed"
        else
            log "WARN" "MTU test to $target failed (may be expected in CI)"
        fi
        echo
        
        tests_total=$((tests_total + 1))
        network_tests_total=$((network_tests_total + 1))
        log "INFO" "Testing HTTP connectivity to $target..."
        if test_http "$target"; then
            tests_passed=$((tests_passed + 1))
            network_tests_passed=$((network_tests_passed + 1))
            log "SUCCESS" "HTTP test to $target passed"
        else
            log "WARN" "HTTP test to $target failed (may be expected in CI)"
        fi
        echo
    done
    
    # Summary
    echo "Test Results Summary"
    echo "==================="
    echo "Core tests passed: $core_tests_passed/$core_tests_total"
    echo "Network tests passed: $network_tests_passed/$network_tests_total"
    echo "Total tests passed: $tests_passed/$tests_total"
    
    # Check if core tests passed (required for success)
    if [ $core_tests_passed -eq $core_tests_total ]; then
        if [ $network_tests_passed -eq $network_tests_total ]; then
            log "SUCCESS" "All tests passed! NetNoise is ready to use."
        else
            log "WARN" "Core tests passed, but some network tests failed (may be expected in CI environments)."
            log "SUCCESS" "NetNoise core functionality is ready to use."
        fi
        echo
        echo "Next steps:"
        echo "1. Run: sudo ./install.sh"
        echo "2. Edit: sudo nano /opt/netnoise/netnoise.conf"
        echo "3. Start: sudo systemctl start netnoise.timer"
        exit 0
    else
        log "ERROR" "Core tests failed. Please fix issues before installation."
        exit 1
    fi
}

# Run main function
main "$@"
