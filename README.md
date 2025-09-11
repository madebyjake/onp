# NetNoise

NetNoise is a network troubleshooting utility that performs active connectivity testing across multiple protocols. It conducts DNS resolution, ping, bandwidth, port scanning, HTTP/HTTPS, and traceroute tests against configurable targets to help diagnose network issues and monitor connection health.

## Features

- Multi-protocol testing (DNS resolution, ping, bandwidth, port scanning, HTTP/HTTPS, traceroute)
- Configurable target lists and test parameters
- Structured logging with JSON output
- Email and webhook alerting
- Systemd service integration
- Automated scheduling and log management

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

## Configuration

Edit `/opt/netnoise/netnoise.conf` to configure monitoring:

```bash
# Add targets to monitor
TARGETS=(
    "amazon.com"
    "apple.com"
    "cloudflare.com"
    "discord.com"
    "espn.com"
    "facebook.com"
    "github.com"
    "google.com"
    "microsoft.com"
    "netflix.com"
    "reddit.com"
    "twitch.tv"
    "wikipedia.org"
    "youtube.com"
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
ALERT_EMAIL="admin@example.com"
ALERT_WEBHOOK="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"

# Timer settings
TIMER_INTERVAL="hourly"
# Options: "minutely", "hourly", "daily", "weekly", "monthly"
# Or custom: "*-*-* *:00:00" (every hour), "*-*-* *:*/15:00" (every 15 minutes)
# Or specific: "Mon *-*-* 09:00:00" (every Monday at 9 AM)

# Log retention (days)
LOG_RETENTION_DAYS=30
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

### Makefile Commands

```bash
make install     # Install netnoise
make test        # Run test suite
make status      # Check service status
make start       # Start monitoring
make stop        # Stop monitoring
make restart     # Restart monitoring
make logs        # View recent logs
make config      # Edit configuration
make check       # Validate configuration
make health      # Show health status
make version     # Show version information
make clean       # Clean old logs
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
sudo apt-get install traceroute curl jq bc dnsutils

# CentOS/RHEL
sudo yum install traceroute curl jq bc bind-utils

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