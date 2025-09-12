# NetNoise

[![Linux](https://img.shields.io/badge/Linux-FCC624?logo=linux&logoColor=black)](https://www.linux.org/)
[![Bash](https://img.shields.io/badge/Bash-4EAA25?logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![Make](https://img.shields.io/badge/Make-427819?logo=gnu&logoColor=white)](https://www.gnu.org/software/make/)
[![License](https://img.shields.io/badge/License-MIT-yellow?logo=open-source-initiative&logoColor=white)](LICENSE)
[![Test](https://github.com/madebyjake/netnoise/actions/workflows/test.yml/badge.svg)](https://github.com/madebyjake/netnoise/actions/workflows/test.yml)

NetNoise is a network monitoring and troubleshooting utility that performs connectivity testing across multiple protocols. It provides automated testing of DNS resolution, ping, traceroute, HTTP/HTTPS connectivity, bandwidth analysis, port scanning, and MTU discovery against configurable targets for network diagnostics and monitoring.

## Features

- **Network Testing**: DNS resolution, ping, traceroute, HTTP/HTTPS connectivity
- **Performance Analysis**: Bandwidth testing, MTU discovery, port scanning
- **Monitoring**: Automated scheduling with systemd integration
- **Alerting**: Email and webhook notifications on failures
- **Logging**: Structured JSON output with configurable retention
- **Configuration**: Flexible target lists and test parameters

## Quick Reference

```bash
# Installation
git clone https://github.com/madebyjake/netnoise.git
cd netnoise
sudo ./install.sh

# Upgrade
make upgrade    # Upgrade netnoise to latest version

# Service Management
make start      # Start monitoring
make stop       # Stop monitoring
make restart    # Restart monitoring
make status     # Check service status

# Configuration
make config     # Edit configuration
make check      # Validate configuration
make regenerate # Regenerate timer after config changes

# Testing & Monitoring
make test       # Run test suite
make manual     # Run manual test
make health     # Show health status
make logs       # View recent logs

# Maintenance
make clean      # Clean old logs and results
make version    # Show version information
```

## Quick Start

### Prerequisites

- Linux system with systemd
- Root or sudo access
- Required tools: `ping`, `traceroute`, `curl`, `jq`, `bc`, `dig` or `nslookup`

### Installation

1. **Clone the repository:**
   ```bash
   git clone https://github.com/madebyjake/netnoise.git
   cd netnoise
   ```

2. **Install netnoise:**
   ```bash
   sudo chmod +x install.sh
   sudo ./install.sh
   ```

3. **Configure targets:**
   ```bash
   sudo nano /opt/netnoise/netnoise.conf
   ```

4. **Start monitoring:**
   ```bash
   sudo systemctl start netnoise.timer
   ```

### ⚠️ Security Reminder

**Always review scripts before running with root/sudo privileges!**

## Upgrading NetNoise

### Automatic Upgrade (Recommended)

The easiest way to upgrade netnoise is to use the built-in upgrade functionality:

```bash
# Stop the service
sudo systemctl stop netnoise.timer
sudo systemctl stop netnoise.service

# Navigate to your netnoise directory
cd /path/to/netnoise

# Pull the latest changes
git pull origin main

# Reinstall with the new version
sudo ./install.sh

# Start the service
sudo systemctl start netnoise.timer
```

### Manual Upgrade

If you prefer to upgrade manually or need more control:

1. **Backup your configuration:**
   ```bash
   sudo cp /opt/netnoise/netnoise.conf /opt/netnoise/netnoise.conf.backup
   ```

2. **Stop the service:**
   ```bash
   sudo systemctl stop netnoise.timer
   sudo systemctl stop netnoise.service
   ```

3. **Update the code:**
   ```bash
   cd /path/to/netnoise
   git pull origin main
   ```

4. **Reinstall:**
   ```bash
   sudo ./install.sh
   ```

5. **Restore your configuration (if needed):**
   ```bash
   sudo cp /opt/netnoise/netnoise.conf.backup /opt/netnoise/netnoise.conf
   ```

6. **Start the service:**
   ```bash
   sudo systemctl start netnoise.timer
   ```

### Upgrade Verification

After upgrading, verify everything is working correctly:

```bash
# Check service status
sudo systemctl status netnoise.timer
sudo systemctl status netnoise.service

# Test configuration
sudo /opt/netnoise/netnoise.sh --check

# Run a manual test
sudo /opt/netnoise/netnoise.sh

# Check logs
sudo journalctl -u netnoise.service -f
```

### Configuration Migration

When upgrading, your existing configuration will be preserved. However, new features may require configuration updates:

- **New targets**: The default configuration may include new monitoring targets
- **New settings**: Additional configuration options may be available
- **Deprecated options**: Some old configuration options may be deprecated

Check the project's release notes for detailed upgrade information and breaking changes.

### Rollback

If you need to rollback to a previous version:

```bash
# Stop the service
sudo systemctl stop netnoise.timer
sudo systemctl stop netnoise.service

# Checkout the previous version
cd /path/to/netnoise
git checkout <previous-version-tag>

# Reinstall
sudo ./install.sh

# Start the service
sudo systemctl start netnoise.timer
```

## Configuration

Edit `/opt/netnoise/netnoise.conf` to configure monitoring:

```bash
# Monitoring targets
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

# Timer settings - Service scheduling
TIMER_INTERVAL="hourly"         # How often to run tests
# Options: "minutely", "hourly", "daily", "weekly", "monthly"
# Or custom: "*-*-* *:00:00" (every hour), "*-*-* *:*/15:00" (every 15 minutes)
# Or specific: "Mon *-*-* 09:00:00" (every Monday at 9 AM)

# Log retention settings - Log management
LOG_RETENTION_DAYS=30           # Days to retain log files
```

### DNS Testing Configuration

DNS resolution testing can be configured with the following settings:

- **`DNS_ENABLED`**: Enable/disable DNS testing (default: `true`)
- **`DNS_TIMEOUT`**: DNS query timeout in seconds (default: `5`, range: 1-60)

DNS testing uses `dig` (preferred) or `nslookup` as fallback. The test measures:
- DNS resolution time
- IP addresses returned
- Success/failure status

### Bandwidth Testing Configuration

Bandwidth testing can be configured with the following settings:

- **`BANDWIDTH_ENABLED`**: Enable/disable bandwidth testing (default: `false`)
- **`BANDWIDTH_TIMEOUT`**: Test timeout in seconds (default: `30`, range: 5-300)
- **`BANDWIDTH_TEST_UPLOAD`**: Enable upload speed testing (default: `false`)

Bandwidth testing uses `curl` (preferred) or `wget` as fallback. The test measures:
- Download speed in Mbps
- Upload speed in Mbps (if enabled)
- Test duration and success/failure status

**Note**: Bandwidth testing is disabled by default as it can consume significant bandwidth and time.

### Port Scanning Configuration

Port scanning can be configured with the following settings:

- **`PORT_SCAN_ENABLED`**: Enable/disable port scanning (default: `false`)
- **`PORT_SCAN_TIMEOUT`**: Connection timeout per port in seconds (default: `5`, range: 1-30)
- **`PORT_SCAN_PORTS`**: Comma-separated list of ports to scan (default: `"22,80,443,25,53,110,143,993,995"`)

Port scanning uses `nc` (netcat) as the preferred method or `/dev/tcp` as fallback. The test measures:
- Open ports on the target host
- Connection success/failure for each port
- Total scan duration and statistics

**Common Ports:**
- **22**: SSH
- **80**: HTTP
- **443**: HTTPS
- **25**: SMTP
- **53**: DNS
- **110**: POP3
- **143**: IMAP
- **993**: IMAPS
- **995**: POP3S

**Note**: Port scanning is disabled by default as it can be seen as intrusive by some network administrators.

### MTU Discovery Configuration

MTU discovery can be configured with the following settings:

- **`MTU_ENABLED`**: Enable/disable MTU discovery (default: `false`)
- **`MTU_TIMEOUT`**: Per-test timeout in seconds (default: `5`, range: 1-30)
- **`MTU_MIN`**: Minimum MTU to test in bytes (default: `576`, range: 68-9000)
- **`MTU_MAX`**: Maximum MTU to test in bytes (default: `1500`, range: 68-9000)
- **`MTU_STEP`**: Step size for binary search in bytes (default: `10`, range: 1-100)

MTU discovery uses `ping -M do` (Don't Fragment) with binary search algorithm. The test measures:
- Optimal MTU size for the network path
- Number of tests performed during discovery
- Total discovery time and success/failure status

**How it works:**
1. Uses binary search between MTU_MIN and MTU_MAX
2. Tests each MTU size with `ping -M do -s <payload_size>`
3. Finds the largest MTU that doesn't require fragmentation
4. Reports the optimal MTU size for the network path

**Note**: MTU discovery is disabled by default as it can be time-consuming and may generate significant network traffic.

### Timer Configuration

The monitoring interval is configurable via the `TIMER_INTERVAL` setting:

- **Predefined intervals**: `minutely`, `hourly`, `daily`, `weekly`, `monthly`
- **Custom intervals**: Use systemd calendar expressions
  - `"*-*-* *:00:00"` - Every hour
  - `"*-*-* *:*/15:00"` - Every 15 minutes
  - `"*-*-* 09:00:00"` - Every day at 9 AM

After changing the timer interval, regenerate the timer:
```bash
make regenerate
```

## Usage

### Service Management

```bash
# Start/stop/restart monitoring
sudo systemctl start netnoise.timer
sudo systemctl stop netnoise.timer
sudo systemctl restart netnoise.timer

# Check status
sudo systemctl status netnoise.timer

# View logs
sudo journalctl -u netnoise.service -f
```

### Enabling Bandwidth Testing

To enable bandwidth testing, edit the configuration file:

```bash
# Edit configuration
sudo nano /opt/netnoise/netnoise.conf

# Enable bandwidth testing
BANDWIDTH_ENABLED=true
BANDWIDTH_TIMEOUT=30
BANDWIDTH_TEST_UPLOAD=false  # Optional: enable upload testing

# Restart service to apply changes
sudo systemctl restart netnoise.timer
```

### Enabling Port Scanning

To enable port scanning, edit the configuration file:

```bash
# Edit configuration
sudo nano /opt/netnoise/netnoise.conf

# Enable port scanning
PORT_SCAN_ENABLED=true
PORT_SCAN_TIMEOUT=5
PORT_SCAN_PORTS="22,80,443,25,53"  # Customize ports as needed

# Restart service to apply changes
sudo systemctl restart netnoise.timer
```

### Enabling MTU Discovery

To enable MTU discovery, edit the configuration file:

```bash
# Edit configuration
sudo nano /opt/netnoise/netnoise.conf

# Enable MTU discovery
MTU_ENABLED=true
MTU_TIMEOUT=5
MTU_MIN=576
MTU_MAX=1500
MTU_STEP=10

# Restart service to apply changes
sudo systemctl restart netnoise.timer
```


### Advanced Features

**Configuration Validation:**
```bash
make check  # Validate configuration
```

**Performance Monitoring:**
- Operation timing and resource usage tracking
- Performance logs: `logs/netnoise-performance-YYYYMMDD.log`

**Health Check:**
```bash
make health  # Show health status
```
Health data is stored in `/opt/netnoise/health.json` for monitoring integration.

### Viewing Results

```bash
# View logs
make logs

# View JSON results
sudo cat /opt/netnoise/results/netnoise-results-$(date +%Y%m%d).json | jq

# View specific target results
sudo cat /opt/netnoise/results/netnoise-results-$(date +%Y%m%d).json | jq '.[] | select(.target == "google.com")'

# View bandwidth test results only
sudo cat /opt/netnoise/results/netnoise-results-$(date +%Y%m%d).json | jq '.[] | select(.target == "google.com") | .bandwidth'

# View port scanning results only
sudo cat /opt/netnoise/results/netnoise-results-$(date +%Y%m%d).json | jq '.[] | select(.target == "google.com") | .ports'

# View MTU discovery results only
sudo cat /opt/netnoise/results/netnoise-results-$(date +%Y%m%d).json | jq '.[] | select(.target == "google.com") | .mtu'
```

## Alerting

Configure alerts in `netnoise.conf`:

- **Email alerts**: Set `ALERT_EMAIL` (requires `mail` command)
- **Webhook alerts**: Set `ALERT_WEBHOOK` for HTTP POST endpoints (Slack, Discord, etc.)

## Security Considerations

- **Always review scripts before running with sudo/root privileges**
- Service runs as root to access network tools (ping, traceroute)
- Logs may contain sensitive network information
- Keep installation directory (`/opt/netnoise`) secure
- Use strong authentication for alert webhooks

## Troubleshooting

**Missing Dependencies:**
```bash
# Ubuntu/Debian
sudo apt install traceroute curl jq bc dnsutils

# CentOS/RHEL
sudo dnf install traceroute curl jq bc bind-utils

# openSUSE
sudo zypper install traceroute curl jq bc bind-utils

# macOS
brew install traceroute curl jq bc
```

**Service Issues:**
```bash
# Check status
sudo systemctl status netnoise.timer

# Check logs
sudo journalctl -u netnoise.service -n 50

# Test manually
sudo /opt/netnoise/netnoise.sh

# Debug mode
sudo bash -x /opt/netnoise/netnoise.sh
```

## Uninstallation

```bash
sudo ./install.sh uninstall
```

This removes the systemd service, installation directory, and all logs.