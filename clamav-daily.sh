#!/bin/bash

# Load environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/hosting_env.env"
source "${SCRIPT_DIR}/telegram_notify.sh"

LOG_FILE="$LOG_DIR/clamav-daily.log"
REPORT_FILE="$LOG_DIR/daily-report-$(date +%Y%m%d).log"

# Directories to monitor
MONITOR_DIRS=("/var/www" "/var/tmp" "/var/backups" "/var/upload" "/tmp")

# Enhanced logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE" >> "$REPORT_FILE"
}

# Main security scan function
perform_security_scan() {
    log "START: Comprehensive security scan started"
    
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
    
    # Run ClamAV scan - IGNORE .log files
    log "Starting ClamAV scan (ignoring .log files)..."
    
    # Build exclude arguments for log files
    local exclude_args=""
    for dir in "${MONITOR_DIRS[@]}"; do
        if [[ -d "$dir" ]]; then
            exclude_args+=" --exclude=*.log"
            # Also exclude common log patterns
            exclude_args+=" --exclude=*access.log* --exclude=*error.log* --exclude=*.log.*"
        fi
    done
    
    local clamav_result=$(clamscan -r $exclude_args --max-filesize="$CLAMAV_MAX_FILE_SIZE" "${MONITOR_DIRS[@]}" 2>&1 || true)
    
    # Process ClamAV results
    local infected_files=0
    if echo "$clamav_result" | grep -q "Infected files: 0"; then
        scan_results+="🔍 CLAMAV SCAN: ✅ No threats detected\n"
        log "ClamAV scan completed - no threats found"
    else
        infected_files=$(echo "$clamav_result" | grep "Infected files:" | awk '{print $3}')
        if [[ -n "$infected_files" && "$infected_files" -gt 0 ]]; then
            total_threats=$((total_threats + infected_files))
            scan_results+="🔍 CLAMAV SCAN: 🚨 $infected_files infected files found\n"
            log "ClamAV found $infected_files infected files"
            
            {
                echo "🚨 CLAMAV INFECTED FILES:"
                echo "========================="
                echo "$clamav_result" | grep "FOUND"
                echo ""
            } >> "$REPORT_FILE"
        else
            scan_results+="🔍 CLAMAV SCAN: ✅ Scan completed\n"
            log "ClamAV scan completed with warnings but no infected files"
        fi
    fi
    
    # File system health check
    log "Performing filesystem health check..."
    {
        echo ""
        echo "📊 FILESYSTEM HEALTH"
        echo "===================="
        echo "Disk usage:"
        df -h /var /tmp /home 2>/dev/null | head -n 4
        echo ""
        
        echo "Large files in monitored directories (top 10):"
        for dir in "${MONITOR_DIRS[@]}"; do
            if [[ -d "$dir" ]]; then
                echo "--- $dir ---"
                find "$dir" -type f ! -name "*.log" -size +10M -exec ls -lh {} \; 2>/dev/null | head -10 | awk '{print $5, $9}' || echo "No large files found"
                echo ""
            fi
        done
    } >> "$REPORT_FILE"
    
    # Final report
    {
        echo ""
        echo "📈 SCAN SUMMARY"
        echo "================"
        echo "Total threats detected: $total_threats"
        echo "Scan status: $(if [[ $total_threats -gt 0 ]]; then echo "❌ NEEDS ATTENTION"; else echo "✅ ALL CLEAR"; fi)"
        echo ""
        echo "$scan_results"
        
        echo ""
        echo "📋 SCAN DETAILS"
        echo "================"
        echo "Scanned directories: ${MONITOR_DIRS[*]}"
        echo "Excluded patterns: *.log, *access.log*, *error.log*"
        echo "Max file size: $CLAMAV_MAX_FILE_SIZE"
        
    } >> "$REPORT_FILE"
    
    log "END: Security scan completed. Total threats: $total_threats"
    
    # Send notifications based on findings
    if [[ $total_threats -gt 0 ]]; then
        local threat_details="🚨 SECURITY ALERT: $total_threats threats detected
🖥️ Server: $(hostname)
📅 Time: $(date '+%Y-%m-%d %H:%M:%S')
🔍 Infected files: $infected_files

⚠️ Immediate review required!
Check full report: $REPORT_FILE"
        
        send_telegram_notification "$threat_details"
        
        # Also send a shorter summary
        local message_summary="🛡️ Security Scan: ❌ THREATS DETECTED
🖥️ $(hostname) | 📅 $(date '+%Y-%m-%d')
🚨 $total_threats infected files found"
        send_telegram_notification "$message_summary"
        
    else
        local message_summary="🛡️ Security Scan: ✅ ALL CLEAR
🖥️ Server: $(hostname)
📅 Date: $(date '+%Y-%m-%d %H:%M:%S')
📊 Scan completed successfully
🔍 No threats detected"
        
        send_telegram_notification "$message_summary"
    fi
}

# Main execution
main() {
    log "=== SECURITY MONITORING STARTED ==="
    perform_security_scan
    log "=== SECURITY MONITORING COMPLETED ==="
}

# Run main function
main "$@"
