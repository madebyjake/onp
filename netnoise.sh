#!/bin/bash

# netnoise - Network Monitoring Script
# Monitors connectivity and performs traceroutes to detect network issues
# Runs as a systemd service with configurable timer

set -euo pipefail

# Version information
VERSION="$(git describe --tags --always --dirty 2>/dev/null | sed 's/^v//' || echo 'unknown')"
BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
GIT_COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')"

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/netnoise.conf"
LOG_DIR="${SCRIPT_DIR}/logs"
LOG_FILE="${LOG_DIR}/netnoise-$(date +%Y%m%d).log"
RESULTS_DIR="${SCRIPT_DIR}/results"
RESULTS_FILE="${RESULTS_DIR}/netnoise-results-$(date +%Y%m%d).json"
PERFORMANCE_LOG="${LOG_DIR}/netnoise-performance-$(date +%Y%m%d).log"
HEALTH_FILE="${SCRIPT_DIR}/health.json"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Create log directory if it doesn't exist
    mkdir -p "$LOG_DIR"
    
    # Log to file
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    
    # Also output to stdout with colors
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

# Performance tracking
track_performance() {
    local operation="$1"
    local start_time="$2"
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "0")
    
    # Create performance log directory
    mkdir -p "$LOG_DIR"
    
    # Log performance data
    echo "$(date '+%Y-%m-%d %H:%M:%S') $operation $duration" >> "$PERFORMANCE_LOG"
    
    # Alert on slow operations
    if (( $(echo "$duration > 5.0" | bc -l 2>/dev/null || echo 0) )); then
        log "WARN" "Slow operation: $operation took ${duration}s"
    fi
}

# Monitor resource usage
monitor_resources() {
    local memory_usage=$(ps -o rss= -p $$ 2>/dev/null | awk '{print $1/1024 " MB"}' || echo "unknown")
    local cpu_usage=$(ps -o %cpu= -p $$ 2>/dev/null | awk '{print $1 "%"}' || echo "unknown")
    
    log "INFO" "Resource usage: Memory: $memory_usage, CPU: $cpu_usage"
    
    # Alert on high resource usage
    if [[ "$memory_usage" =~ ^[0-9.]+ ]]; then
        if (( $(echo "${memory_usage% MB} > 200" | bc -l 2>/dev/null || echo 0) )); then
            log "WARN" "High memory usage: $memory_usage"
        fi
    fi
}

