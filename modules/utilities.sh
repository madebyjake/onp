#!/bin/bash

# netnoise - Utilities Module
# Contains utility functions for health status, dependencies, cleanup, and help

# Ensure this module is being sourced, not executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Error: This module must be sourced, not executed directly" >&2
    exit 1
fi

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

# Clean up old logs
cleanup_old_logs() {
    if [ -d "$LOG_DIR" ]; then
        find "$LOG_DIR" -name "*.log" -mtime +"$LOG_RETENTION_DAYS" -delete 2>/dev/null || true
        log "INFO" "Cleaned up logs older than $LOG_RETENTION_DAYS days"
    fi
    
    if [ -d "$RESULTS_DIR" ]; then
        find "$RESULTS_DIR" -name "*.json" -mtime +"$LOG_RETENTION_DAYS" -delete 2>/dev/null || true
        find "$RESULTS_DIR" -name "traceroute-*.txt" -mtime +"$LOG_RETENTION_DAYS" -delete 2>/dev/null || true
    fi
}

# Show help information
show_help() {
    cat << EOF
netnoise v${VERSION} - Network Monitoring Tool

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -h, --help       Show this help message
    -v, --version    Show version information
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
