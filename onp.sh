#!/bin/bash

# OpenNetProbe (ONP) - Network Monitoring Script
# Monitors connectivity and performs traceroutes to detect network issues
# Runs as a systemd service with configurable timer

set -euo pipefail

# Version information
VERSION="$(git describe --tags --always --dirty 2>/dev/null | sed 's/^v//' || echo 'unknown')"
BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
GIT_COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')"

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/onp.conf"
LOG_DIR="${SCRIPT_DIR}/logs"
LOG_FILE="${LOG_DIR}/onp-$(date +%Y%m%d).log"
RESULTS_DIR="${SCRIPT_DIR}/results"
RESULTS_FILE="${RESULTS_DIR}/onp-results-$(date +%Y%m%d).json"
PERFORMANCE_LOG="${LOG_DIR}/onp-performance-$(date +%Y%m%d).log"
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
    
    cat > "$HEALTH_FILE" << EOF
{
    "status": "$status",
    "timestamp": "$timestamp",
    "version": "$VERSION",
    "build_date": "$BUILD_DATE",
    "git_commit": "$GIT_COMMIT",
    "uptime": "$uptime",
    "memory_usage_mb": $memory_usage,
    "targets_configured": ${#TARGETS[@]},
    "last_run": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "pid": $$
}
EOF
}

# Check if required tools are available
check_dependencies() {
    local missing_tools=()
    
    for tool in ping traceroute curl jq; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
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
    
    # Validate targets format
    if [ ${#TARGETS[@]} -gt 0 ]; then
        for target in "${TARGETS[@]}"; do
            if [[ ! "$target" =~ ^(https?://)?[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}(/.*)?$ ]] && [[ ! "$target" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
                log "WARN" "Target '$target' may not be valid (hostname/IP/URL format expected)"
                ((warnings++))
            fi
        done
    fi
    
    # Validate alert settings
    if [ "${ALERT_ON_FAILURE:-true}" = "true" ]; then
        if [ -n "${ALERT_EMAIL:-}" ] && [[ ! "${ALERT_EMAIL}" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            log "WARN" "ALERT_EMAIL format may be invalid: ${ALERT_EMAIL}"
            ((warnings++))
        fi
        
        if [ -n "${ALERT_WEBHOOK:-}" ] && [[ ! "${ALERT_WEBHOOK}" =~ ^https?:// ]]; then
            log "WARN" "ALERT_WEBHOOK should be a valid URL: ${ALERT_WEBHOOK}"
            ((warnings++))
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
# ONP Configuration File
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

# HTTP/HTTPS test settings
HTTP_TIMEOUT=10
HTTP_USER_AGENT="OpenNetProbe (ONP)/1.0"

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
    
    if ping -c "$PING_COUNT" -W "$PING_TIMEOUT" "$target" &> /dev/null; then
        local ping_time=$(ping -c 1 -W "$PING_TIMEOUT" "$target" 2>/dev/null | grep 'time=' | sed 's/.*time=\([0-9.]*\).*/\1/')
        echo "  \"ping\": {\"status\": \"success\", \"time_ms\": \"$ping_time\"}" >> "$result_file"
        log "SUCCESS" "Ping to $target successful (${ping_time}ms)"
        return 0
    else
        echo "  \"ping\": {\"status\": \"failed\", \"error\": \"timeout or unreachable\"}" >> "$result_file"
        log "ERROR" "Ping to $target failed"
        return 1
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
    
    if response=$(curl -s -w "\n%{http_code}\n%{time_total}" -m "$HTTP_TIMEOUT" -A "$HTTP_USER_AGENT" "$target" 2>/dev/null); then
        http_code=$(echo "$response" | tail -n 2 | head -n 1)
        response_time=$(echo "$response" | tail -n 1)
        
        if [ "$http_code" -ge 200 ] && [ "$http_code" -lt 400 ]; then
            echo "  \"http\": {\"status\": \"success\", \"code\": $http_code, \"time_ms\": \"$(echo "$response_time * 1000" | bc -l | cut -d. -f1)\"}" >> "$result_file"
            log "SUCCESS" "HTTP to $target successful (${http_code}, ${response_time}s)"
            return 0
        else
            echo "  \"http\": {\"status\": \"failed\", \"code\": $http_code, \"error\": \"HTTP $http_code\"}" >> "$result_file"
            log "ERROR" "HTTP to $target failed with code $http_code"
            return 1
        fi
    else
        echo "  \"http\": {\"status\": \"failed\", \"error\": \"connection failed\"}" >> "$result_file"
        log "ERROR" "HTTP to $target failed"
        return 1
    fi
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
    local result_file="/tmp/onp_result_$$.json"
    echo "{" > "$result_file"
    echo "  \"target\": \"$target\"," >> "$result_file"
    echo "  \"timestamp\": \"$timestamp\"," >> "$result_file"
    
    # Test ping
    test_ping "$target" "$result_file"
    local ping_result=$?
    
    # Test HTTP
    test_http "$target" "$result_file"
    local http_result=$?
    
    # Test traceroute
    test_traceroute "$target" "$result_file"
    
    # Close JSON
    echo "}" >> "$result_file"
    
    # Append to main results file
    if [ -f "$RESULTS_FILE" ]; then
        echo "," >> "$RESULTS_FILE"
    else
        echo "[" > "$RESULTS_FILE"
    fi
    cat "$result_file" >> "$RESULTS_FILE"
    
    # Clean up temp file
    rm -f "$result_file"
    
    # Return overall result
    if [ $ping_result -eq 0 ] || [ $http_result -eq 0 ]; then
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
            echo "$message" | mail -s "ONP Alert" "$ALERT_EMAIL"
            log "INFO" "Alert email sent to $ALERT_EMAIL"
        fi
        
        # Webhook alert (if configured)
        if [ -n "${ALERT_WEBHOOK:-}" ]; then
            curl -X POST -H "Content-Type: application/json" \
                 -d "{\"text\":\"$message\"}" \
                 "$ALERT_WEBHOOK" &> /dev/null || log "WARN" "Failed to send webhook alert"
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
OpenNetProbe (ONP) v${VERSION} - Network Monitoring Tool

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

For more information, see: https://github.com/madebyjake/onp
EOF
}

# Show version information
show_version() {
    cat << EOF
OpenNetProbe (ONP) v${VERSION}
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

    log "INFO" "ONP v${VERSION} starting - $(date)"
    
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
    
    # Close JSON array
    if [ -f "$RESULTS_FILE" ]; then
        echo "]" >> "$RESULTS_FILE"
    fi
    
    # Summary
    local failed_count=${#failed_targets[@]}
    local success_count=$((total_targets - failed_count))
    
    log "INFO" "Test completed: $success_count/$total_targets targets successful"
    
    if [ $failed_count -gt 0 ]; then
        log "ERROR" "Failed targets: ${failed_targets[*]}"
        send_alert "ONP detected $failed_count failed targets: ${failed_targets[*]}"
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
