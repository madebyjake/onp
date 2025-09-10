# OpenNetProbe (ONP) Makefile
# Provides commands for managing ONP

.PHONY: help install uninstall test clean status start stop restart logs regenerate check health version

# Default target
help:
	@echo "OpenNetProbe (ONP) Management Commands"
	@echo "====================================="
	@echo ""
	@echo "Available targets:"
	@echo "  install     - Install ONP systemd service"
	@echo "  uninstall   - Remove ONP completely"
	@echo "  test        - Run test suite"
	@echo "  clean       - Clean up logs and results"
	@echo "  status      - Show service status"
	@echo "  start       - Start monitoring"
	@echo "  stop        - Stop monitoring"
	@echo "  restart     - Restart monitoring"
	@echo "  regenerate  - Regenerate timer after config changes"
	@echo "  check       - Check configuration"
	@echo "  health      - Show health status"
	@echo "  logs        - View recent logs"
	@echo "  config      - Edit configuration"
	@echo "  manual      - Run manual test"
	@echo "  version     - Show version information"
	@echo ""

# Install ONP
install:
	@echo "Installing ONP..."
	sudo ./install.sh

# Uninstall ONP
uninstall:
	@echo "Uninstalling ONP..."
	sudo ./install.sh uninstall

# Run test suite
test:
	@echo "Running ONP test suite..."
	./test.sh

# Clean up old logs and results
clean:
	@echo "Cleaning up old logs and results..."
	@if [ -d "/opt/onp/logs" ]; then \
		sudo find /opt/onp/logs -name "*.log" -mtime +7 -delete; \
		echo "Cleaned old log files"; \
	fi
	@if [ -d "/opt/onp/results" ]; then \
		sudo find /opt/onp/results -name "*.json" -mtime +7 -delete; \
		sudo find /opt/onp/results -name "traceroute-*.txt" -mtime +7 -delete; \
		echo "Cleaned old result files"; \
	fi

# Show service status
status:
	@echo "OpenNetProbe (ONP) Service Status"
	@echo "================================="
	@systemctl status onp.timer --no-pager || true
	@echo ""
	@echo "Recent Logs:"
	@journalctl -u onp.service -n 10 --no-pager || true

# Start monitoring
start:
	@echo "Starting ONP monitoring..."
	sudo systemctl start onp.timer
	@echo "Monitoring started. Use 'make status' to check status."

# Stop monitoring
stop:
	@echo "Stopping ONP monitoring..."
	sudo systemctl stop onp.timer
	@echo "Monitoring stopped."

# Restart monitoring
restart:
	@echo "Restarting ONP monitoring..."
	sudo systemctl restart onp.timer
	@echo "Monitoring restarted. Use 'make status' to check status."

# Regenerate timer after config changes
regenerate:
	@echo "Regenerating ONP timer..."
	sudo ./install.sh regenerate
	@echo "Timer regenerated. Use 'make status' to check status."

# Check configuration
check:
	@echo "Checking ONP configuration..."
	sudo ./install.sh check
	@echo "Configuration check completed."

# Show health status
health:
	@echo "OpenNetProbe (ONP) Health Status"
	@echo "================================"
	@if [ -f "/opt/onp/health.json" ]; then \
		cat /opt/onp/health.json | jq . 2>/dev/null || cat /opt/onp/health.json; \
	else \
		echo "Health file not found. Run 'make manual' to generate health status."; \
	fi

# Show version information
version:
	@echo "OpenNetProbe (ONP) Version Information"
	@echo "======================================="
	@./onp.sh --version

# View logs
logs:
	@echo "OpenNetProbe (ONP) Logs (last 50 lines)"
	@echo "======================================="
	@journalctl -u onp.service -n 50 --no-pager || true

# Edit configuration
config:
	@echo "Editing ONP configuration..."
	@if [ -f "/opt/onp/onp.conf" ]; then \
		sudo nano /opt/onp/onp.conf; \
	else \
		echo "Configuration file not found. Run 'make install' first."; \
	fi

# Run manual test
manual:
	@echo "Running manual ONP test..."
	sudo /opt/onp/onp.sh

# Show installation info
info:
	@echo "OpenNetProbe (ONP) Installation Information"
	@echo "============================================"
	@echo "Installation directory: /opt/onp"
	@echo "Configuration file: /opt/onp/onp.conf"
	@echo "Log directory: /opt/onp/logs"
	@echo "Results directory: /opt/onp/results"
	@echo ""
	@echo "Service files:"
	@echo "  Service: /etc/systemd/system/onp.service"
	@echo "  Timer:   /etc/systemd/system/onp.timer"
	@echo ""
	@echo "Useful commands:"
	@echo "  View logs:     journalctl -u onp.service -f"
	@echo "  Check status:  systemctl status onp.timer"
	@echo "  Manual run:    sudo /opt/onp/onp.sh"
