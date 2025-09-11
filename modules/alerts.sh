#!/bin/bash

# netnoise - Alerting Module
# Handles alert notifications via email and webhook

# Ensure this module is being sourced, not executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Error: This module must be sourced, not executed directly" >&2
    exit 1
fi

# Send alert if configured
send_alert() {
    local message="$1"
    
    if [ "$ALERT_ON_FAILURE" = true ]; then
        log "WARN" "Alert: $message"
        
        # Email alert (if configured)
        if [ -n "${ALERT_EMAIL:-}" ] && command -v mail &> /dev/null; then
            echo "$message" | mail -s "netnoise Alert" "$ALERT_EMAIL"
            log "INFO" "Alert email sent to $ALERT_EMAIL"
        fi
        
        # Webhook alert (if configured)
        if [ -n "${ALERT_WEBHOOK:-}" ]; then
            # Properly escape the message for JSON to prevent injection
            local escaped_message
            escaped_message=$(printf '%s\n' "$message" | sed 's/\\/\\\\/g; s/"/\\"/g; s/`/\\`/g; s/\$/\\$/g')
            
            # Validate webhook URL format
            if [[ "$ALERT_WEBHOOK" =~ ^https?://[a-zA-Z0-9.-]+(:[0-9]+)?(/.*)?$ ]]; then
                curl -X POST -H "Content-Type: application/json" \
                     -d "{\"text\":\"$escaped_message\"}" \
                     --max-time 30 \
                     "$ALERT_WEBHOOK" &> /dev/null || log "WARN" "Failed to send webhook alert"
            else
                log "WARN" "Invalid webhook URL format: $ALERT_WEBHOOK"
            fi
        fi
    fi
}
