#!/bin/bash

# netnoise - Logging Module
# Provides centralized logging functionality with colorized output and file logging

# Ensure this module is being sourced, not executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Error: This module must be sourced, not executed directly" >&2
    exit 1
fi

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
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
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
    local end_time
    end_time=$(date +%s.%N)
    local duration
    duration=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "0")
    
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
