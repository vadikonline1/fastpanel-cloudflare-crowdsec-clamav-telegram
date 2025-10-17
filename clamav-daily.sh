#!/bin/bash

# Load environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/hosting_env.env"
source "${SCRIPT_DIR}/telegram_notify.sh"

LOG_FILE="$LOG_DIR/clamav-daily.log"
REPORT_FILE="$LOG_DIR/daily-report-$(date +%Y%m%d).log"
QUARANTINE_DIR="$LOG_DIR/quarantine"

# Directories to monitor
MONITOR_DIRS=("/var/www" "/var/tmp" "/var/backups" "/var/upload" "/tmp")

# Enhanced logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE" >> "$REPORT_FILE"
}

# Clean old logs
clean_old_logs() {
    log "Cleaning logs older than 7 days..."
    find "$LOG_DIR" -name "*.log" -mtime +7 -delete 2>/dev/null && log "Old logs cleaned successfully" || log "No old logs to clean"
    
    # Clean old quarantine files (older than 30 days)
    find "$QUARANTINE_DIR" -type f -mtime +30 -delete 2>/dev/null && log "Old quarantine files cleaned" || true
}

# Create quarantine directory
setup_quarantine() {
    mkdir -p "$QUARANTINE_DIR"
    chmod 700 "$QUARANTINE_DIR"
}

