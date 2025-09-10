# OpenNetProbe (ONP)

A network monitoring utility that performs connectivity tests, traceroutes, and HTTP checks on a configurable list of targets. Runs as a systemd service with configurable scheduling to detect connection errors.

## Features

- **Multi-protocol Testing**: Performs ping, HTTP/HTTPS, and traceroute tests
- **Configurable Targets**: Supports hostnames, IP addresses, and URLs
- **Logging**: Generates logs with timestamps and color-coded output
- **JSON Results**: Outputs machine-readable results for monitoring system integration
- **Alert System**: Sends email and webhook notifications on failures
- **Systemd Integration**: Uses systemd timer for scheduling
- **Resource Management**: Configurable timeouts and resource limits
- **Log Rotation**: Automatically cleans up old logs and results
- **Configuration Validation**: Comprehensive config validation with detailed error reporting
- **Performance Monitoring**: Built-in performance tracking and resource monitoring
- **Health Check Endpoint**: JSON health status file for monitoring integration

## Quick Start

### Prerequisites

- Linux system with systemd
- Root or sudo access
- Required tools: `ping`, `traceroute`, `curl`, `jq`, `bc`

### Installation

1. **Clone the repository:**
   ```bash
   git clone https://github.com/madebyjake/onp.git
   cd onp
   ```

2. **Install OpenNetProbe:**
   ```bash
   sudo chmod +x install.sh
   sudo ./install.sh
   ```

3. **Configure targets:**
   ```bash
   sudo nano /opt/onp/onp.conf
   ```

4. **Start monitoring:**
   ```bash
   sudo systemctl start onp.timer
   ```

### ⚠️ Security Reminder

**Always review scripts before running with root/sudo privileges!**

## Configuration

Edit `/opt/onp/onp.conf` to configure monitoring:

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

# HTTP/HTTPS test settings
HTTP_TIMEOUT=10
HTTP_USER_AGENT="OpenNetProbe (ONP)/1.0"

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
sudo systemctl start onp.timer
sudo systemctl stop onp.timer
sudo systemctl restart onp.timer

# Check status
sudo systemctl status onp.timer

# View logs
sudo journalctl -u onp.service -f
```

### Makefile Commands

```bash
make install     # Install OpenNetProbe
make test        # Run test suite
make status      # Check service status
make start       # Start monitoring
make stop        # Stop monitoring
make restart     # Restart monitoring
make logs        # View recent logs
make config      # Edit configuration
make check    # Validate configuration
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
- Performance logs: `logs/onp-performance-YYYYMMDD.log`

**Health Check:**
```bash
make health  # Show health status
```
Health data is stored in `/opt/onp/health.json` for monitoring integration.

### Viewing Results

```bash
# View logs
make logs

# View JSON results
sudo cat /opt/onp/results/onp-results-$(date +%Y%m%d).json | jq

# View specific target results
sudo cat /opt/onp/results/onp-results-$(date +%Y%m%d).json | jq '.[] | select(.target == "google.com")'
```

## Alerting

Configure alerts in `onp.conf`:

- **Email alerts**: Set `ALERT_EMAIL` (requires `mail` command)
- **Webhook alerts**: Set `ALERT_WEBHOOK` for HTTP POST endpoints (Slack, Discord, etc.)

## Security Considerations

- **Always review scripts before running with sudo/root privileges**
- Service runs as root to access network tools (ping, traceroute)
- Logs may contain sensitive network information
- Keep installation directory (`/opt/onp`) secure
- Use strong authentication for alert webhooks

## Troubleshooting

**Missing Dependencies:**
```bash
# Ubuntu/Debian
sudo apt-get install traceroute curl jq bc

# CentOS/RHEL
sudo yum install traceroute curl jq bc

# macOS
brew install traceroute curl jq bc
```

**Service Issues:**
```bash
# Check status
sudo systemctl status onp.timer

# Check logs
sudo journalctl -u onp.service -n 50

# Test manually
sudo /opt/onp/onp.sh

# Debug mode
sudo bash -x /opt/onp/onp.sh
```

## Uninstallation

```bash
sudo ./install.sh uninstall
```

This removes the systemd service, installation directory, and all logs.