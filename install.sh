#!/bin/bash

# OpenNetProbe (ONP) Installation Script
# Installs ONP as a systemd service with configurable monitoring

set -euo pipefail

# Version information
VERSION="$(git describe --tags --always --dirty 2>/dev/null | sed 's/^v//' || echo '1.0.0')"
BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
GIT_COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
INSTALL_DIR="/opt/onp"
SERVICE_USER="root"
SERVICE_GROUP="root"

# Logging function
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

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log "ERROR" "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Check system requirements
check_requirements() {
    log "INFO" "Checking system requirements..."
    
    # Check if systemd is available
    if ! command -v systemctl &> /dev/null; then
        log "ERROR" "systemd is required but not found"
        exit 1
    fi
    
    # Check if required tools are available
    local missing_tools=()
    for tool in ping traceroute curl jq bc; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        log "WARN" "Missing optional tools: ${missing_tools[*]}"
        log "INFO" "Installing missing tools..."
        
        # Try to install missing tools based on package manager
        if command -v apt-get &> /dev/null; then
            apt-get update && apt-get install -y "${missing_tools[@]}"
        elif command -v yum &> /dev/null; then
            yum install -y "${missing_tools[@]}"
        elif command -v dnf &> /dev/null; then
            dnf install -y "${missing_tools[@]}"
        elif command -v pacman &> /dev/null; then
            pacman -S --noconfirm "${missing_tools[@]}"
        elif command -v brew &> /dev/null; then
            brew install "${missing_tools[@]}"
        else
            log "ERROR" "Cannot install missing tools automatically. Please install: ${missing_tools[*]}"
            exit 1
        fi
    fi
    
    log "SUCCESS" "System requirements check passed"
}

# Create installation directory
create_directories() {
    log "INFO" "Creating installation directories..."
    
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$INSTALL_DIR/logs"
    mkdir -p "$INSTALL_DIR/results"
    
    log "SUCCESS" "Directories created at $INSTALL_DIR"
}

# Install files
install_files() {
    log "INFO" "Installing OpenNetProbe files..."
    
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    # Copy script files
    cp "$script_dir/onp.sh" "$INSTALL_DIR/"
    cp "$script_dir/onp.conf" "$INSTALL_DIR/"
    
    # Make script executable
    chmod +x "$INSTALL_DIR/onp.sh"
    
    # Set ownership
    chown -R "$SERVICE_USER:$SERVICE_GROUP" "$INSTALL_DIR"
    
    log "SUCCESS" "Files installed successfully"
}

# Generate systemd timer based on configuration
generate_timer() {
    local config_file="$INSTALL_DIR/onp.conf"
    local timer_file="/etc/systemd/system/onp.timer"
    
    # Load configuration
    source "$config_file"
    
    # Default timer interval
    local timer_interval="${TIMER_INTERVAL:-hourly}"
    
    # Generate timer file
    cat > "$timer_file" << EOF
[Unit]
Description=OpenNetProbe (ONP) Network Monitoring Timer
Documentation=https://github.com/madebyjake/onp
Requires=onp.service

[Timer]
# Run based on configured interval
OnCalendar=$timer_interval
# Add some randomization to avoid all systems hitting at the same time
RandomizedDelaySec=300
# Timer persists across reboots
Persistent=true
# Accuracy settings
AccuracySec=1min

[Install]
WantedBy=timers.target
EOF
    
    log "INFO" "Generated timer with interval: $timer_interval"
}

# Install systemd service
install_systemd() {
    log "INFO" "Installing systemd service..."
    
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    # Copy service file
    cp "$script_dir/onp.service" "/etc/systemd/system/"
    
    # Generate timer file based on configuration
    generate_timer
    
    # Reload systemd
    systemctl daemon-reload
    
    # Enable timer (but don't start yet)
    systemctl enable onp.timer
    
    log "SUCCESS" "Systemd service installed and enabled"
}

# Test installation
test_installation() {
    log "INFO" "Testing installation..."
    
    # Test script execution
    if "$INSTALL_DIR/onp.sh" --help &> /dev/null || [ $? -eq 1 ]; then
        log "SUCCESS" "Script execution test passed"
    else
        log "ERROR" "Script execution test failed"
        exit 1
    fi
    
    # Test systemd service
    if systemctl is-enabled onp.timer &> /dev/null; then
        log "SUCCESS" "Systemd timer is enabled"
    else
        log "ERROR" "Systemd timer is not enabled"
        exit 1
    fi
}

# Regenerate timer after config changes
regenerate_timer() {
    log "INFO" "Regenerating timer based on current configuration..."
    
    if [ ! -f "$INSTALL_DIR/onp.conf" ]; then
        log "ERROR" "Configuration file not found: $INSTALL_DIR/onp.conf"
        exit 1
    fi
    
    # Generate new timer
    generate_timer
    
    # Reload systemd
    systemctl daemon-reload
    
    # Restart timer if it's running
    if systemctl is-active onp.timer &> /dev/null; then
        systemctl restart onp.timer
        log "SUCCESS" "Timer regenerated and restarted"
    else
        log "SUCCESS" "Timer regenerated (not running)"
    fi
}

