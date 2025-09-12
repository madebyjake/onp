# netnoise Makefile
# Provides commands for managing netnoise

.PHONY: help install install-dev uninstall upgrade upgrade-dev test clean status start stop restart logs regenerate check health version config manual info lint format validate deps setup dev

# Default target
help:
	@echo "NetNoise Management Commands"
	@echo "====================================="
	@echo ""
	@echo "Available targets:"
	@echo "  install     - Install netnoise systemd service"
	@echo "  install-dev - Install netnoise for development (local, no systemd)"
	@echo "  uninstall   - Remove netnoise completely"
	@echo "  upgrade     - Upgrade netnoise to latest version"
	@echo "  upgrade-dev - Upgrade netnoise for development"
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
	@echo "  info        - Show installation information"
	@echo "  lint        - Run ShellCheck on all scripts"
	@echo "  format      - Format and validate scripts"
	@echo "  validate    - Validate all configuration files"
	@echo "  deps        - Check and install dependencies"
	@echo "  setup       - Setup development environment"
	@echo "  dev         - Run development mode (local testing)"
	@echo ""

# Install netnoise
install:
	@echo "Installing netnoise..."
	sudo ./install.sh

# Install netnoise for development (local, no systemd)
install-dev:
	@echo "Installing netnoise for development..."
	@echo "Setting up development environment..."
	@mkdir -p logs results packet_loss
	@chmod +x netnoise.sh install.sh test.sh
	@chmod +x modules/*.sh 2>/dev/null || true
	@echo "Creating development configuration..."
	@if [ ! -f "netnoise.conf" ]; then \
		echo "Configuration file not found. Please create netnoise.conf first."; \
		exit 1; \
	fi
	@echo "Development installation completed!"
	@echo "Run 'make dev' to test locally or './netnoise.sh' to run manually."

# Uninstall netnoise
uninstall:
	@echo "Uninstalling netnoise..."
	sudo ./install.sh uninstall

# Upgrade netnoise
upgrade:
	@echo "Upgrading netnoise..."
	@echo "Stopping netnoise services..."
	@sudo systemctl stop netnoise.timer 2>/dev/null || true
	@sudo systemctl stop netnoise.service 2>/dev/null || true
	@echo "Backing up current configuration..."
	@sudo cp /opt/netnoise/netnoise.conf /opt/netnoise/netnoise.conf.backup 2>/dev/null || true
	@echo "Pulling latest changes..."
	@git fetch origin
	@git merge origin/$$(git branch --show-current) --ff-only || (echo "Warning: Could not fast-forward merge. Use 'git status' to check for conflicts." && exit 1)
	@echo "Reinstalling netnoise..."
	@sudo ./install.sh
	@echo "Restoring configuration..."
	@sudo cp /opt/netnoise/netnoise.conf.backup /opt/netnoise/netnoise.conf 2>/dev/null || true
	@echo "Starting netnoise services..."
	@sudo systemctl start netnoise.timer
	@echo "Upgrade completed successfully!"
	@echo "Run 'make status' to verify everything is working."

# Upgrade netnoise for development
upgrade-dev:
	@echo "Upgrading netnoise for development..."
	@echo "Pulling latest changes..."
	@git fetch origin
	@git merge origin/$$(git branch --show-current) --ff-only || (echo "Warning: Could not fast-forward merge. Use 'git status' to check for conflicts." && exit 1)
	@echo "Setting up development environment..."
	@mkdir -p logs results packet_loss
	@chmod +x netnoise.sh install.sh test.sh
	@chmod +x modules/*.sh 2>/dev/null || true
	@echo "Running development validation..."
	@make format
	@make validate
	@echo "Development upgrade completed!"
	@echo "Run 'make dev' to test locally or './netnoise.sh' to run manually."

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

# Run ShellCheck on all scripts
lint:
	@echo "Running ShellCheck on all scripts..."
	@if command -v shellcheck >/dev/null 2>&1; then \
		echo "Checking main scripts..."; \
		shellcheck netnoise.sh install.sh test.sh || true; \
		echo "Checking modules..."; \
		for module in modules/*.sh; do \
			if [ -f "$$module" ]; then \
				echo "Checking $$module..."; \
				shellcheck "$$module" || true; \
			fi; \
		done; \
		echo "ShellCheck completed"; \
	else \
		echo "ShellCheck not found. Install with: sudo apt-get install shellcheck"; \
		echo "Or: brew install shellcheck"; \
	fi

# Format and validate scripts
format:
	@echo "Formatting and validating scripts..."
	@echo "Checking script syntax..."
	@bash -n netnoise.sh && echo "✓ netnoise.sh syntax OK" || echo "✗ netnoise.sh syntax error"
	@bash -n install.sh && echo "✓ install.sh syntax OK" || echo "✗ install.sh syntax error"
	@bash -n test.sh && echo "✓ test.sh syntax OK" || echo "✗ test.sh syntax error"
	@echo "Checking module syntax..."
	@for module in modules/*.sh; do \
		if [ -f "$$module" ]; then \
			if bash -n "$$module"; then \
				echo "✓ $$module syntax OK"; \
			else \
				echo "✗ $$module syntax error"; \
			fi; \
		fi; \
	done
	@echo "Format validation completed"

# Validate all configuration files
validate:
	@echo "Validating configuration files..."
	@echo "Checking netnoise.conf..."
	@if [ -f "netnoise.conf" ]; then \
		if bash -c "source netnoise.conf && echo 'Configuration loaded successfully'"; then \
			echo "✓ netnoise.conf is valid"; \
		else \
			echo "✗ netnoise.conf has errors"; \
		fi; \
	else \
		echo "✗ netnoise.conf not found"; \
	fi
	@echo "Checking systemd files..."
	@if [ -f "netnoise.service" ]; then \
		if systemd-analyze verify netnoise.service >/dev/null 2>&1; then \
			echo "✓ netnoise.service is valid"; \
		else \
			echo "✗ netnoise.service has issues (may need systemd context)"; \
		fi; \
	else \
		echo "✗ netnoise.service not found"; \
	fi
	@if [ -f "netnoise.timer" ]; then \
		if systemd-analyze verify netnoise.timer >/dev/null 2>&1; then \
			echo "✓ netnoise.timer is valid"; \
		else \
			echo "✗ netnoise.timer has issues (may need systemd context)"; \
		fi; \
	else \
		echo "✗ netnoise.timer not found"; \
	fi
	@echo "Configuration validation completed"

# Check and install dependencies
deps:
	@echo "Checking dependencies..."
	@echo "Required tools:"
	@for tool in ping traceroute curl jq bc; do \
		if command -v "$$tool" >/dev/null 2>&1; then \
			echo "✓ $$tool is installed"; \
		else \
			echo "✗ $$tool is missing"; \
		fi; \
	done
	@echo "DNS tools:"
	@if command -v dig >/dev/null 2>&1; then \
		echo "✓ dig is installed"; \
	else \
		echo "✗ dig is missing"; \
	fi
	@if command -v nslookup >/dev/null 2>&1; then \
		echo "✓ nslookup is installed"; \
	else \
		echo "✗ nslookup is missing"; \
	fi
	@echo "Optional tools:"
	@for tool in shellcheck nc wget; do \
		if command -v "$$tool" >/dev/null 2>&1; then \
			echo "✓ $$tool is installed"; \
		else \
			echo "? $$tool is not installed (optional)"; \
		fi; \
	done
	@echo "Dependency check completed"

# Setup development environment
setup:
	@echo "Setting up development environment..."
	@echo "Creating necessary directories..."
	@mkdir -p logs results packet_loss
	@echo "Setting up permissions..."
	@chmod +x netnoise.sh install.sh test.sh
	@chmod +x modules/*.sh 2>/dev/null || true
	@echo "Running initial validation..."
	@make format
	@make validate
	@echo "Development environment setup completed"

# Run development mode (local testing)
dev:
	@echo "Running netnoise in development mode..."
	@echo "This will run locally without systemd..."
	@echo "======================================="
	@./netnoise.sh --check
	@echo ""
	@echo "Running full test suite..."
	@make test
	@echo ""
	@echo "Development mode completed"
