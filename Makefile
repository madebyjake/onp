# netnoise Makefile
# Provides commands for managing netnoise

.PHONY: help install uninstall test clean status start stop restart logs regenerate check health version

# Default target
help:
	@echo "NetNoise Management Commands"
	@echo "====================================="
	@echo ""
	@echo "Available targets:"
	@echo "  install     - Install netnoise systemd service"
	@echo "  uninstall   - Remove netnoise completely"
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

# Install netnoise
install:
	@echo "Installing netnoise..."
	sudo ./install.sh

# Uninstall netnoise
uninstall:
	@echo "Uninstalling netnoise..."
	sudo ./install.sh uninstall

# Run test suite
test:
	@echo "Running netnoise test suite..."
	./test.sh

# Clean up old logs and results
clean:
	@echo "Cleaning up old logs and results..."
	@if [ -d "/opt/netnoise/logs" ]; then \
		sudo find /opt/netnoise/logs -name "*.log" -mtime +7 -delete; \
		echo "Cleaned old log files"; \
	fi
	@if [ -d "/opt/netnoise/results" ]; then \
		sudo find /opt/netnoise/results -name "*.json" -mtime +7 -delete; \
		sudo find /opt/netnoise/results -name "traceroute-*.txt" -mtime +7 -delete; \
		echo "Cleaned old result files"; \
	fi

# Show service status
status:
	@echo "NetNoise Service Status"
	@echo "================================="
	@systemctl status netnoise.timer --no-pager || true
	@echo ""
	@echo "Recent Logs:"
	@journalctl -u netnoise.service -n 10 --no-pager || true

# Start monitoring
start:
	@echo "Starting netnoise monitoring..."
	sudo systemctl start netnoise.timer
	@echo "Monitoring started. Use 'make status' to check status."

# Stop monitoring
stop:
	@echo "Stopping netnoise monitoring..."
	sudo systemctl stop netnoise.timer
	@echo "Monitoring stopped."

# Restart monitoring
restart:
	@echo "Restarting netnoise monitoring..."
	sudo systemctl restart netnoise.timer
	@echo "Monitoring restarted. Use 'make status' to check status."

# Regenerate timer after config changes
regenerate:
	@echo "Regenerating netnoise timer..."
	sudo ./install.sh regenerate
	@echo "Timer regenerated. Use 'make status' to check status."

# Check configuration
check:
	@echo "Checking netnoise configuration..."
	sudo ./install.sh check
	@echo "Configuration check completed."

# Show health status
health:
	@echo "NetNoise Health Status"
	@echo "================================"
	@if [ -f "/opt/netnoise/health.json" ]; then \
		cat /opt/netnoise/health.json | jq . 2>/dev/null || cat /opt/netnoise/health.json; \
	else \
		echo "Health file not found. Run 'make manual' to generate health status."; \
	fi

# Show version information
version:
	@echo "NetNoise Version Information"
	@echo "======================================="
	@./netnoise.sh --version

# View logs
logs:
	@echo "NetNoise Logs (last 50 lines)"
	@echo "======================================="
	@journalctl -u netnoise.service -n 50 --no-pager || true

# Edit configuration
config:
	@echo "Editing netnoise configuration..."
	@if [ -f "/opt/netnoise/netnoise.conf" ]; then \
		sudo nano /opt/netnoise/netnoise.conf; \
	else \
		echo "Configuration file not found. Run 'make install' first."; \
	fi

# Run manual test
manual:
	@echo "Running manual netnoise test..."
	sudo /opt/netnoise/netnoise.sh

# Show installation info
info:
	@echo "NetNoise Installation Information"
	@echo "============================================"
	@echo "Installation directory: /opt/netnoise"
	@echo "Configuration file: /opt/netnoise/netnoise.conf"
	@echo "Log directory: /opt/netnoise/logs"
	@echo "Results directory: /opt/netnoise/results"
	@echo ""
	@echo "Service files:"
	@echo "  Service: /etc/systemd/system/netnoise.service"
	@echo "  Timer:   /etc/systemd/system/netnoise.timer"
	@echo ""
	@echo "Useful commands:"
	@echo "  View logs:     journalctl -u netnoise.service -f"
	@echo "  Check status:  systemctl status netnoise.timer"
	@echo "  Manual run:    sudo /opt/netnoise/netnoise.sh"
