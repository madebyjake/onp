#!/bin/bash

# netnoise - Network Monitoring Script
# This script is the main entry point for netnoise

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

# Load modules with error handling
load_module() {
    local module="$1"
    # shellcheck source=/dev/null
    if ! source "${SCRIPT_DIR}/modules/${module}.sh" 2>/dev/null; then
        echo "Error: Failed to load module ${module}.sh" >&2
        echo "Please ensure all module files exist and are executable." >&2
        exit 1
    fi
}

load_module "logging"
load_module "config"
load_module "network_tests"
load_module "utilities"
load_module "alerts"

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
            # Load config (which includes validation)
            load_config
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
    local start_time
    start_time=$(date +%s.%N)
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
    
    if [ "$failed_count" -gt 0 ]; then
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