# Update health status
update_health_status() {
    local status="$1"
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local uptime=$(uptime -p 2>/dev/null || echo "unknown")
    local memory_usage=$(ps -o rss= -p $$ 2>/dev/null | awk '{print int($1/1024)}' || echo "unknown")
    
    # Get targets count safely
    local targets_count=0
    if [ -n "${TARGETS:-}" ] && [ ${#TARGETS[@]} -gt 0 ]; then
        targets_count=${#TARGETS[@]}
    fi
    
    printf '{
    "status": "%s",
    "timestamp": "%s",
    "version": "%s",
    "build_date": "%s",
    "git_commit": "%s",
    "uptime": "%s",
    "memory_usage_mb": %s,
    "targets_configured": %d,
    "last_run": "%s",
    "pid": %d
}' "$status" "$timestamp" "$VERSION" "$BUILD_DATE" "$GIT_COMMIT" "$uptime" "$memory_usage" "$targets_count" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" $$ > "$HEALTH_FILE"
}

# Check if required tools are available
check_dependencies() {
    local missing_tools=()
    
    for tool in ping traceroute curl jq; do
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
        log "ERROR" "Missing required tools: ${missing_tools[*]}"
        log "ERROR" "Please install missing tools and try again"
        exit 1
    fi
}

# Validate configuration
validate_config() {
    local errors=0
    local warnings=0
    
    # Check required variables
    if [ -z "${TARGETS:-}" ]; then
        log "ERROR" "TARGETS not defined in configuration"
        ((errors++))
    elif [ ${#TARGETS[@]} -eq 0 ]; then
        log "ERROR" "No targets configured"
        ((errors++))
    fi
    
    # Validate numeric settings
    if ! [[ "${PING_COUNT:-4}" =~ ^[0-9]+$ ]] || [ "${PING_COUNT:-4}" -lt 1 ] || [ "${PING_COUNT:-4}" -gt 100 ]; then
        log "ERROR" "PING_COUNT must be a number between 1-100 (got: ${PING_COUNT:-4})"
        ((errors++))
    fi
    
    if ! [[ "${PING_TIMEOUT:-10}" =~ ^[0-9]+$ ]] || [ "${PING_TIMEOUT:-10}" -lt 1 ] || [ "${PING_TIMEOUT:-10}" -gt 300 ]; then
        log "ERROR" "PING_TIMEOUT must be a number between 1-300 (got: ${PING_TIMEOUT:-10})"
        ((errors++))
    fi
    
    if ! [[ "${TRACEROUTE_MAX_HOPS:-30}" =~ ^[0-9]+$ ]] || [ "${TRACEROUTE_MAX_HOPS:-30}" -lt 1 ] || [ "${TRACEROUTE_MAX_HOPS:-30}" -gt 64 ]; then
        log "ERROR" "TRACEROUTE_MAX_HOPS must be a number between 1-64 (got: ${TRACEROUTE_MAX_HOPS:-30})"
        ((errors++))
    fi
    
    if ! [[ "${HTTP_TIMEOUT:-10}" =~ ^[0-9]+$ ]] || [ "${HTTP_TIMEOUT:-10}" -lt 1 ] || [ "${HTTP_TIMEOUT:-10}" -gt 300 ]; then
        log "ERROR" "HTTP_TIMEOUT must be a number between 1-300 (got: ${HTTP_TIMEOUT:-10})"
        ((errors++))
    fi
    
    if ! [[ "${DNS_TIMEOUT:-5}" =~ ^[0-9]+$ ]] || [ "${DNS_TIMEOUT:-5}" -lt 1 ] || [ "${DNS_TIMEOUT:-5}" -gt 60 ]; then
        log "ERROR" "DNS_TIMEOUT must be a number between 1-60 (got: ${DNS_TIMEOUT:-5})"
        ((errors++))
    fi
    
    if [[ "${DNS_ENABLED:-true}" != "true" ]] && [[ "${DNS_ENABLED:-true}" != "false" ]]; then
        log "ERROR" "DNS_ENABLED must be true or false (got: ${DNS_ENABLED:-true})"
        ((errors++))
    fi
    
    if ! [[ "${BANDWIDTH_TIMEOUT:-30}" =~ ^[0-9]+$ ]] || [ "${BANDWIDTH_TIMEOUT:-30}" -lt 5 ] || [ "${BANDWIDTH_TIMEOUT:-30}" -gt 300 ]; then
        log "ERROR" "BANDWIDTH_TIMEOUT must be a number between 5-300 (got: ${BANDWIDTH_TIMEOUT:-30})"
        ((errors++))
    fi
    
    if [[ "${BANDWIDTH_ENABLED:-false}" != "true" ]] && [[ "${BANDWIDTH_ENABLED:-false}" != "false" ]]; then
        log "ERROR" "BANDWIDTH_ENABLED must be true or false (got: ${BANDWIDTH_ENABLED:-false})"
        ((errors++))
    fi
    
    if [[ "${BANDWIDTH_TEST_UPLOAD:-false}" != "true" ]] && [[ "${BANDWIDTH_TEST_UPLOAD:-false}" != "false" ]]; then
        log "ERROR" "BANDWIDTH_TEST_UPLOAD must be true or false (got: ${BANDWIDTH_TEST_UPLOAD:-false})"
        ((errors++))
    fi
    
    if ! [[ "${PORT_SCAN_TIMEOUT:-5}" =~ ^[0-9]+$ ]] || [ "${PORT_SCAN_TIMEOUT:-5}" -lt 1 ] || [ "${PORT_SCAN_TIMEOUT:-5}" -gt 30 ]; then
        log "ERROR" "PORT_SCAN_TIMEOUT must be a number between 1-30 (got: ${PORT_SCAN_TIMEOUT:-5})"
        ((errors++))
    fi
    
    if [[ "${PORT_SCAN_ENABLED:-false}" != "true" ]] && [[ "${PORT_SCAN_ENABLED:-false}" != "false" ]]; then
        log "ERROR" "PORT_SCAN_ENABLED must be true or false (got: ${PORT_SCAN_ENABLED:-false})"
        ((errors++))
    fi
    
    if ! [[ "${LOG_RETENTION_DAYS:-30}" =~ ^[0-9]+$ ]] || [ "${LOG_RETENTION_DAYS:-30}" -lt 1 ] || [ "${LOG_RETENTION_DAYS:-30}" -gt 3650 ]; then
        log "ERROR" "LOG_RETENTION_DAYS must be a number between 1-3650 (got: ${LOG_RETENTION_DAYS:-30})"
        ((errors++))
    fi
    
    # Validate timer interval
    case "${TIMER_INTERVAL:-hourly}" in
        "minutely"|"hourly"|"daily"|"weekly"|"monthly")
            ;;
        *)
            if ! [[ "${TIMER_INTERVAL}" =~ ^\*.*\*.*\*.*\*.*\*.*$ ]]; then
                log "ERROR" "Invalid TIMER_INTERVAL format: ${TIMER_INTERVAL:-hourly}"
                log "INFO" "Valid formats: minutely, hourly, daily, weekly, monthly, or systemd calendar expression"
                ((errors++))
            fi
            ;;
    esac
    
    # Validate targets format with comprehensive checks
    if [ ${#TARGETS[@]} -gt 0 ]; then
        for target in "${TARGETS[@]}"; do
            local is_valid=false
            
            # Check for empty or whitespace-only targets
            if [[ -z "${target// }" ]]; then
                log "WARN" "Empty target found, skipping"
                ((warnings++))
                continue
            fi
            
            # Check for dangerous characters that could lead to command injection
            if [[ "$target" =~ [\;\|\&\`\$\(\)] ]]; then
                log "ERROR" "Target '$target' contains dangerous characters"
                ((errors++))
                continue
            fi
            
            # Validate URL format
            if [[ "$target" =~ ^https?:// ]]; then
                if [[ "$target" =~ ^https?://[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}(/.*)?$ ]]; then
                    is_valid=true
                else
                    log "WARN" "Target '$target' has invalid URL format"
                    ((warnings++))
                fi
            # Validate hostname format
            elif [[ "$target" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
                # Additional hostname validation
                if [[ ! "$target" =~ ^\. ]] && [[ ! "$target" =~ \.$ ]] && [[ ! "$target" =~ \.\. ]]; then
                    is_valid=true
                else
                    log "WARN" "Target '$target' has invalid hostname format"
                    ((warnings++))
                fi
            # Validate IP address format
            elif [[ "$target" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
                # Validate IP address ranges
                local ip_parts=($(echo "$target" | tr '.' ' '))
                local valid_ip=true
                for part in "${ip_parts[@]}"; do
                    if [ "$part" -gt 255 ] || [ "$part" -lt 0 ]; then
                        valid_ip=false
                        break
                    fi
                done
                if [ "$valid_ip" = true ]; then
                    is_valid=true
                else
                    log "WARN" "Target '$target' has invalid IP address format"
                    ((warnings++))
                fi
            else
                log "WARN" "Target '$target' may not be valid (hostname/IP/URL format expected)"
                ((warnings++))
            fi
            
            if [ "$is_valid" = true ]; then
                log "INFO" "Target '$target' validation passed"
            fi
        done
    fi
    
    # Validate alert settings
    if [ "${ALERT_ON_FAILURE:-true}" = "true" ]; then
        if [ -n "${ALERT_EMAIL:-}" ] && [[ ! "${ALERT_EMAIL}" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            log "WARN" "ALERT_EMAIL format may be invalid: ${ALERT_EMAIL}"
            ((warnings++))
        fi
        
        if [ -n "${ALERT_WEBHOOK:-}" ]; then
            # Webhook URL validation
            if [[ ! "${ALERT_WEBHOOK}" =~ ^https?://[a-zA-Z0-9.-]+(:[0-9]+)?(/.*)?$ ]]; then
                log "WARN" "ALERT_WEBHOOK should be a valid URL: ${ALERT_WEBHOOK}"
                ((warnings++))
            elif [[ "${ALERT_WEBHOOK}" =~ [\;\|\&\`\$\(\)] ]]; then
                log "ERROR" "ALERT_WEBHOOK contains dangerous characters: ${ALERT_WEBHOOK}"
                ((errors++))
            else
                log "INFO" "ALERT_WEBHOOK validation passed"
            fi
        fi
    fi
    
    # Summary
    if [ $warnings -gt 0 ]; then
        log "WARN" "Configuration validation completed with $warnings warnings"
    fi
    
    if [ $errors -gt 0 ]; then
        log "ERROR" "Configuration validation failed with $errors errors"
        return 1
    fi
    
    log "SUCCESS" "Configuration validation passed"
    return 0
}

# Load configuration
load_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        log "ERROR" "Configuration file not found: $CONFIG_FILE"
        log "INFO" "Creating default configuration file..."
        create_default_config
    fi
    
    # Source the configuration file
    source "$CONFIG_FILE"
    
    # Validate configuration
    if ! validate_config; then
        exit 1
    fi
    
    log "INFO" "Configuration loaded successfully"
    log "INFO" "Monitoring ${#TARGETS[@]} targets"
}

# Create default configuration file
create_default_config() {
    cat > "$CONFIG_FILE" << 'EOF'
# netnoise Configuration File
# Add targets to monitor (one per line)
# Format: TARGETS=("hostname1" "hostname2" "ip_address" "https://example.com")

TARGETS=(
    "google.com"
    "cloudflare.com"
    "github.com"
    "stackoverflow.com"
    "example.com"
)

# Ping settings
PING_COUNT=4
PING_TIMEOUT=10

# Traceroute settings
TRACEROUTE_MAX_HOPS=30
TRACEROUTE_TIMEOUT=5

# DNS resolution test settings
DNS_TIMEOUT=5
DNS_ENABLED=true

# Bandwidth test settings
BANDWIDTH_ENABLED=false
BANDWIDTH_TIMEOUT=30
BANDWIDTH_TEST_UPLOAD=false

# Port scanning test settings
PORT_SCAN_ENABLED=false
PORT_SCAN_TIMEOUT=5
PORT_SCAN_PORTS="22,80,443,25,53,110,143,993,995"

# HTTP/HTTPS test settings
HTTP_TIMEOUT=10
HTTP_USER_AGENT="netnoise/1.0"

# Alert settings
ALERT_ON_FAILURE=true
ALERT_EMAIL=""
ALERT_WEBHOOK=""

# Log retention (days)
LOG_RETENTION_DAYS=30
EOF
    log "INFO" "Default configuration created at $CONFIG_FILE"
    log "INFO" "Please edit the configuration file to add your monitoring targets"
}

# Test connectivity with ping
test_ping() {
    local target="$1"
    local result_file="$2"
    
    log "INFO" "Testing ping connectivity to $target"
    
    # Extract hostname from URL if needed and validate
    local hostname="$target"
    if [[ "$target" =~ ^https?:// ]]; then
        hostname=$(echo "$target" | sed 's|^https\?://||' | cut -d'/' -f1)
    fi
    
    # Validate hostname to prevent command injection
    if [[ ! "$hostname" =~ ^[a-zA-Z0-9.-]+$ ]] || [[ "$hostname" =~ ^\. ]] || [[ "$hostname" =~ \.$ ]] || [[ "$hostname" =~ \.\. ]]; then
        echo "  \"ping\": {\"status\": \"failed\", \"error\": \"invalid hostname format\"}" >> "$result_file"
        log "ERROR" "Invalid hostname format: $hostname"
        return 1
    fi
    
    if ping -c "$PING_COUNT" -W "$PING_TIMEOUT" "$hostname" &> /dev/null; then
        local ping_time=$(ping -c 1 -W "$PING_TIMEOUT" "$hostname" 2>/dev/null | grep 'time=' | sed 's/.*time=\([0-9.]*\).*/\1/')
        echo "  \"ping\": {\"status\": \"success\", \"time_ms\": \"$ping_time\"}" >> "$result_file"
        log "SUCCESS" "Ping to $hostname successful (${ping_time}ms)"
        return 0
    else
        echo "  \"ping\": {\"status\": \"failed\", \"error\": \"timeout or unreachable\"}" >> "$result_file"
        log "ERROR" "Ping to $hostname failed"
        return 1
    fi
}

# Test DNS resolution
test_dns() {
    local target="$1"
    local result_file="$2"
    
    log "INFO" "Testing DNS resolution for $target"
    
    # Extract hostname from URL if needed
    local hostname="$target"
    if [[ "$target" =~ ^https?:// ]]; then
        hostname=$(echo "$target" | sed 's|^https\?://||' | cut -d'/' -f1)
    fi
    
    # Validate hostname to prevent command injection
    if [[ ! "$hostname" =~ ^[a-zA-Z0-9.-]+$ ]] || [[ "$hostname" =~ ^\. ]] || [[ "$hostname" =~ \.$ ]] || [[ "$hostname" =~ \.\. ]]; then
        echo "  \"dns\": {\"status\": \"failed\", \"error\": \"invalid hostname format\"}" >> "$result_file"
        log "ERROR" "Invalid hostname format: $hostname"
        return 1
    fi
    
    local dns_start_time=$(date +%s.%N)
    local dns_result=""
    local dns_error=""
    local dns_time_ms=""
    local dns_records=""
    
    # Try dig first (more reliable and detailed)
    if command -v dig &> /dev/null; then
        if dns_result=$(timeout "$DNS_TIMEOUT" dig +short +time="$DNS_TIMEOUT" +tries=1 "$hostname" A 2>&1); then
            if [ -n "$dns_result" ] && [ "$dns_result" != "" ]; then
                # Extract IP addresses from dig output with proper validation
                local ip_addresses=()
                while IFS= read -r line; do
                    if [[ "$line" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
                        # Validate each octet is <= 255
                        local valid_ip=true
                        IFS='.' read -ra ADDR <<< "$line"
                        for octet in "${ADDR[@]}"; do
                            if [ "$octet" -gt 255 ] || [ "$octet" -lt 0 ]; then
                                valid_ip=false
                                break
                            fi
                        done
                        if [ "$valid_ip" = true ]; then
                            ip_addresses+=("$line")
                        fi
                    fi
                done <<< "$dns_result"
                if [ ${#ip_addresses[@]} -gt 0 ]; then
                    dns_records=$(printf '%s,' "${ip_addresses[@]}" | sed 's/,$//')
                    local dns_end_time=$(date +%s.%N)
                    dns_time_ms=$(echo "($dns_end_time - $dns_start_time) * 1000" | bc -l 2>/dev/null | cut -d. -f1 || echo "0")
                    echo "  \"dns\": {\"status\": \"success\", \"time_ms\": \"$dns_time_ms\", \"records\": \"$dns_records\", \"method\": \"dig\"}" >> "$result_file"
                    log "SUCCESS" "DNS resolution for $hostname successful (${dns_time_ms}ms, IPs: $dns_records)"
                    return 0
                else
                    dns_error="No valid IP addresses found in DNS response"
                fi
            else
                dns_error="Empty DNS response"
            fi
        else
            dns_error="dig command failed"
        fi
    # Fallback to nslookup if dig is not available
    elif command -v nslookup &> /dev/null; then
        if dns_result=$(timeout "$DNS_TIMEOUT" nslookup "$hostname" 2>&1); then
            # Extract IP addresses from nslookup output with proper validation
            local ip_addresses=()
            while IFS= read -r line; do
                if [[ "$line" =~ Address:[[:space:]]+([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}) ]]; then
                    local ip="${BASH_REMATCH[1]}"
                    # Validate each octet is <= 255
                    local valid_ip=true
                    IFS='.' read -ra ADDR <<< "$ip"
                    for octet in "${ADDR[@]}"; do
                        if [ "$octet" -gt 255 ] || [ "$octet" -lt 0 ]; then
                            valid_ip=false
                            break
                        fi
                    done
                    if [ "$valid_ip" = true ]; then
                        ip_addresses+=("$ip")
                    fi
                fi
            done <<< "$dns_result"
            if [ ${#ip_addresses[@]} -gt 0 ]; then
                dns_records=$(printf '%s,' "${ip_addresses[@]}" | sed 's/,$//')
                local dns_end_time=$(date +%s.%N)
                dns_time_ms=$(echo "($dns_end_time - $dns_start_time) * 1000" | bc -l 2>/dev/null | cut -d. -f1 || echo "0")
                echo "  \"dns\": {\"status\": \"success\", \"time_ms\": \"$dns_time_ms\", \"records\": \"$dns_records\", \"method\": \"nslookup\"}" >> "$result_file"
                log "SUCCESS" "DNS resolution for $hostname successful (${dns_time_ms}ms, IPs: $dns_records)"
                return 0
            else
                dns_error="No valid IP addresses found in DNS response"
            fi
        else
            dns_error="nslookup command failed"
        fi
    else
        dns_error="Neither dig nor nslookup available"
    fi
    
    # If we get here, DNS resolution failed
    local dns_end_time=$(date +%s.%N)
    dns_time_ms=$(echo "($dns_end_time - $dns_start_time) * 1000" | bc -l 2>/dev/null | cut -d. -f1 || echo "0")
    echo "  \"dns\": {\"status\": \"failed\", \"time_ms\": \"$dns_time_ms\", \"error\": \"$dns_error\"}" >> "$result_file"
    log "ERROR" "DNS resolution for $hostname failed: $dns_error"
    return 1
}

# Test bandwidth (upload/download speed)
test_bandwidth() {
    local target="$1"
    local result_file="$2"
    
    log "INFO" "Testing bandwidth to $target"
    
    # Extract hostname from URL if needed
    local hostname="$target"
    local test_url="$target"
    if [[ "$target" =~ ^https?:// ]]; then
        hostname=$(echo "$target" | sed 's|^https\?://||' | cut -d'/' -f1)
        test_url="$target"
    else
        # Default to HTTPS for bandwidth testing
        test_url="https://$target"
    fi
    
    # Validate hostname to prevent command injection
    if [[ ! "$hostname" =~ ^[a-zA-Z0-9.-]+$ ]] || [[ "$hostname" =~ ^\. ]] || [[ "$hostname" =~ \.$ ]] || [[ "$hostname" =~ \.\. ]]; then
        echo "  \"bandwidth\": {\"status\": \"failed\", \"error\": \"invalid hostname format\"}" >> "$result_file"
        log "ERROR" "Invalid hostname format: $hostname"
        return 1
    fi
    
    local bandwidth_start_time=$(date +%s.%N)
    local download_speed=""
    local upload_speed=""
    local bandwidth_error=""
    local total_time=""
    
    # Test download speed
    local download_test_file="/tmp/bandwidth_download_$$"
    local download_result=""
    
    if command -v curl &> /dev/null; then
        # Use curl for download test
        if download_result=$(timeout "$BANDWIDTH_TIMEOUT" curl -s -w "\n%{speed_download}\n%{time_total}" \
            -o "$download_test_file" \
            --max-time "$BANDWIDTH_TIMEOUT" \
            --connect-timeout 10 \
            -A "$HTTP_USER_AGENT" \
            "$test_url" 2>&1); then
            
            # Parse curl output
            local speed_bytes=$(echo "$download_result" | tail -n 2 | head -n 1)
            total_time=$(echo "$download_result" | tail -n 1)
            
            # Convert bytes per second to Mbps
            if [[ "$speed_bytes" =~ ^[0-9]+$ ]] && [ "$speed_bytes" -gt 0 ]; then
                download_speed=$(echo "scale=2; $speed_bytes * 8 / 1000000" | bc -l 2>/dev/null || echo "0")
            else
                bandwidth_error="Invalid download speed data"
            fi
        else
            bandwidth_error="Download test failed"
        fi
    elif command -v wget &> /dev/null; then
        # Use wget for download test
        local wget_start_time=$(date +%s.%N)
        if download_result=$(timeout "$BANDWIDTH_TIMEOUT" wget -O "$download_test_file" \
            --timeout="$BANDWIDTH_TIMEOUT" \
            --tries=1 \
            --user-agent="$HTTP_USER_AGENT" \
            "$test_url" 2>&1); then
            
            local wget_end_time=$(date +%s.%N)
            local wget_duration=$(echo "$wget_end_time - $wget_start_time" | bc -l 2>/dev/null || echo "1")
            
            # Extract file size and calculate speed
            local file_size=$(stat -f%z "$download_test_file" 2>/dev/null || echo "0")
            if [ "$file_size" -gt 0 ] && [ "$wget_duration" -gt 0 ]; then
                download_speed=$(echo "scale=2; $file_size * 8 / $wget_duration / 1000000" | bc -l 2>/dev/null || echo "0")
            else
                bandwidth_error="Invalid download data from wget"
            fi
        else
            bandwidth_error="Download test failed with wget"
        fi
    else
        bandwidth_error="Neither curl nor wget available for bandwidth testing"
    fi
    
    # Test upload speed (if enabled and tools available)
    local upload_speed=""
    if [ "${BANDWIDTH_TEST_UPLOAD:-false}" = "true" ] && command -v curl &> /dev/null; then
        local upload_test_file="/tmp/bandwidth_upload_$$"
        
        # Create test data for upload (1MB)
        dd if=/dev/zero of="$upload_test_file" bs=1024 count=1024 2>/dev/null
        
        # Use a service that supports POST uploads for testing
        local upload_url="https://httpbin.org/post"
        
        if upload_result=$(timeout "$BANDWIDTH_TIMEOUT" curl -s -w "\n%{speed_upload}\n%{time_total}" \
            -X POST \
            -F "file=@$upload_test_file" \
            --max-time "$BANDWIDTH_TIMEOUT" \
            --connect-timeout 10 \
            -A "$HTTP_USER_AGENT" \
            "$upload_url" 2>&1); then
            
            # Parse upload speed
            local upload_speed_bytes=$(echo "$upload_result" | tail -n 2 | head -n 1)
            if [[ "$upload_speed_bytes" =~ ^[0-9]+$ ]] && [ "$upload_speed_bytes" -gt 0 ]; then
                upload_speed=$(echo "scale=2; $upload_speed_bytes * 8 / 1000000" | bc -l 2>/dev/null || echo "0")
            fi
        fi
        
        rm -f "$upload_test_file"
    fi
    
    # Clean up download test file
    rm -f "$download_test_file"
    
    # Calculate total test time
    local bandwidth_end_time=$(date +%s.%N)
    local test_duration=$(echo "($bandwidth_end_time - $bandwidth_start_time) * 1000" | bc -l 2>/dev/null | cut -d. -f1 || echo "0")
    
    # Prepare results
    if [ -n "$bandwidth_error" ]; then
        echo "  \"bandwidth\": {\"status\": \"failed\", \"time_ms\": \"$test_duration\", \"error\": \"$bandwidth_error\"}" >> "$result_file"
        log "ERROR" "Bandwidth test failed: $bandwidth_error"
        return 1
    else
        local bandwidth_json="  \"bandwidth\": {\"status\": \"success\", \"time_ms\": \"$test_duration\", \"download_mbps\": \"$download_speed\""
        
        if [ -n "$upload_speed" ] && [ "$upload_speed" != "0" ]; then
            bandwidth_json="$bandwidth_json, \"upload_mbps\": \"$upload_speed\""
        fi
        
        bandwidth_json="$bandwidth_json, \"method\": \"curl\"}"
        echo "$bandwidth_json" >> "$result_file"
        
        if [ -n "$upload_speed" ] && [ "$upload_speed" != "0" ]; then
            log "SUCCESS" "Bandwidth test successful - Download: ${download_speed}Mbps, Upload: ${upload_speed}Mbps"
        else
            log "SUCCESS" "Bandwidth test successful - Download: ${download_speed}Mbps"
        fi
        return 0
    fi
}

# Test port connectivity
test_ports() {
    local target="$1"
    local result_file="$2"
    
    log "INFO" "Testing port connectivity to $target"
    
    # Extract hostname from URL if needed
    local hostname="$target"
    if [[ "$target" =~ ^https?:// ]]; then
        hostname=$(echo "$target" | sed 's|^https\?://||' | cut -d'/' -f1)
    fi
    
    # Validate hostname to prevent command injection
    if [[ ! "$hostname" =~ ^[a-zA-Z0-9.-]+$ ]] || [[ "$hostname" =~ ^\. ]] || [[ "$hostname" =~ \.$ ]] || [[ "$hostname" =~ \.\. ]]; then
        echo "  \"ports\": {\"status\": \"failed\", \"error\": \"invalid hostname format\"}" >> "$result_file"
        log "ERROR" "Invalid hostname format: $hostname"
        return 1
    fi
    
    local ports_start_time=$(date +%s.%N)
    local ports_json="  \"ports\": {\"status\": \"success\", \"time_ms\": \"0\", \"open_ports\": ["
    local open_ports=()
    local ports_error=""
    local total_open=0
    
    # Parse PORT_SCAN_PORTS configuration
    local ports_to_scan=()
    if [ -n "${PORT_SCAN_PORTS:-}" ]; then
        # Split comma-separated ports and validate
        IFS=',' read -ra port_list <<< "$PORT_SCAN_PORTS"
        for port in "${port_list[@]}"; do
            port=$(echo "$port" | tr -d ' ')  # Remove whitespace
            if [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]; then
                ports_to_scan+=("$port")
            else
                log "WARN" "Invalid port number: $port (skipping)"
            fi
        done
    else
        # Default ports if none specified
        ports_to_scan=(22 80 443 25 53 110 143 993 995)
    fi
    
    if [ ${#ports_to_scan[@]} -eq 0 ]; then
        echo "  \"ports\": {\"status\": \"disabled\", \"message\": \"No valid ports configured for scanning\"}" >> "$result_file"
        log "INFO" "No valid ports configured for scanning"
        return 0
    fi
    
    # Test each port
    for port in "${ports_to_scan[@]}"; do
        local port_open=false
        local port_error=""
        
        # Try netcat first (preferred method)
        if command -v nc &> /dev/null; then
            if timeout "$PORT_SCAN_TIMEOUT" nc -z -w"$PORT_SCAN_TIMEOUT" "$hostname" "$port" 2>/dev/null; then
                port_open=true
            else
                port_error="nc connection failed"
            fi
        # Fallback to /dev/tcp method
        elif [ -c /dev/tcp ]; then
            if timeout "$PORT_SCAN_TIMEOUT" bash -c "exec 3<>/dev/tcp/$hostname/$port" 2>/dev/null; then
                port_open=true
                exec 3<&- 2>/dev/null || true
            else
                port_error="tcp connection failed"
            fi
        else
            port_error="No port scanning tools available (nc or /dev/tcp)"
            break
        fi
        
        if [ "$port_open" = true ]; then
            open_ports+=("$port")
            total_open=$((total_open + 1))
            log "SUCCESS" "Port $port on $hostname is open"
        else
            log "DEBUG" "Port $port on $hostname is closed or filtered"
        fi
    done
    
    # Calculate total test time
    local ports_end_time=$(date +%s.%N)
    local test_duration=$(echo "($ports_end_time - $ports_start_time) * 1000" | bc -l 2>/dev/null | cut -d. -f1 || echo "0")
    
    # Prepare results
    if [ -n "$port_error" ] && [ ${#open_ports[@]} -eq 0 ]; then
        echo "  \"ports\": {\"status\": \"failed\", \"time_ms\": \"$test_duration\", \"error\": \"$port_error\"}" >> "$result_file"
        log "ERROR" "Port scanning failed: $port_error"
        return 1
    else
        # Build JSON array of open ports
        local ports_array=""
        for i in "${!open_ports[@]}"; do
            if [ $i -gt 0 ]; then
                ports_array="$ports_array, "
            fi
            ports_array="$ports_array${open_ports[$i]}"
        done
        
        echo "  \"ports\": {\"status\": \"success\", \"time_ms\": \"$test_duration\", \"open_ports\": [$ports_array], \"total_open\": $total_open, \"total_scanned\": ${#ports_to_scan[@]}}" >> "$result_file"
        
        if [ $total_open -gt 0 ]; then
            log "SUCCESS" "Port scanning completed - $total_open/${#ports_to_scan[@]} ports open: ${open_ports[*]}"
        else
            log "INFO" "Port scanning completed - 0/${#ports_to_scan[@]} ports open"
        fi
        return 0
    fi
}

# Test HTTP/HTTPS connectivity
test_http() {
    local target="$1"
    local result_file="$2"
    
    # Add protocol if not present
    if [[ ! "$target" =~ ^https?:// ]]; then
        target="https://$target"
    fi
    
    log "INFO" "Testing HTTP connectivity to $target"
    
    local http_code
    local response_time
    local curl_exit_code
    local error_message=""
    
    # Use a temporary file to capture curl output and errors
    local temp_file="/tmp/curl_output_$$"
    local error_file="/tmp/curl_error_$$"
    
    # Run curl with proper error handling
    curl -s -w "\n%{http_code}\n%{time_total}\n%{exitcode}" \
         -m "$HTTP_TIMEOUT" \
         -A "$HTTP_USER_AGENT" \
         --connect-timeout 10 \
         --max-time "$HTTP_TIMEOUT" \
         "$target" > "$temp_file" 2> "$error_file"
    
    curl_exit_code=$?
    
    # Check if curl succeeded
    if [ $curl_exit_code -eq 0 ]; then
        # Parse response
        local response_lines=$(wc -l < "$temp_file")
        if [ "$response_lines" -ge 3 ]; then
            http_code=$(tail -n 3 "$temp_file" | head -n 1)
            response_time=$(tail -n 2 "$temp_file" | head -n 1)
            
            # Validate HTTP code is numeric
            if [[ "$http_code" =~ ^[0-9]+$ ]]; then
                if [ "$http_code" -ge 200 ] && [ "$http_code" -lt 400 ]; then
                    local time_ms=$(echo "$response_time * 1000" | bc -l 2>/dev/null | cut -d. -f1 || echo "0")
                    echo "  \"http\": {\"status\": \"success\", \"code\": $http_code, \"time_ms\": \"$time_ms\"}" >> "$result_file"
                    log "SUCCESS" "HTTP to $target successful (${http_code}, ${response_time}s)"
                    rm -f "$temp_file" "$error_file"
                    return 0
                else
                    echo "  \"http\": {\"status\": \"failed\", \"code\": $http_code, \"error\": \"HTTP $http_code\"}" >> "$result_file"
                    log "ERROR" "HTTP to $target failed with code $http_code"
                    rm -f "$temp_file" "$error_file"
                    return 1
                fi
            else
                error_message="Invalid HTTP response format"
            fi
        else
            error_message="Incomplete HTTP response"
        fi
    else
        # Handle curl errors
        case $curl_exit_code in
            6)  error_message="Couldn't resolve host" ;;
            7)  error_message="Failed to connect to host" ;;
            28) error_message="Operation timeout" ;;
            35) error_message="SSL connect error" ;;
            52) error_message="Empty reply from server" ;;
            56) error_message="Failure in receiving network data" ;;
            *)  error_message="Curl error $curl_exit_code" ;;
        esac
        
        # Try to get more details from error file
        if [ -s "$error_file" ]; then
            local curl_error=$(head -n 1 "$error_file" | sed 's/^curl: [0-9]*: //')
            if [ -n "$curl_error" ]; then
                error_message="$error_message: $curl_error"
            fi
        fi
    fi
    
    # Log and record the error
    echo "  \"http\": {\"status\": \"failed\", \"error\": \"$error_message\"}" >> "$result_file"
    log "ERROR" "HTTP to $target failed: $error_message"
    
    # Clean up temp files
    rm -f "$temp_file" "$error_file"
    return 1
}

# Perform traceroute
test_traceroute() {
    local target="$1"
    local result_file="$2"
    
    log "INFO" "Performing traceroute to $target"
    
    # Extract hostname from URL if needed
    local hostname="$target"
    if [[ "$target" =~ ^https?:// ]]; then
        hostname=$(echo "$target" | sed 's|^https\?://||' | cut -d'/' -f1)
    fi
    
    # Validate hostname to prevent command injection
    if [[ ! "$hostname" =~ ^[a-zA-Z0-9.-]+$ ]] || [[ "$hostname" =~ ^\. ]] || [[ "$hostname" =~ \.$ ]] || [[ "$hostname" =~ \.\. ]]; then
        echo "  \"traceroute\": {\"status\": \"failed\", \"error\": \"invalid hostname format\"}" >> "$result_file"
        log "ERROR" "Invalid hostname format: $hostname"
        return 1
    fi
    
    local trace_output
    local trace_file="/tmp/traceroute_$$"
    
    if trace_output=$(timeout "$TRACEROUTE_TIMEOUT" traceroute -m "$TRACEROUTE_MAX_HOPS" "$hostname" 2>&1); then
        local hop_count=$(echo "$trace_output" | grep -c "^\s*[0-9]" || echo "0")
        local last_hop=$(echo "$trace_output" | grep "^\s*[0-9]" | tail -1 | awk '{print $2}' | sed 's/[()]//g')
        
        echo "  \"traceroute\": {\"status\": \"success\", \"hops\": $hop_count, \"last_hop\": \"$last_hop\"}" >> "$result_file"
        log "SUCCESS" "Traceroute to $hostname completed ($hop_count hops, last: $last_hop)"
        
        # Save full traceroute output
        echo "$trace_output" > "${RESULTS_DIR}/traceroute-${hostname}-$(date +%Y%m%d-%H%M%S).txt"
    else
        echo "  \"traceroute\": {\"status\": \"failed\", \"error\": \"timeout or failed\"}" >> "$result_file"
        log "ERROR" "Traceroute to $hostname failed"
    fi
    
    rm -f "$trace_file"
}

# Test a single target
test_target() {
    local target="$1"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    log "INFO" "Starting tests for target: $target"
    
    # Create results directory
    mkdir -p "$RESULTS_DIR"
    
    # Start JSON result for this target
    local result_file="/tmp/netnoise_result_$$.json"
    echo "{" > "$result_file"
    echo "  \"target\": \"$target\"," >> "$result_file"
    echo "  \"timestamp\": \"$timestamp\"," >> "$result_file"
    
    # Test DNS resolution (if enabled)
    local dns_result=0
    if [ "${DNS_ENABLED:-true}" = "true" ]; then
        test_dns "$target" "$result_file"
        dns_result=$?
    else
        echo "  \"dns\": {\"status\": \"disabled\", \"message\": \"DNS testing disabled in configuration\"}" >> "$result_file"
        log "INFO" "DNS testing disabled for $target"
    fi
    
    # Test ping
    test_ping "$target" "$result_file"
    local ping_result=$?
    
    # Test bandwidth (if enabled)
    local bandwidth_result=0  # Default to success when disabled
    if [ "${BANDWIDTH_ENABLED:-false}" = "true" ]; then
        test_bandwidth "$target" "$result_file"
        bandwidth_result=$?
    else
        echo "  \"bandwidth\": {\"status\": \"disabled\", \"message\": \"Bandwidth testing disabled in configuration\"}" >> "$result_file"
        log "INFO" "Bandwidth testing disabled for $target"
    fi
    
    # Test port scanning (if enabled)
    local ports_result=0  # Default to success when disabled
    if [ "${PORT_SCAN_ENABLED:-false}" = "true" ]; then
        test_ports "$target" "$result_file"
        ports_result=$?
    else
        echo "  \"ports\": {\"status\": \"disabled\", \"message\": \"Port scanning disabled in configuration\"}" >> "$result_file"
        log "INFO" "Port scanning disabled for $target"
    fi
    
    # Test HTTP
    test_http "$target" "$result_file"
    local http_result=$?
    
    # Test traceroute
    test_traceroute "$target" "$result_file"
    
    # Close JSON
    echo "}" >> "$result_file"
    
    # Append to main results file with file locking to prevent race conditions
    local lock_file="${RESULTS_FILE}.lock"
    local timeout=30
    local count=0
    
    # Wait for lock with timeout
    while [ $count -lt $timeout ]; do
        if (set -C; echo $$ > "$lock_file") 2>/dev/null; then
            # Got the lock
            trap 'rm -f "$lock_file"' EXIT
            
            # Append to main results file
            if [ -f "$RESULTS_FILE" ]; then
                echo "," >> "$RESULTS_FILE"
            else
                echo "[" > "$RESULTS_FILE"
            fi
            cat "$result_file" >> "$RESULTS_FILE"
            
            # Release lock
            rm -f "$lock_file"
            trap - EXIT
            break
        else
            # Lock is held, wait and retry
            sleep 1
            count=$((count + 1))
        fi
    done
    
    # If we couldn't get the lock, log a warning but continue
    if [ $count -eq $timeout ]; then
        log "WARN" "Could not acquire lock for results file, skipping this result"
    fi
    
    # Clean up temp file
    rm -f "$result_file"
    
    # Return overall result
    if [ $dns_result -eq 0 ] || [ $ping_result -eq 0 ] || [ $bandwidth_result -eq 0 ] || [ $ports_result -eq 0 ] || [ $http_result -eq 0 ]; then
        log "SUCCESS" "Target $target is reachable"
        return 0
    else
        log "ERROR" "Target $target is unreachable"
        return 1
    fi
}

# Send alert if configured
send_alert() {
    local message="$1"
    
    if [ "$ALERT_ON_FAILURE" = true ]; then
        log "WARN" "Alert: $message"
        
        # Email alert (if configured)
        if [ -n "${ALERT_EMAIL:-}" ] && command -v mail &> /dev/null; then
            echo "$message" | mail -s "netnoise Alert" "$ALERT_EMAIL"
            log "INFO" "Alert email sent to $ALERT_EMAIL"
        fi
        
        # Webhook alert (if configured)
        if [ -n "${ALERT_WEBHOOK:-}" ]; then
            # Properly escape the message for JSON to prevent injection
            local escaped_message=$(printf '%s\n' "$message" | sed 's/\\/\\\\/g; s/"/\\"/g; s/`/\\`/g; s/\$/\\$/g')
            
            # Validate webhook URL format
            if [[ "$ALERT_WEBHOOK" =~ ^https?://[a-zA-Z0-9.-]+(:[0-9]+)?(/.*)?$ ]]; then
                curl -X POST -H "Content-Type: application/json" \
                     -d "{\"text\":\"$escaped_message\"}" \
                     --max-time 30 \
                     "$ALERT_WEBHOOK" &> /dev/null || log "WARN" "Failed to send webhook alert"
            else
                log "WARN" "Invalid webhook URL format: $ALERT_WEBHOOK"
            fi
        fi
    fi
}

# Clean up old logs
cleanup_old_logs() {
    if [ -d "$LOG_DIR" ]; then
        find "$LOG_DIR" -name "*.log" -mtime +$LOG_RETENTION_DAYS -delete 2>/dev/null || true
        log "INFO" "Cleaned up logs older than $LOG_RETENTION_DAYS days"
    fi
    
    if [ -d "$RESULTS_DIR" ]; then
        find "$RESULTS_DIR" -name "*.json" -mtime +$LOG_RETENTION_DAYS -delete 2>/dev/null || true
        find "$RESULTS_DIR" -name "traceroute-*.txt" -mtime +$LOG_RETENTION_DAYS -delete 2>/dev/null || true
    fi
}

# Show help information
show_help() {
    cat << EOF
netnoise v${VERSION} - Network Monitoring Tool

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -h, --help      Show this help message
    -v, --version   Show version information
    -c, --check      Check configuration and exit

DESCRIPTION:
    Monitors network connectivity by performing ping, HTTP, and traceroute tests
    on configured targets. Designed to run as a systemd service.

EXAMPLES:
    $0                 # Run monitoring with current configuration
    $0 --check         # Check configuration and exit
    $0 --version       # Show version information

For more information, see: https://github.com/madebyjake/netnoise
EOF
}

# Show version information
show_version() {
    cat << EOF
netnoise v${VERSION}
Build Date: ${BUILD_DATE}
Git Commit: ${GIT_COMMIT}
EOF
}

# Main execution
main() {
    # Handle command line arguments
    case "${1:-}" in
        "--help"|"-h")
            show_help
            exit 0
            ;;
        "--version"|"-v")
            show_version
            exit 0
            ;;
        "--check"|"-c")
            load_config
            validate_config
            log "SUCCESS" "Configuration validation passed"
            exit 0
            ;;
        "")
            # No arguments, continue with normal execution
            ;;
        *)
            log "ERROR" "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac

    log "INFO" "netnoise v${VERSION} starting - $(date)"
    
    # Update health status
    update_health_status "starting"
    
    # Check dependencies
    local start_time=$(date +%s.%N)
    check_dependencies
    track_performance "check_dependencies" "$start_time"
    
    # Load configuration
    start_time=$(date +%s.%N)
    load_config
    track_performance "load_config" "$start_time"
    
    # Clean up old logs
    start_time=$(date +%s.%N)
    cleanup_old_logs
    track_performance "cleanup_old_logs" "$start_time"
    
    # Monitor resources
    monitor_resources
    
    local failed_targets=()
    local total_targets=${#TARGETS[@]}
    
    # Test each target
    for target in "${TARGETS[@]}"; do
        start_time=$(date +%s.%N)
        if ! test_target "$target"; then
            failed_targets+=("$target")
        fi
        track_performance "test_target_$target" "$start_time"
    done
    
    # Close JSON array with file locking
    local lock_file="${RESULTS_FILE}.lock"
    local timeout=30
    local count=0
    
    # Wait for lock with timeout
    while [ $count -lt $timeout ]; do
        if (set -C; echo $$ > "$lock_file") 2>/dev/null; then
            # Got the lock
            trap 'rm -f "$lock_file"' EXIT
            
            # Close JSON array
            if [ -f "$RESULTS_FILE" ]; then
                echo "]" >> "$RESULTS_FILE"
            fi
            
            # Release lock
            rm -f "$lock_file"
            trap - EXIT
            break
        else
            # Lock is held, wait and retry
            sleep 1
            count=$((count + 1))
        fi
    done
    
    # If we couldn't get the lock, log a warning
    if [ $count -eq $timeout ]; then
        log "WARN" "Could not acquire lock to close JSON array"
    fi
    
    # Summary
    local failed_count=${#failed_targets[@]}
    local success_count=$((total_targets - failed_count))
    
    log "INFO" "Test completed: $success_count/$total_targets targets successful"
    
    if [ $failed_count -gt 0 ]; then
        log "ERROR" "Failed targets: ${failed_targets[*]}"
        send_alert "netnoise detected $failed_count failed targets: ${failed_targets[*]}"
        update_health_status "failed"
        exit 1
    else
        log "SUCCESS" "All targets are reachable"
        update_health_status "completed"
        exit 0
    fi
}

# Run main function
main "$@"