# Check installed configuration
check_installed_config() {
    log "INFO" "Validating installed OpenNetProbe configuration..."
    
    if [ ! -f "$INSTALL_DIR/onp.conf" ]; then
        log "ERROR" "Configuration file not found: $INSTALL_DIR/onp.conf"
        exit 1
    fi
    
    if [ ! -f "$INSTALL_DIR/onp.sh" ]; then
        log "ERROR" "Main script not found: $INSTALL_DIR/onp.sh"
        exit 1
    fi
    
    # Test configuration validation
    if ! "$INSTALL_DIR/onp.sh" --check; then
        log "ERROR" "Configuration validation failed"
        exit 1
    fi
    
    # Check systemd service status
    if systemctl is-enabled onp.timer &> /dev/null; then
        log "SUCCESS" "Systemd timer is enabled"
    else
        log "WARN" "Systemd timer is not enabled"
    fi
    
    if systemctl is-active onp.timer &> /dev/null; then
        log "SUCCESS" "Systemd timer is active"
    else
        log "INFO" "Systemd timer is not active (this is normal if not started)"
    fi
    
    log "SUCCESS" "Configuration validation completed successfully"
}

# Show status and next steps
show_status() {
    log "INFO" "Installation completed successfully!"
    echo
    echo "=== OpenNetProbe (ONP) Status ==="
    echo "Installation directory: $INSTALL_DIR"
    echo "Configuration file: $INSTALL_DIR/onp.conf"
    echo "Log directory: $INSTALL_DIR/logs"
    echo "Results directory: $INSTALL_DIR/results"
    echo
    echo "=== Service Status ==="
    systemctl status onp.timer --no-pager
    echo
    echo "=== Next Steps ==="
    echo "1. Edit configuration: sudo nano $INSTALL_DIR/onp.conf"
    echo "2. Regenerate timer: sudo $0 regenerate"
    echo "3. Start monitoring: sudo systemctl start onp.timer"
    echo "4. Check status: sudo systemctl status onp.timer"
    echo "5. View logs: sudo journalctl -u onp.service -f"
    echo "6. Test manually: sudo $INSTALL_DIR/onp.sh"
    echo
    echo "=== Useful Commands ==="
    echo "Start timer:     sudo systemctl start onp.timer"
    echo "Stop timer:      sudo systemctl stop onp.timer"
    echo "Restart timer:   sudo systemctl restart onp.timer"
    echo "Regenerate:      sudo $0 regenerate"
    echo "View logs:       sudo journalctl -u onp.service"
    echo "Test run:        sudo $INSTALL_DIR/onp.sh"
    echo "Edit config:     sudo nano $INSTALL_DIR/onp.conf"
}

# Uninstall function
uninstall() {
    log "INFO" "Uninstalling OpenNetProbe (ONP)..."
    
    # Stop and disable services
    systemctl stop onp.timer 2>/dev/null || true
    systemctl disable onp.timer 2>/dev/null || true
    
    # Remove systemd files
    rm -f /etc/systemd/system/onp.service
    rm -f /etc/systemd/system/onp.timer
    
    # Reload systemd
    systemctl daemon-reload
    
    # Remove installation directory
    if [ -d "$INSTALL_DIR" ]; then
        rm -rf "$INSTALL_DIR"
    fi
    
    log "SUCCESS" "OpenNetProbe uninstalled successfully"
}

# Show help information
show_help() {
    cat << EOF
OpenNetProbe (ONP) Installation Script v${VERSION}

USAGE:
    $0 [COMMAND] [OPTIONS]

COMMANDS:
    install                 Install OpenNetProbe (ONP) (default)
    uninstall               Remove OpenNetProbe (ONP) completely
    regenerate              Regenerate timer based on current config
    check                   Check installed configuration
    help, -h, --help        Show this help message
    version, -v, --version  Show version information

OPTIONS:
    --force                 Force installation even if already installed

EXAMPLES:
    $0                      # Install OpenNetProbe (ONP)
    $0 install --force      # Force installation
    $0 regenerate           # Regenerate timer after config changes
    $0 check                # Check current installation
    $0 uninstall            # Remove OpenNetProbe (ONP)

For more information, see: https://github.com/madebyjake/onp
EOF
}

# Show version information
show_version() {
    cat << EOF
OpenNetProbe Installation Script v${VERSION}
Build Date: ${BUILD_DATE}
Git Commit: ${GIT_COMMIT}
EOF
}

# Main function
main() {
    echo "OpenNetProbe (ONP) Installation Script v${VERSION}"
    echo "=========================================="
    echo
    echo "⚠️  SECURITY REMINDER: This script requires root privileges."
    echo "   Please review the script before running: cat install.sh"
    echo
    
    # Parse command line arguments
    case "${1:-install}" in
        "install")
            check_root
            check_requirements
            create_directories
            install_files
            install_systemd
            test_installation
            show_status
            ;;
        "uninstall")
            check_root
            uninstall
            ;;
        "regenerate")
            check_root
            regenerate_timer
            ;;
        "check")
            check_root
            check_installed_config
            ;;
        "help"|"-h"|"--help")
            show_help
            ;;
        "version"|"-v"|"--version")
            show_version
            ;;
        *)
            log "ERROR" "Unknown command: $1"
            echo "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
