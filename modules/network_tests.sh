#!/bin/bash

# netnoise - Network Testing Module
# Contains all network testing functions: ping, DNS, bandwidth, ports, MTU, HTTP, traceroute

# Ensure this module is being sourced, not executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Error: This module must be sourced, not executed directly" >&2
    exit 1
fi

# Test connectivity with ping
test_ping() {
    local target="$1"
    local result_file="$2"
    
    log "INFO" "Testing ping connectivity to $target"
    
    # Extract hostname from URL if needed and validate
    local hostname="$target"
    if [[ "$target" =~ ^https?:// ]]; then
        hostname=$(echo "$target" | sed 's|^https\?://||' | cut -d'/' -f1)
    fi
    
    # Validate hostname to prevent command injection
    if [[ ! "$hostname" =~ ^[a-zA-Z0-9.-]+$ ]] || [[ "$hostname" =~ ^\. ]] || [[ "$hostname" =~ \.$ ]] || [[ "$hostname" =~ \.\. ]]; then
        echo "  \"ping\": {\"status\": \"failed\", \"error\": \"invalid hostname format\"}" >> "$result_file"
        log "ERROR" "Invalid hostname format: $hostname"
        return 1
    fi
    
    if ping -c "$PING_COUNT" -W "$PING_TIMEOUT" "$hostname" &> /dev/null; then
        local ping_time=$(ping -c 1 -W "$PING_TIMEOUT" "$hostname" 2>/dev/null | grep 'time=' | sed 's/.*time=\([0-9.]*\).*/\1/')
        echo "  \"ping\": {\"status\": \"success\", \"time_ms\": \"$ping_time\"}" >> "$result_file"
        log "SUCCESS" "Ping to $hostname successful (${ping_time}ms)"
        return 0
    else
        echo "  \"ping\": {\"status\": \"failed\", \"error\": \"timeout or unreachable\"}" >> "$result_file"
        log "ERROR" "Ping to $hostname failed"
        return 1
    fi
}

# Test DNS resolution
test_dns() {
    local target="$1"
    local result_file="$2"
    
    log "INFO" "Testing DNS resolution for $target"
    
    # Extract hostname from URL if needed
    local hostname="$target"
    if [[ "$target" =~ ^https?:// ]]; then
        hostname=$(echo "$target" | sed 's|^https\?://||' | cut -d'/' -f1)
    fi
    
    # Validate hostname to prevent command injection
    if [[ ! "$hostname" =~ ^[a-zA-Z0-9.-]+$ ]] || [[ "$hostname" =~ ^\. ]] || [[ "$hostname" =~ \.$ ]] || [[ "$hostname" =~ \.\. ]]; then
        echo "  \"dns\": {\"status\": \"failed\", \"error\": \"invalid hostname format\"}" >> "$result_file"
        log "ERROR" "Invalid hostname format: $hostname"
        return 1
    fi
    
    local dns_start_time=$(date +%s.%N)
    local dns_result=""
    local dns_error=""
    local dns_time_ms=""
    local dns_records=""
    
    # Try dig first (more reliable and detailed)
    if command -v dig &> /dev/null; then
        if dns_result=$(timeout "$DNS_TIMEOUT" dig +short +time="$DNS_TIMEOUT" +tries=1 "$hostname" A 2>&1); then
            if [ -n "$dns_result" ] && [ "$dns_result" != "" ]; then
                # Extract IP addresses from dig output with proper validation
                local ip_addresses=()
                while IFS= read -r line; do
                    if [[ "$line" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
                        # Validate each octet is <= 255
                        local valid_ip=true
                        IFS='.' read -ra ADDR <<< "$line"
                        for octet in "${ADDR[@]}"; do
                            if [ "$octet" -gt 255 ] || [ "$octet" -lt 0 ]; then
                                valid_ip=false
                                break
                            fi
                        done
                        if [ "$valid_ip" = true ]; then
                            ip_addresses+=("$line")
                        fi
                    fi
                done <<< "$dns_result"
                if [ ${#ip_addresses[@]} -gt 0 ]; then
                    dns_records=$(printf '%s,' "${ip_addresses[@]}" | sed 's/,$//')
                    local dns_end_time=$(date +%s.%N)
                    dns_time_ms=$(echo "($dns_end_time - $dns_start_time) * 1000" | bc -l 2>/dev/null | cut -d. -f1 || echo "0")
                    echo "  \"dns\": {\"status\": \"success\", \"time_ms\": \"$dns_time_ms\", \"records\": \"$dns_records\", \"method\": \"dig\"}" >> "$result_file"
                    log "SUCCESS" "DNS resolution for $hostname successful (${dns_time_ms}ms, IPs: $dns_records)"
                    return 0
                else
                    dns_error="No valid IP addresses found in DNS response"
                fi
            else
                dns_error="Empty DNS response"
            fi
        else
            dns_error="dig command failed"
        fi
    # Fallback to nslookup if dig is not available
    elif command -v nslookup &> /dev/null; then
        if dns_result=$(timeout "$DNS_TIMEOUT" nslookup "$hostname" 2>&1); then
            # Extract IP addresses from nslookup output with proper validation
            local ip_addresses=()
            while IFS= read -r line; do
                if [[ "$line" =~ Address:[[:space:]]+([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}) ]]; then
                    local ip="${BASH_REMATCH[1]}"
                    # Validate each octet is <= 255
                    local valid_ip=true
                    IFS='.' read -ra ADDR <<< "$ip"
                    for octet in "${ADDR[@]}"; do
                        if [ "$octet" -gt 255 ] || [ "$octet" -lt 0 ]; then
                            valid_ip=false
                            break
                        fi
                    done
                    if [ "$valid_ip" = true ]; then
                        ip_addresses+=("$ip")
                    fi
                fi
            done <<< "$dns_result"
            if [ ${#ip_addresses[@]} -gt 0 ]; then
                dns_records=$(printf '%s,' "${ip_addresses[@]}" | sed 's/,$//')
                local dns_end_time=$(date +%s.%N)
                dns_time_ms=$(echo "($dns_end_time - $dns_start_time) * 1000" | bc -l 2>/dev/null | cut -d. -f1 || echo "0")
                echo "  \"dns\": {\"status\": \"success\", \"time_ms\": \"$dns_time_ms\", \"records\": \"$dns_records\", \"method\": \"nslookup\"}" >> "$result_file"
                log "SUCCESS" "DNS resolution for $hostname successful (${dns_time_ms}ms, IPs: $dns_records)"
                return 0
            else
                dns_error="No valid IP addresses found in DNS response"
            fi
        else
            dns_error="nslookup command failed"
        fi
    else
        dns_error="Neither dig nor nslookup available"
    fi
    
    # If we get here, DNS resolution failed
    local dns_end_time=$(date +%s.%N)
    dns_time_ms=$(echo "($dns_end_time - $dns_start_time) * 1000" | bc -l 2>/dev/null | cut -d. -f1 || echo "0")
    echo "  \"dns\": {\"status\": \"failed\", \"time_ms\": \"$dns_time_ms\", \"error\": \"$dns_error\"}" >> "$result_file"
    log "ERROR" "DNS resolution for $hostname failed: $dns_error"
    return 1
}

# Test bandwidth (upload/download speed)
test_bandwidth() {
    local target="$1"
    local result_file="$2"
    
    log "INFO" "Testing bandwidth to $target"
    
    # Extract hostname from URL if needed
    local hostname="$target"
    local test_url="$target"
    if [[ "$target" =~ ^https?:// ]]; then
        hostname=$(echo "$target" | sed 's|^https\?://||' | cut -d'/' -f1)
        test_url="$target"
    else
        # Default to HTTPS for bandwidth testing
        test_url="https://$target"
    fi
    
    # Validate hostname to prevent command injection
    if [[ ! "$hostname" =~ ^[a-zA-Z0-9.-]+$ ]] || [[ "$hostname" =~ ^\. ]] || [[ "$hostname" =~ \.$ ]] || [[ "$hostname" =~ \.\. ]]; then
        echo "  \"bandwidth\": {\"status\": \"failed\", \"error\": \"invalid hostname format\"}" >> "$result_file"
        log "ERROR" "Invalid hostname format: $hostname"
        return 1
    fi
    
    local bandwidth_start_time=$(date +%s.%N)
    local download_speed=""
    local upload_speed=""
    local bandwidth_error=""
    local total_time=""
    
    # Test download speed
    local download_test_file="/tmp/bandwidth_download_$$"
    local download_result=""
    
    if command -v curl &> /dev/null; then
        # Use curl for download test
        if download_result=$(timeout "$BANDWIDTH_TIMEOUT" curl -s -w "\n%{speed_download}\n%{time_total}" \
            -o "$download_test_file" \
            --max-time "$BANDWIDTH_TIMEOUT" \
            --connect-timeout 10 \
            -A "$HTTP_USER_AGENT" \
            "$test_url" 2>&1); then
            
            # Parse curl output
            local speed_bytes=$(echo "$download_result" | tail -n 2 | head -n 1)
            # total_time=$(echo "$download_result" | tail -n 1)  # Currently unused
            
            # Convert bytes per second to Mbps
            if [[ "$speed_bytes" =~ ^[0-9]+$ ]] && [ "$speed_bytes" -gt 0 ]; then
                download_speed=$(echo "scale=2; $speed_bytes * 8 / 1000000" | bc -l 2>/dev/null || echo "0")
            else
                bandwidth_error="Invalid download speed data"
            fi
        else
            bandwidth_error="Download test failed"
        fi
    elif command -v wget &> /dev/null; then
        # Use wget for download test
        local wget_start_time=$(date +%s.%N)
        if download_result=$(timeout "$BANDWIDTH_TIMEOUT" wget -O "$download_test_file" \
            --timeout="$BANDWIDTH_TIMEOUT" \
            --tries=1 \
            --user-agent="$HTTP_USER_AGENT" \
            "$test_url" 2>&1); then
            
            local wget_end_time=$(date +%s.%N)
            local wget_duration=$(echo "$wget_end_time - $wget_start_time" | bc -l 2>/dev/null || echo "1")
            
            # Extract file size and calculate speed
            local file_size=$(stat -f%z "$download_test_file" 2>/dev/null || echo "0")
            if [ "$file_size" -gt 0 ] && [ "$wget_duration" -gt 0 ]; then
                download_speed=$(echo "scale=2; $file_size * 8 / $wget_duration / 1000000" | bc -l 2>/dev/null || echo "0")
            else
                bandwidth_error="Invalid download data from wget"
            fi
        else
            bandwidth_error="Download test failed with wget"
        fi
    else
        bandwidth_error="Neither curl nor wget available for bandwidth testing"
    fi
    
    # Test upload speed (if enabled and tools available)
    local upload_speed=""
    if [ "${BANDWIDTH_TEST_UPLOAD:-false}" = "true" ] && command -v curl &> /dev/null; then
        local upload_test_file="/tmp/bandwidth_upload_$$"
        
        # Create test data for upload (1MB)
        dd if=/dev/zero of="$upload_test_file" bs=1024 count=1024 2>/dev/null
        
        # Use a service that supports POST uploads for testing
        local upload_url="https://httpbin.org/post"
        
        if upload_result=$(timeout "$BANDWIDTH_TIMEOUT" curl -s -w "\n%{speed_upload}\n%{time_total}" \
            -X POST \
            -F "file=@$upload_test_file" \
            --max-time "$BANDWIDTH_TIMEOUT" \
            --connect-timeout 10 \
            -A "$HTTP_USER_AGENT" \
            "$upload_url" 2>&1); then
            
            # Parse upload speed
            local upload_speed_bytes=$(echo "$upload_result" | tail -n 2 | head -n 1)
            if [[ "$upload_speed_bytes" =~ ^[0-9]+$ ]] && [ "$upload_speed_bytes" -gt 0 ]; then
                upload_speed=$(echo "scale=2; $upload_speed_bytes * 8 / 1000000" | bc -l 2>/dev/null || echo "0")
            fi
        fi
        
        rm -f "$upload_test_file"
    fi
    
    # Clean up download test file
    rm -f "$download_test_file"
    
    # Calculate total test time
    local bandwidth_end_time=$(date +%s.%N)
    local test_duration=$(echo "($bandwidth_end_time - $bandwidth_start_time) * 1000" | bc -l 2>/dev/null | cut -d. -f1 || echo "0")
    
    # Prepare results
    if [ -n "$bandwidth_error" ]; then
        echo "  \"bandwidth\": {\"status\": \"failed\", \"time_ms\": \"$test_duration\", \"error\": \"$bandwidth_error\"}" >> "$result_file"
        log "ERROR" "Bandwidth test failed: $bandwidth_error"
        return 1
    else
        local bandwidth_json="  \"bandwidth\": {\"status\": \"success\", \"time_ms\": \"$test_duration\", \"download_mbps\": \"$download_speed\""
        
        if [ -n "$upload_speed" ] && [ "$upload_speed" != "0" ]; then
            bandwidth_json="$bandwidth_json, \"upload_mbps\": \"$upload_speed\""
        fi
        
        # Determine method used
        local method="curl"
        if ! command -v curl &> /dev/null && command -v wget &> /dev/null; then
            method="wget"
        fi
        
        bandwidth_json="$bandwidth_json, \"method\": \"$method\"}"
        echo "$bandwidth_json" >> "$result_file"
        
        if [ -n "$upload_speed" ] && [ "$upload_speed" != "0" ]; then
            log "SUCCESS" "Bandwidth test successful - Download: ${download_speed}Mbps, Upload: ${upload_speed}Mbps"
        else
            log "SUCCESS" "Bandwidth test successful - Download: ${download_speed}Mbps"
        fi
        return 0
    fi
}

# Test port connectivity
test_ports() {
    local target="$1"
    local result_file="$2"
    
    log "INFO" "Testing port connectivity to $target"
    
    # Extract hostname from URL if needed
    local hostname="$target"
    if [[ "$target" =~ ^https?:// ]]; then
        hostname=$(echo "$target" | sed 's|^https\?://||' | cut -d'/' -f1)
    fi
    
    # Validate hostname to prevent command injection
    if [[ ! "$hostname" =~ ^[a-zA-Z0-9.-]+$ ]] || [[ "$hostname" =~ ^\. ]] || [[ "$hostname" =~ \.$ ]] || [[ "$hostname" =~ \.\. ]]; then
        echo "  \"ports\": {\"status\": \"failed\", \"error\": \"invalid hostname format\"}" >> "$result_file"
        log "ERROR" "Invalid hostname format: $hostname"
        return 1
    fi
    
    local ports_start_time=$(date +%s.%N)
    local open_ports=()
    local total_open=0
    
    # Parse PORT_SCAN_PORTS configuration
    local ports_to_scan=()
    if [ -n "${PORT_SCAN_PORTS:-}" ]; then
        # Split comma-separated ports and validate
        IFS=',' read -ra port_list <<< "$PORT_SCAN_PORTS"
        for port in "${port_list[@]}"; do
            port=$(echo "$port" | tr -d ' ')  # Remove whitespace
            if [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]; then
                ports_to_scan+=("$port")
            else
                log "WARN" "Invalid port number: $port (skipping)"
            fi
        done
    else
        # Default ports if none specified
        ports_to_scan=(22 80 443 25 53 110 143 993 995)
    fi
    
    if [ ${#ports_to_scan[@]} -eq 0 ]; then
        echo "  \"ports\": {\"status\": \"disabled\", \"message\": \"No valid ports configured for scanning\"}" >> "$result_file"
        log "INFO" "No valid ports configured for scanning"
        return 0
    fi
    
    # Test each port
    for port in "${ports_to_scan[@]}"; do
        local port_open=false
        local port_error=""
        
        # Try netcat first (preferred method)
        if command -v nc &> /dev/null; then
            if timeout "$PORT_SCAN_TIMEOUT" nc -z -w"$PORT_SCAN_TIMEOUT" "$hostname" "$port" 2>/dev/null; then
                port_open=true
            else
                port_error="nc connection failed"
            fi
        # Fallback to /dev/tcp method
        elif [ -c /dev/tcp ]; then
            if timeout "$PORT_SCAN_TIMEOUT" bash -c "exec 3<>/dev/tcp/$hostname/$port" 2>/dev/null; then
                port_open=true
                exec 3<&- 2>/dev/null || true
            else
                port_error="tcp connection failed"
            fi
        else
            port_error="No port scanning tools available (nc or /dev/tcp)"
            break
        fi
        
        if [ "$port_open" = true ]; then
            open_ports+=("$port")
            total_open=$((total_open + 1))
            log "SUCCESS" "Port $port on $hostname is open"
        else
            log "DEBUG" "Port $port on $hostname is closed or filtered"
        fi
    done
    
    # Calculate total test time
    local ports_end_time=$(date +%s.%N)
    local test_duration=$(echo "($ports_end_time - $ports_start_time) * 1000" | bc -l 2>/dev/null | cut -d. -f1 || echo "0")
    
    # Prepare results
    if [ -n "$port_error" ] && [ ${#open_ports[@]} -eq 0 ]; then
        echo "  \"ports\": {\"status\": \"failed\", \"time_ms\": \"$test_duration\", \"error\": \"$port_error\"}" >> "$result_file"
        log "ERROR" "Port scanning failed: $port_error"
        return 1
    else
        # Build JSON array of open ports
        local ports_array=""
        for i in "${!open_ports[@]}"; do
            if [ "$i" -gt 0 ]; then
                ports_array="$ports_array, "
            fi
            ports_array="$ports_array${open_ports[$i]}"
        done
        
        echo "  \"ports\": {\"status\": \"success\", \"time_ms\": \"$test_duration\", \"open_ports\": [$ports_array], \"total_open\": $total_open, \"total_scanned\": ${#ports_to_scan[@]}}" >> "$result_file"
        
        if [ $total_open -gt 0 ]; then
            log "SUCCESS" "Port scanning completed - $total_open/${#ports_to_scan[@]} ports open: ${open_ports[*]}"
        else
            log "INFO" "Port scanning completed - 0/${#ports_to_scan[@]} ports open"
        fi
        return 0
    fi
}

# Test MTU discovery
test_mtu() {
    local target="$1"
    local result_file="$2"
    
    log "INFO" "Testing MTU discovery to $target"
    
    # Extract hostname from URL if needed
    local hostname="$target"
    if [[ "$target" =~ ^https?:// ]]; then
        hostname=$(echo "$target" | sed 's|^https\?://||' | cut -d'/' -f1)
    fi
    
    # Validate hostname to prevent command injection
    if [[ ! "$hostname" =~ ^[a-zA-Z0-9.-]+$ ]] || [[ "$hostname" =~ ^\. ]] || [[ "$hostname" =~ \.$ ]] || [[ "$hostname" =~ \.\. ]]; then
        echo "  \"mtu\": {\"status\": \"failed\", \"error\": \"invalid hostname format\"}" >> "$result_file"
        log "ERROR" "Invalid hostname format: $hostname"
        return 1
    fi
    
    local mtu_start_time=$(date +%s.%N)
    local mtu_error=""
    local discovered_mtu=0
    local test_count=0
    
    # Parse MTU configuration
    local min_mtu="${MTU_MIN:-576}"
    local max_mtu="${MTU_MAX:-1500}"
    local mtu_step="${MTU_STEP:-10}"
    
    # Validate configuration
    if ! [[ "$min_mtu" =~ ^[0-9]+$ ]] || [ "$min_mtu" -lt 68 ] || [ "$min_mtu" -gt 9000 ]; then
        mtu_error="Invalid MTU_MIN value: $min_mtu (must be 68-9000)"
    elif ! [[ "$max_mtu" =~ ^[0-9]+$ ]] || [ "$max_mtu" -lt 68 ] || [ "$max_mtu" -gt 9000 ]; then
        mtu_error="Invalid MTU_MAX value: $max_mtu (must be 68-9000)"
    elif ! [[ "$mtu_step" =~ ^[0-9]+$ ]] || [ "$mtu_step" -lt 1 ] || [ "$mtu_step" -gt 100 ]; then
        mtu_error="Invalid MTU_STEP value: $mtu_step (must be 1-100)"
    elif [ "$min_mtu" -ge "$max_mtu" ]; then
        mtu_error="MTU_MIN ($min_mtu) must be less than MTU_MAX ($max_mtu)"
    fi
    
    if [ -n "$mtu_error" ]; then
        echo "  \"mtu\": {\"status\": \"failed\", \"error\": \"$mtu_error\"}" >> "$result_file"
        log "ERROR" "MTU discovery configuration error: $mtu_error"
        return 1
    fi
    
    # Binary search for optimal MTU
    local low=$min_mtu
    local high=$max_mtu
    local best_mtu=$min_mtu
    
    log "INFO" "Starting MTU discovery: range $min_mtu-$max_mtu bytes, step $mtu_step"
    
    while [ "$low" -le "$high" ]; do
        local current_mtu=$(((low + high) / 2))
        local payload_size=$((current_mtu - 28))  # Subtract IP and ICMP headers
        
        # Ensure payload size is within valid range
        if [ "$payload_size" -lt 0 ] || [ "$payload_size" -gt 65507 ]; then
            if [ "$current_mtu" -lt "$min_mtu" ]; then
                low=$((current_mtu + 1))
            else
                high=$((current_mtu - 1))
            fi
            continue
        fi
        
        test_count=$((test_count + 1))
        
        # Test with ping Don't Fragment flag (detect OS)
        local ping_cmd="ping -c 1 -s $payload_size -W $MTU_TIMEOUT"
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS uses -D for Don't Fragment
            ping_cmd="$ping_cmd -D"
        else
            # Linux uses -M do for Don't Fragment
            ping_cmd="$ping_cmd -M do"
        fi
        
        if timeout "$MTU_TIMEOUT" "$ping_cmd" "$hostname" &>/dev/null; then
            best_mtu=$current_mtu
            low=$((current_mtu + mtu_step))
            log "DEBUG" "MTU $current_mtu bytes successful"
        else
            high=$((current_mtu - mtu_step))
            log "DEBUG" "MTU $current_mtu bytes failed"
        fi
        
        # Safety check to prevent infinite loops
        if [ $test_count -gt 50 ]; then
            log "WARN" "MTU discovery exceeded maximum test count, stopping"
            break
        fi
    done
    
    # Calculate total test time
    local mtu_end_time=$(date +%s.%N)
    local test_duration=$(echo "($mtu_end_time - $mtu_start_time) * 1000" | bc -l 2>/dev/null | cut -d. -f1 || echo "0")
    
    # Prepare results
    if [ "$best_mtu" -gt "$min_mtu" ]; then
        discovered_mtu=$best_mtu
        echo "  \"mtu\": {\"status\": \"success\", \"time_ms\": \"$test_duration\", \"discovered_mtu\": $discovered_mtu, \"test_count\": $test_count, \"range\": \"$min_mtu-$max_mtu\"}" >> "$result_file"
        log "SUCCESS" "MTU discovery completed - optimal MTU: ${discovered_mtu} bytes (tested $test_count times)"
        return 0
    else
        echo "  \"mtu\": {\"status\": \"failed\", \"time_ms\": \"$test_duration\", \"error\": \"no valid MTU found in range $min_mtu-$max_mtu\", \"test_count\": $test_count}" >> "$result_file"
        log "ERROR" "MTU discovery failed - no valid MTU found in range $min_mtu-$max_mtu"
        return 1
    fi
}

# Test HTTP/HTTPS connectivity
test_http() {
    local target="$1"
    local result_file="$2"
    
    # Add protocol if not present
    if [[ ! "$target" =~ ^https?:// ]]; then
        target="https://$target"
    fi
    
    log "INFO" "Testing HTTP connectivity to $target"
    
    local http_code
    local response_time
    local curl_exit_code
    local error_message=""
    
    # Use a temporary file to capture curl output and errors
    local temp_file="/tmp/curl_output_$$"
    local error_file="/tmp/curl_error_$$"
    
    # Run curl with proper error handling
    curl -s -w "\n%{http_code}\n%{time_total}\n%{exitcode}" \
         -m "$HTTP_TIMEOUT" \
         -A "$HTTP_USER_AGENT" \
         --connect-timeout 10 \
         --max-time "$HTTP_TIMEOUT" \
         "$target" > "$temp_file" 2> "$error_file"
    
    curl_exit_code=$?
    
    # Check if curl succeeded
    if [ $curl_exit_code -eq 0 ]; then
        # Parse response
        local response_lines=$(wc -l < "$temp_file")
        if [ "$response_lines" -ge 3 ]; then
            http_code=$(tail -n 3 "$temp_file" | head -n 1)
            response_time=$(tail -n 2 "$temp_file" | head -n 1)
            
            # Validate HTTP code is numeric
            if [[ "$http_code" =~ ^[0-9]+$ ]]; then
                if [ "$http_code" -ge 200 ] && [ "$http_code" -lt 400 ]; then
                    local time_ms=$(echo "$response_time * 1000" | bc -l 2>/dev/null | cut -d. -f1 || echo "0")
                    echo "  \"http\": {\"status\": \"success\", \"code\": $http_code, \"time_ms\": \"$time_ms\"}" >> "$result_file"
                    log "SUCCESS" "HTTP to $target successful (${http_code}, ${response_time}s)"
                    rm -f "$temp_file" "$error_file"
                    return 0
                else
                    echo "  \"http\": {\"status\": \"failed\", \"code\": $http_code, \"error\": \"HTTP $http_code\"}" >> "$result_file"
                    log "ERROR" "HTTP to $target failed with code $http_code"
                    rm -f "$temp_file" "$error_file"
                    return 1
                fi
            else
                error_message="Invalid HTTP response format"
            fi
        else
            error_message="Incomplete HTTP response"
        fi
    else
        # Handle curl errors
        case $curl_exit_code in
            6)  error_message="Couldn't resolve host" ;;
            7)  error_message="Failed to connect to host" ;;
            28) error_message="Operation timeout" ;;
            35) error_message="SSL connect error" ;;
            52) error_message="Empty reply from server" ;;
            56) error_message="Failure in receiving network data" ;;
            *)  error_message="Curl error $curl_exit_code" ;;
        esac
        
        # Try to get more details from error file
        if [ -s "$error_file" ]; then
            local curl_error=$(head -n 1 "$error_file" | sed 's/^curl: [0-9]*: //')
            if [ -n "$curl_error" ]; then
                error_message="$error_message: $curl_error"
            fi
        fi
    fi
    
    # Log and record the error
    echo "  \"http\": {\"status\": \"failed\", \"error\": \"$error_message\"}" >> "$result_file"
    log "ERROR" "HTTP to $target failed: $error_message"
    
    # Clean up temp files
    rm -f "$temp_file" "$error_file"
    return 1
}

# Perform traceroute
test_traceroute() {
    local target="$1"
    local result_file="$2"
    
    log "INFO" "Performing traceroute to $target"
    
    # Extract hostname from URL if needed
    local hostname="$target"
    if [[ "$target" =~ ^https?:// ]]; then
        hostname=$(echo "$target" | sed 's|^https\?://||' | cut -d'/' -f1)
    fi
    
    # Validate hostname to prevent command injection
    if [[ ! "$hostname" =~ ^[a-zA-Z0-9.-]+$ ]] || [[ "$hostname" =~ ^\. ]] || [[ "$hostname" =~ \.$ ]] || [[ "$hostname" =~ \.\. ]]; then
        echo "  \"traceroute\": {\"status\": \"failed\", \"error\": \"invalid hostname format\"}" >> "$result_file"
        log "ERROR" "Invalid hostname format: $hostname"
        return 1
    fi
    
    local trace_output
    local trace_file="/tmp/traceroute_$$"
    
    if trace_output=$(timeout "$TRACEROUTE_TIMEOUT" traceroute -m "$TRACEROUTE_MAX_HOPS" "$hostname" 2>&1); then
        local hop_count=$(echo "$trace_output" | grep -c "^\s*[0-9]" || echo "0")
        local last_hop=$(echo "$trace_output" | grep "^\s*[0-9]" | tail -1 | awk '{print $2}' | sed 's/[()]//g')
        
        echo "  \"traceroute\": {\"status\": \"success\", \"hops\": $hop_count, \"last_hop\": \"$last_hop\"}" >> "$result_file"
        log "SUCCESS" "Traceroute to $hostname completed ($hop_count hops, last: $last_hop)"
        
        # Save full traceroute output
        echo "$trace_output" > "${RESULTS_DIR}/traceroute-${hostname}-$(date +%Y%m%d-%H%M%S).txt"
    else
        echo "  \"traceroute\": {\"status\": \"failed\", \"error\": \"timeout or failed\"}" >> "$result_file"
        log "ERROR" "Traceroute to $hostname failed"
    fi
    
    rm -f "$trace_file"
}

# Test a single target
test_target() {
    local target="$1"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    log "INFO" "Starting tests for target: $target"
    
    # Create results directory
    mkdir -p "$RESULTS_DIR"
    
    # Start JSON result for this target
    local result_file="/tmp/netnoise_result_$$.json"
    echo "{" > "$result_file"
    echo "  \"target\": \"$target\"," >> "$result_file"
    echo "  \"timestamp\": \"$timestamp\"," >> "$result_file"
    
    # Test DNS resolution (if enabled)
    local dns_result=0
    if [ "${DNS_ENABLED:-true}" = "true" ]; then
        test_dns "$target" "$result_file"
        dns_result=$?
    else
        echo "  \"dns\": {\"status\": \"disabled\", \"message\": \"DNS testing disabled in configuration\"}" >> "$result_file"
        log "INFO" "DNS testing disabled for $target"
    fi
    
    # Test ping
    test_ping "$target" "$result_file"
    local ping_result=$?
    
    # Test bandwidth (if enabled)
    local bandwidth_result=0  # Default to success when disabled
    if [ "${BANDWIDTH_ENABLED:-false}" = "true" ]; then
        test_bandwidth "$target" "$result_file"
        bandwidth_result=$?
    else
        echo "  \"bandwidth\": {\"status\": \"disabled\", \"message\": \"Bandwidth testing disabled in configuration\"}" >> "$result_file"
        log "INFO" "Bandwidth testing disabled for $target"
    fi
    
    # Test port scanning (if enabled)
    local ports_result=0  # Default to success when disabled
    if [ "${PORT_SCAN_ENABLED:-false}" = "true" ]; then
        test_ports "$target" "$result_file"
        ports_result=$?
    else
        echo "  \"ports\": {\"status\": \"disabled\", \"message\": \"Port scanning disabled in configuration\"}" >> "$result_file"
        log "INFO" "Port scanning disabled for $target"
    fi
    
    # Test MTU discovery (if enabled)
    local mtu_result=0  # Default to success when disabled
    if [ "${MTU_ENABLED:-false}" = "true" ]; then
        test_mtu "$target" "$result_file"
        mtu_result=$?
    else
        echo "  \"mtu\": {\"status\": \"disabled\", \"message\": \"MTU discovery disabled in configuration\"}" >> "$result_file"
        log "INFO" "MTU discovery disabled for $target"
    fi
    
    # Test HTTP
    test_http "$target" "$result_file"
    local http_result=$?
    
    # Test traceroute
    test_traceroute "$target" "$result_file"
    
    # Close JSON
    echo "}" >> "$result_file"
    
    # Append to main results file with file locking to prevent race conditions
    local lock_file="${RESULTS_FILE}.lock"
    local timeout=30
    local count=0
    
    # Wait for lock with timeout
    while [ $count -lt $timeout ]; do
        if (set -C; echo $$ > "$lock_file") 2>/dev/null; then
            # Got the lock
            trap 'rm -f "$lock_file"' EXIT
            
            # Append to main results file
            if [ -f "$RESULTS_FILE" ]; then
                echo "," >> "$RESULTS_FILE"
            else
                echo "[" > "$RESULTS_FILE"
            fi
            cat "$result_file" >> "$RESULTS_FILE"
            
            # Release lock
            rm -f "$lock_file"
            trap - EXIT
            break
        else
            # Lock is held, wait and retry
            sleep 1
            count=$((count + 1))
        fi
    done
    
    # If we couldn't get the lock, log a warning but continue
    if [ $count -eq $timeout ]; then
        log "WARN" "Could not acquire lock for results file, skipping this result"
    fi
    
    # Clean up temp file
    rm -f "$result_file"
    
    # Return overall result
    if [ $dns_result -eq 0 ] || [ $ping_result -eq 0 ] || [ $bandwidth_result -eq 0 ] || [ $ports_result -eq 0 ] || [ $mtu_result -eq 0 ] || [ $http_result -eq 0 ]; then
        log "SUCCESS" "Target $target is reachable"
        return 0
    else
        log "ERROR" "Target $target is unreachable"
        return 1
    fi
}
