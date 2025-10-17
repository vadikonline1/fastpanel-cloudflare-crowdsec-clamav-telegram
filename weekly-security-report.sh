#!/bin/bash
# weekly-security-report.sh - Scanare completă OPTIMIZATĂ a sistemului

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/hosting_env.env"
source "${SCRIPT_DIR}/telegram_notify.sh"

LOG_DIR="/etc/automation-web-hosting/log"
WEEKLY_LOG="$LOG_DIR/weekly-security-scan.log"
WEEKLY_REPORT="$LOG_DIR/weekly-report-$(date +%Y%m%d).log"

# Enhanced logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$WEEKLY_LOG" >> "$WEEKLY_REPORT"
}

# Optimized full system scan - focuses on critical areas
perform_optimized_system_scan() {
    local start_time=$(date +%s)
    log "START: Optimized weekly system security scan started"
    
    {
        echo "🛡️ WEEKLY OPTIMIZED SYSTEM SECURITY SCAN REPORT"
        echo "==============================================="
        echo "🖥️ Server: $(hostname)"
        echo "📅 Date: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "📊 Scan type: OPTIMIZED SYSTEM SCAN"
        echo "🎯 Focus: Critical system areas + web content"
        echo ""
    } > "$WEEKLY_REPORT"
    
    local total_threats=0
    local scan_results=""
    
    # 1. OPTIMIZED ClamAV scan - using directories from environment
    log "Starting optimized ClamAV scan on: ${WEEKLY_SCAN_DIRS[*]}"
    
    local clamav_result=$(clamscan -r --max-filesize="$CLAMAV_MAX_FILE_SIZE" "${WEEKLY_SCAN_DIRS[@]}" 2>&1 || true)
    
    local clamav_infected=0
    if echo "$clamav_result" | grep -q "Infected files: 0"; then
        scan_results+="🔍 OPTIMIZED CLAMAV: ✅ No threats detected\n"
        log "Optimized ClamAV scan completed - no threats found"
    else
        clamav_infected=$(echo "$clamav_result" | grep "Infected files:" | awk '{print $3}')
        if [[ -n "$clamav_infected" && "$clamav_infected" -gt 0 ]]; then
            total_threats=$((total_threats + clamav_infected))
            scan_results+="🔍 OPTIMIZED CLAMAV: 🚨 $clamav_infected infected files\n"
            log "Optimized ClamAV found $clamav_infected infected files"
            
            {
                echo "🚨 CLAMAV INFECTED FILES (top 15):"
                echo "=================================="
                echo "$clamav_result" | grep "FOUND" | head -15
                echo ""
            } >> "$WEEKLY_REPORT"
        fi
    fi
    
    # 2. Quick RKHunter scan (already fast)
    log "Starting RKHunter scan..."
    if command -v rkhunter >/dev/null 2>&1; then
        local rkhunter_report="$LOG_DIR/rkhunter-weekly-$(date +%Y%m%d).log"
        rkhunter --check --sk --rwo > "$rkhunter_report" 2>&1
        
        local warnings=$(grep -c "Warning" "$rkhunter_report" 2>/dev/null || echo "0")
        local suspicious=$(grep -c "Suspicious" "$rkhunter_report" 2>/dev/null || echo "0")
        
        if [[ $warnings -gt 0 ]]; then
            scan_results+="🦠 RKHUNTER: 🚨 $warnings warnings, $suspicious suspicious\n"
        else
            scan_results+="🦠 RKHUNTER: ✅ No threats detected\n"
        fi
        
        {
            echo "🦠 RKHUNTER RESULTS"
            echo "==================="
            echo "Warnings: $warnings"
            echo "Suspicious items: $suspicious"
            echo ""
        } >> "$WEEKLY_REPORT"
        
        rm -f "$rkhunter_report"
    else
        scan_results+="🦠 RKHUNTER: ❌ Not installed\n"
    fi
    
    # 3. Targeted Maldet scan - using directories from environment
    log "Starting targeted Maldet scan on: ${MALDET_SCAN_DIRS[*]}"
    local maldet_cmd=$(command -v maldet || command -v lmd)
    if [[ -n "$maldet_cmd" ]]; then
        local maldet_infected=0
        
        for dir in "${MALDET_SCAN_DIRS[@]}"; do
            if [[ -d "$dir" ]]; then
                log "Scanning $dir with Maldet..."
                local scan_result=$($maldet_cmd -a "$dir" 2>&1)
                
                if echo "$scan_result" | grep -q "SCAN ID"; then
                    local scan_id=$(echo "$scan_result" | grep "SCAN ID" | awk '{print $3}')
                    sleep 10  # Shorter wait for optimized scan
                    
                    local report=$($maldet_cmd -e "$scan_id" 2>&1)
                    local hits=$(echo "$report" | grep "TOTAL HITS" | awk '{print $3}' 2>/dev/null || echo "0")
                    
                    if [[ "$hits" =~ ^[0-9]+$ ]] && [[ "$hits" -gt 0 ]]; then
                        maldet_infected=$((maldet_infected + hits))
                        {
                            echo "🔍 MALDET SCAN $dir: $hits hits"
                            echo "$report" | grep "HIT" | head -2
                            echo ""
                        } >> "$WEEKLY_REPORT"
                    fi
                    
                    $maldet_cmd -q "$scan_id" 2>/dev/null || true
                fi
            fi
        done
        
        if [[ $maldet_infected -gt 0 ]]; then
            total_threats=$((total_threats + maldet_infected))
            scan_results+="🔍 TARGETED MALDET: 🚨 $maldet_infected infected files\n"
        else
            scan_results+="🔍 TARGETED MALDET: ✅ No threats detected\n"
        fi
    else
        scan_results+="🔍 TARGETED MALDET: ❌ Not installed\n"
    fi
    
    # 4. Quick system integrity check
    log "Performing quick system integrity check..."
    {
        echo ""
        echo "🔒 QUICK SYSTEM INTEGRITY CHECK"
        echo "=============================="
        echo "Critical file changes (last 7 days):"
        echo "-----------------------------------"
        find /etc -type f -mtime -7 -ls 2>/dev/null | head -10
        echo ""
        
        echo "User account changes:"
        echo "--------------------"
        find /home -type f -name "*.sh" -o -name "*.php" -o -name "*.py" 2>/dev/null | head -5
        echo ""
    } >> "$WEEKLY_REPORT"
    
    # 5. System health snapshot
    log "Creating system health snapshot..."
    {
        echo "💾 SYSTEM HEALTH SNAPSHOT"
        echo "========================"
        echo "Disk usage:"
        df -h | grep -E '(/var|/home|/tmp|/$)' | head -5
        echo ""
        
        echo "Memory usage:"
        free -h | head -2
        echo ""
        
        echo "Top processes by CPU:"
        ps aux --sort=-%cpu | head -5
        echo ""
    } >> "$WEEKLY_REPORT"
    
    # Calculate scan duration
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local duration_minutes=$((duration / 60))
    
    # Final report
    {
        echo ""
        echo "📈 WEEKLY SCAN SUMMARY"
        echo "======================"
        echo "Total threats detected: $total_threats"
        echo "Scan duration: ${duration_minutes} minutes"
        echo "Scan status: $(if [[ $total_threats -gt 0 ]]; then echo "❌ NEEDS ATTENTION"; else echo "✅ ALL SYSTEMS CLEAR"; fi)"
        echo ""
        echo -e "$scan_results"
        echo ""
        echo "📋 SCAN DETAILS"
        echo "================"
        echo "Optimized scan completed"
        echo "Scanned directories: ${WEEKLY_SCAN_DIRS[*]}"
        echo "Maldet directories: ${MALDET_SCAN_DIRS[*]}"
        echo "Report location: $WEEKLY_REPORT"
        echo "Scan finished: $(date '+%Y-%m-%d %H:%M:%S')"
        
    } >> "$WEEKLY_REPORT"
    
    log "END: Optimized weekly scan completed in ${duration_minutes} minutes. Total threats: $total_threats"
    
    # Send optimized weekly report
    local weekly_message="📊 WEEKLY SECURITY REPORT (Optimized)
🖥️ Server: $(hostname)
📅 Date: $(date '+%Y-%m-%d %H:%M:%S')
⏱️ Duration: ${duration_minutes} minutes
📈 Threats: $total_threats
$(echo -e "$scan_results")
🔍 Full report: $WEEKLY_REPORT"
    
    if send_telegram_notification "$weekly_message"; then
        log "✅ Weekly Telegram notification sent successfully"
    else
        log "❌ Weekly Telegram notification failed"
    fi
    
    return $total_threats
}

# Main execution for optimized weekly scan
main_weekly() {
    log "=== OPTIMIZED WEEKLY SYSTEM SCAN STARTED ==="
    
    # Create log directory if it doesn't exist
    mkdir -p "$LOG_DIR"
    
    # Perform optimized system scan
    perform_optimized_system_scan
    local scan_result=$?
    
    log "=== OPTIMIZED WEEKLY SYSTEM SCAN COMPLETED ==="
    
    return $scan_result
}

# Run if called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main_weekly "$@"
fi