# Remove infected files function
remove_infected_files() {
    local clamav_result="$1"
    local removed_count=0
    local quarantine_count=0
    
    log "Starting removal of infected files..."
    
    # Extract infected files from ClamAV results
    local infected_files=$(echo "$clamav_result" | grep "FOUND" | awk '{print $1}' | head -50)
    
    if [[ -z "$infected_files" ]]; then
        log "No infected files found to remove"
        return 0
    fi
    
    {
        echo ""
        echo "🗑️ INFECTED FILES REMOVAL REPORT"
        echo "================================"
    } >> "$REPORT_FILE"
    
    for file in $infected_files; do
        if [[ -f "$file" ]]; then
            local file_size=$(stat -c%s "$file" 2>/dev/null || echo "unknown")
            local file_type=$(file "$file" 2>/dev/null | cut -d: -f2- || echo "unknown")
            
            # Skip files in /tmp (usually temporary/cache files)
            if [[ "$file" == /tmp/* ]]; then
                log "Skipping temporary file: $file"
                echo "⏭️ SKIPPED (temporary): $file" >> "$REPORT_FILE"
                continue
            fi
            
            # Try to quarantine first (for important directories)
            if [[ "$file" == /var/www/* ]] || [[ "$file" == /var/upload/* ]]; then
                local quarantine_file="$QUARANTINE_DIR/$(basename "$file")_$(date +%Y%m%d_%H%M%S)"
                if cp "$file" "$quarantine_file" 2>/dev/null; then
                    log "Quarantined: $file -> $quarantine_file"
                    echo "📦 QUARANTINED: $file (size: $file_size, type: $file_type)" >> "$REPORT_FILE"
                    quarantine_count=$((quarantine_count + 1))
                fi
            fi
            
            # Remove the infected file
            if rm -f "$file" 2>/dev/null; then
                log "✅ REMOVED infected file: $file"
                echo "✅ REMOVED: $file (size: $file_size, type: $file_type)" >> "$REPORT_FILE"
                removed_count=$((removed_count + 1))
            else
                log "❌ FAILED to remove: $file"
                echo "❌ FAILED: $file (size: $file_size, type: $file_type)" >> "$REPORT_FILE"
            fi
        else
            log "File not found (already removed?): $file"
            echo "⚠️ NOT FOUND: $file" >> "$REPORT_FILE"
        fi
    done
    
    {
        echo ""
        echo "📊 REMOVAL SUMMARY:"
        echo "Files removed: $removed_count"
        echo "Files quarantined: $quarantine_count"
        echo ""
    } >> "$REPORT_FILE"
    
    log "Infected files removal completed: $removed_count removed, $quarantine_count quarantined"
    return $removed_count
}

# RKHunter scan function
perform_rkhunter_scan() {
    log "Starting RKHunter full system check..."
    
    local rkhunter_report="$LOG_DIR/rkhunter-$(date +%Y%m%d).log"
    
    {
        echo ""
        echo "🦠 RKHUNTER SCAN RESULTS"
        echo "========================"
    } >> "$REPORT_FILE"
    
    # Run RKHunter with comprehensive check
    if command -v rkhunter >/dev/null 2>&1; then
        # Update RKHunter database
        log "Updating RKHunter database..."
        rkhunter --update 2>&1 | tee -a "$LOG_FILE" > /dev/null
        
        # Perform full system check
        log "Running RKHunter full system check..."
        rkhunter --check --sk --rwo 2>&1 | tee "$rkhunter_report"
        
        # Extract warnings and suspicious items
        local warnings=$(grep -c "Warning" "$rkhunter_report" 2>/dev/null || echo "0")
        local suspicious=$(grep -c "Suspicious" "$rkhunter_report" 2>/dev/null || echo "0")
        
        # Create summary directly in report
        {
            echo "RKHunter Scan Summary:"
            echo "---------------------"
            echo "Scan date: $(date '+%Y-%m-%d %H:%M:%S')"
            echo "Warnings found: $warnings"
            echo "Suspicious items: $suspicious"
            echo ""
            
            if [[ $warnings -gt 0 ]]; then
                echo "Top warnings:"
                grep "Warning" "$rkhunter_report" 2>/dev/null | head -5 || echo "No warnings details"
            fi
        } >> "$REPORT_FILE"
        
        if [[ $warnings -eq 0 && $suspicious -eq 0 ]]; then
            echo "✅ RKHunter: No warnings or suspicious items detected" >> "$REPORT_FILE"
            log "RKHunter scan completed - no threats found"
            echo "🦠 RKHUNTER: ✅ No threats detected"
        else
            echo "🚨 RKHunter: $warnings warnings, $suspicious suspicious items found" >> "$REPORT_FILE"
            log "RKHunter found $warnings warnings and $suspicious suspicious items"
            echo "🦠 RKHUNTER: 🚨 $warnings warnings, $suspicious suspicious items"
        fi
        
        # Clean up
        rm -f "$rkhunter_report"
        
    else
        echo "❌ RKHunter: Not installed" >> "$REPORT_FILE"
        log "RKHunter not installed"
        echo "🦠 RKHUNTER: ❌ Not installed"
    fi
    
    # Return the scan result string
    if [[ $warnings -eq 0 && $suspicious -eq 0 ]]; then
        echo "🦠 RKHUNTER: ✅ No threats detected"
    else
        echo "🦠 RKHUNTER: 🚨 $warnings warnings, $suspicious suspicious items"
    fi
}

# Maldet (Linux Malware Detect) scan function
perform_maldet_scan() {
    log "Starting Maldet malware scan..."
    
    {
        echo ""
        echo "🔍 MALDET SCAN RESULTS"
        echo "======================"
    } >> "$REPORT_FILE"
    
    local maldet_cmd=$(command -v maldet || command -v lmd)
    
    if [[ -n "$maldet_cmd" ]]; then
        # Update Maldet signatures
        log "Updating Maldet signatures..."
        $maldet_cmd --update 2>&1 | tee -a "$LOG_FILE" > /dev/null
        
        # Perform scan on monitored directories
        log "Running Maldet scan on monitored directories..."
        
        local infected_count=0
        local scan_results=""
        
        for dir in "${MONITOR_DIRS[@]}"; do
            if [[ -d "$dir" ]]; then
                log "Scanning directory with Maldet: $dir"
                local scan_result=$($maldet_cmd -a "$dir" 2>&1)
                
                if echo "$scan_result" | grep -q "SCAN ID"; then
                    local scan_id=$(echo "$scan_result" | grep "SCAN ID" | awk '{print $3}')
                    
                    if [[ -n "$scan_id" ]]; then
                        # Wait a bit for scan to complete
                        sleep 10
                        
                        # Get report
                        local report=$($maldet_cmd -e "$scan_id" 2>&1)
                        local hits=$(echo "$report" | grep "TOTAL HITS" | awk '{print $3}' 2>/dev/null || echo "0")
                        
                        if [[ "$hits" =~ ^[0-9]+$ ]] && [[ "$hits" -gt 0 ]]; then
                            infected_count=$((infected_count + hits))
                            scan_results+="Directory $dir: $hits hits\n"
                            
                            # Log detailed hits
                            echo "$report" | grep "HIT" | head -5 >> "$REPORT_FILE"
                        fi
                        
                        # Clean up the scan
                        $maldet_cmd -q "$scan_id" 2>/dev/null || true
                    fi
                else
                    log "Maldet scan failed for $dir: $scan_result"
                fi
            fi
        done
        
        # Append to main report
        {
            echo "Maldet Scan Summary:"
            echo "-------------------"
            echo "Scan date: $(date '+%Y-%m-%d %H:%M:%S')"
            echo "Infected files: $infected_count"
            echo ""
            
            if [[ $infected_count -gt 0 ]]; then
                echo "Infected directories:"
                echo -e "$scan_results"
            fi
        } >> "$REPORT_FILE"
        
        if [[ $infected_count -eq 0 ]]; then
            echo "✅ Maldet: No malware detected" >> "$REPORT_FILE"
            log "Maldet scan completed - no malware found"
            echo "🔍 MALDET: ✅ No threats detected"
        else
            echo "🚨 Maldet: $infected_count infected files found" >> "$REPORT_FILE"
            log "Maldet found $infected_count infected files"
            echo "🔍 MALDET: 🚨 $infected_count infected files"
        fi
        
    else
        echo "❌ Maldet: Not installed" >> "$REPORT_FILE"
        log "Maldet not installed"
        echo "🔍 MALDET: ❌ Not installed"
    fi
    
    # Return the scan result string
    if [[ $infected_count -eq 0 ]]; then
        echo "🔍 MALDET: ✅ No threats detected"
    else
        echo "🔍 MALDET: 🚨 $infected_count infected files"
    fi
}

# ClamAV scan function
perform_clamav_scan() {
    log "Starting ClamAV scan (ignoring .log files)..."
    
    # Build exclude arguments for log files
    local exclude_args=""
    for dir in "${MONITOR_DIRS[@]}"; do
        if [[ -d "$dir" ]]; then
            exclude_args+=" --exclude=*.log"
            exclude_args+=" --exclude=*access.log* --exclude=*error.log* --exclude=*.log.*"
        fi
    done
    
    local clamav_result=$(clamscan -r $exclude_args --max-filesize="$CLAMAV_MAX_FILE_SIZE" "${MONITOR_DIRS[@]}" 2>&1 || true)
    
    # Process ClamAV results
    local infected_files=0
    if echo "$clamav_result" | grep -q "Infected files: 0"; then
        log "ClamAV scan completed - no threats found"
        infected_files=0
    else
        infected_files=$(echo "$clamav_result" | grep "Infected files:" | awk '{print $3}' 2>/dev/null || echo "0")
        if [[ -n "$infected_files" ]] && [[ "$infected_files" -gt 0 ]]; then
            log "ClamAV found $infected_files infected files"
            
            {
                echo "🚨 CLAMAV INFECTED FILES:"
                echo "========================="
                echo "$clamav_result" | grep "FOUND" | head -20
                echo ""
            } >> "$REPORT_FILE"
            
            # Remove infected files automatically
            remove_infected_files "$clamav_result"
            
        else
            log "ClamAV scan completed with warnings but no infected files"
            infected_files=0
        fi
    fi
    
    # Return both the result string and infected count
    if [[ $infected_files -eq 0 ]]; then
        echo "🔍 CLAMAV: ✅ No threats detected"
    else
        echo "🔍 CLAMAV: 🚨 $infected_files infected files found and removed"
    fi
    
    echo "$infected_files"
}

# File system health check
perform_filesystem_check() {
    log "Performing filesystem health check..."
    
    {
        echo ""
        echo "📊 FILESYSTEM HEALTH"
        echo "===================="
        echo "Disk usage:"
        df -h /var /tmp /home 2>/dev/null | head -n 4
        echo ""
        
        echo "Large files in monitored directories (top 3):"
        for dir in "${MONITOR_DIRS[@]}"; do
            if [[ -d "$dir" ]]; then
                echo "--- $dir ---"
                find "$dir" -type f ! -name "*.log" -size +50M -exec ls -lh {} \; 2>/dev/null | head -3 | awk '{print $5, $9}' 2>/dev/null || echo "No large files found"
                echo ""
            fi
        done
    } >> "$REPORT_FILE"
}

# Main security scan function
perform_security_scan() {
    log "START: Comprehensive security scan started"
    
    # Create report directory if it doesn't exist
    mkdir -p "$LOG_DIR"
    setup_quarantine
    
    {
        echo "🛡️ COMPREHENSIVE SECURITY SCAN REPORT"
        echo "======================================"
        echo "🖥️ Server: $(hostname)"
        echo "📅 Date: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "📁 Monitored directories: ${MONITOR_DIRS[*]}"
        echo ""
    } > "$REPORT_FILE"
    
    local total_threats=0
    local scan_results=""
    
    # Run ClamAV scan
    log "Starting ClamAV scan..."
    local clamav_output=$(perform_clamav_scan)
    local clamav_infected=$(echo "$clamav_output" | tail -1)
    scan_results+="$(echo "$clamav_output" | head -1)\n"
    
    if [[ -n "$clamav_infected" && "$clamav_infected" -gt 0 ]]; then
        total_threats=$((total_threats + clamav_infected))
    fi
    
    # Run RKHunter scan
    log "Starting RKHunter scan..."
    local rkhunter_result=$(perform_rkhunter_scan)
    scan_results+="${rkhunter_result}\n"
    
    # Run Maldet scan  
    log "Starting Maldet scan..."
    local maldet_output=$(perform_maldet_scan)
    local maldet_infected=$(echo "$maldet_output" | grep -o "[0-9]*" | head -1)
    scan_results+="${maldet_output}\n"
    
    if [[ -n "$maldet_infected" && "$maldet_infected" -gt 0 ]]; then
        total_threats=$((total_threats + maldet_infected))
    fi
    
    # File system health check
    perform_filesystem_check
    
    # Final report
    {
        echo ""
        echo "📈 SCAN SUMMARY"
        echo "================"
        echo "Total threats detected: $total_threats"
        echo "Scan status: $(if [[ $total_threats -gt 0 ]]; then echo "❌ NEEDS ATTENTION"; else echo "✅ ALL CLEAR"; fi)"
        echo ""
        echo -e "$scan_results"
        
        echo ""
        echo "📋 SCAN DETAILS"
        echo "================"
        echo "Scanned directories: ${MONITOR_DIRS[*]}"
        echo "Excluded patterns: *.log, *access.log*, *error.log*"
        echo "Max file size: $CLAMAV_MAX_FILE_SIZE"
        echo "Report location: $REPORT_FILE"
        echo "Quarantine location: $QUARANTINE_DIR"
        
    } >> "$REPORT_FILE"
    
    log "END: Security scan completed. Total threats: $total_threats"
    
    # Send notifications based on findings
    local short_message=""
    if [[ $total_threats -gt 0 ]]; then
        short_message="🚨 SECURITY ALERT: $total_threats threats detected
🖥️ Server: $(hostname)
📅 Time: $(date '+%Y-%m-%d %H:%M:%S')

⚠️ Check full report: $REPORT_FILE"
    else
        short_message="🛡️ Security Scan: ✅ ALL CLEAR
🖥️ Server: $(hostname)
📅 Date: $(date '+%Y-%m-%d %H:%M:%S')
📊 All scans completed successfully"
    fi
    
    # Send notification
    if send_telegram_notification "$short_message"; then
        log "✅ Telegram notification sent successfully"
    else
        log "❌ Telegram notification failed"
    fi
    
    return $total_threats
}

# Main execution
main() {
    log "=== SECURITY MONITORING STARTED ==="
    
    # Clean old logs first
    clean_old_logs
    
    # Perform comprehensive security scan
    perform_security_scan
    local scan_result=$?
    
    log "=== SECURITY MONITORING COMPLETED ==="
    
    return $scan_result
}

# Run main function if called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
