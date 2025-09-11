#!/bin/bash

# netnoise - Configuration Module
# Handles configuration loading, validation, and default configuration creation

# Ensure this module is being sourced, not executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Error: This module must be sourced, not executed directly" >&2
    exit 1
fi

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
    
    if ! [[ "${MTU_TIMEOUT:-5}" =~ ^[0-9]+$ ]] || [ "${MTU_TIMEOUT:-5}" -lt 1 ] || [ "${MTU_TIMEOUT:-5}" -gt 30 ]; then
        log "ERROR" "MTU_TIMEOUT must be a number between 1-30 (got: ${MTU_TIMEOUT:-5})"
        ((errors++))
    fi
    
    if [[ "${MTU_ENABLED:-false}" != "true" ]] && [[ "${MTU_ENABLED:-false}" != "false" ]]; then
        log "ERROR" "MTU_ENABLED must be true or false (got: ${MTU_ENABLED:-false})"
        ((errors++))
    fi
    
    if ! [[ "${MTU_MIN:-576}" =~ ^[0-9]+$ ]] || [ "${MTU_MIN:-576}" -lt 68 ] || [ "${MTU_MIN:-576}" -gt 9000 ]; then
        log "ERROR" "MTU_MIN must be a number between 68-9000 (got: ${MTU_MIN:-576})"
        ((errors++))
    fi
    
    if ! [[ "${MTU_MAX:-1500}" =~ ^[0-9]+$ ]] || [ "${MTU_MAX:-1500}" -lt 68 ] || [ "${MTU_MAX:-1500}" -gt 9000 ]; then
        log "ERROR" "MTU_MAX must be a number between 68-9000 (got: ${MTU_MAX:-1500})"
        ((errors++))
    fi
    
    if ! [[ "${MTU_STEP:-10}" =~ ^[0-9]+$ ]] || [ "${MTU_STEP:-10}" -lt 1 ] || [ "${MTU_STEP:-10}" -gt 100 ]; then
        log "ERROR" "MTU_STEP must be a number between 1-100 (got: ${MTU_STEP:-10})"
        ((errors++))
    fi
    
    if [ "${MTU_MIN:-576}" -ge "${MTU_MAX:-1500}" ]; then
        log "ERROR" "MTU_MIN (${MTU_MIN:-576}) must be less than MTU_MAX (${MTU_MAX:-1500})"
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
                local ip_parts
                read -ra ip_parts <<< "$(echo "$target" | tr '.' ' ')"
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
    # shellcheck source=/dev/null
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
    # Core Internet Infrastructure
    "google.com"                # Global search/CDN
    "cloudflare.com"            # Major CDN/DNS provider
    "1.1.1.1"                   # Cloudflare DNS (IPv4)
    "8.8.8.8"                   # Google DNS (IPv4)
    
    # DNS Root Servers
    "a.root-servers.net"        # Root DNS server A
    "b.root-servers.net"        # Root DNS server B
    
    # Global Services
    "amazon.com"                # Global e-commerce/CDN
    "microsoft.com"             # Enterprise services
    "github.com"                # Developer platform
    "wikipedia.org"             # Global knowledge base
    
    # CDN Providers
    "fastly.com"                # Major CDN provider
    "akamai.com"                # Major CDN provider
    
    # Network Infrastructure
    "level3.net"                # Major backbone provider
    "he.net"                    # Hurricane Electric (global ISP)
    "cogentco.com"              # Major backbone provider
    "ntt.net"                   # Global backbone provider
    
    # Time Services
    "time.nist.gov"             # NTP time server
)

# Ping settings - Basic connectivity testing
PING_COUNT=4                    # Number of ping packets to send
PING_TIMEOUT=10                 # Timeout per ping in seconds

# Traceroute settings - Network path discovery
TRACEROUTE_MAX_HOPS=30          # Maximum number of hops to trace
TRACEROUTE_TIMEOUT=5            # Timeout per hop in seconds

# DNS resolution test settings - Name resolution testing
DNS_TIMEOUT=5                   # DNS query timeout in seconds
DNS_ENABLED=true                # Enable DNS resolution tests

# Bandwidth test settings - Network performance testing (resource intensive)
BANDWIDTH_ENABLED=false         # Enable bandwidth testing
BANDWIDTH_TIMEOUT=30            # Bandwidth test timeout in seconds
BANDWIDTH_TEST_UPLOAD=false     # Include upload speed testing

# Port scanning test settings - Service availability testing (security sensitive)
PORT_SCAN_ENABLED=false         # Enable port scanning
PORT_SCAN_TIMEOUT=5             # Port scan timeout in seconds
PORT_SCAN_PORTS="22,80,443,25,53,110,143,993,995"  # Ports to scan

# MTU discovery test settings - Maximum transmission unit testing
MTU_ENABLED=false               # Enable MTU discovery
MTU_TIMEOUT=5                   # MTU test timeout in seconds
MTU_MIN=576                     # Minimum MTU to test (bytes)
MTU_MAX=1500                    # Maximum MTU to test (bytes)
MTU_STEP=10                     # MTU test step size (bytes)

# HTTP/HTTPS test settings - Web service connectivity
HTTP_TIMEOUT=10                 # HTTP request timeout in seconds
HTTP_USER_AGENT="netnoise/1.0"  # User agent string for HTTP requests

# Alert settings - Notification configuration
ALERT_ON_FAILURE=true           # Send alerts when tests fail
ALERT_EMAIL=""                  # Email address for alerts (optional)
ALERT_WEBHOOK=""                # Webhook URL for alerts (optional)

# Log retention settings - Log management
LOG_RETENTION_DAYS=30           # Days to retain log files

# Timer settings - Service scheduling
TIMER_INTERVAL="hourly"         # How often to run tests
EOF
    log "INFO" "Default configuration created at $CONFIG_FILE"
    log "INFO" "Please edit the configuration file to add your monitoring targets"
}
