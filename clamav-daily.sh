#!/bin/bash
set -e

# Load environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/hosting_env.env"
source "${SCRIPT_DIR}/telegram_notify.sh"

LOG_FILE="$LOG_DIR/clamav-daily.log"
REPORT_FILE="$LOG_DIR/daily-report-$(date +%Y%m%d).log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE" >> "$REPORT_FILE"
}

log "START: Daily security scan started"

{
    echo "🛡️ DAILY SECURITY SCAN REPORT"
    echo "================================"
    echo "🖥️ Server: $(hostname)"
    echo "📅 Date: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
} > "$REPORT_FILE"

# Run ClamAV scan
log "Starting ClamAV scan of: $CLAMAV_SCAN_PATHS"
SCAN_RESULT=$(clamscan -r --max-filesize="$CLAMAV_MAX_FILE_SIZE" $CLAMAV_SCAN_PATHS 2>&1)

if echo "$SCAN_RESULT" | grep -q "Infected files: 0"; then
    MALWARE_STATUS="✅ No threats detected"
    SCAN_SUMMARY=$(echo "$SCAN_RESULT" | grep "Scanned files:\|Infected files:\|Data scanned:\|Data read:\|Time:")
else
    MALWARE_STATUS="🚨 THREATS DETECTED"
    INFECTED_FILES=$(echo "$SCAN_RESULT" | grep "Infected files:" | awk '{print $3}')
    SCAN_SUMMARY=$(echo "$SCAN_RESULT" | grep "Scanned files:\|Infected files:\|Data scanned:\|Data read:\|Time:")
    echo "$SCAN_RESULT" | grep "FOUND" >> "$REPORT_FILE"
fi

{
    echo "🔍 MALWARE SCAN RESULTS"
    echo "--------------------------------"
    echo "Status: $MALWARE_STATUS"
    echo "Scan Summary:"
    echo "$SCAN_SUMMARY"
    echo ""
    echo "📊 SYSTEM STATUS"
    echo "--------------------------------"
    echo "CrowdSec: $(systemctl is-active crowdsec 2>/dev/null || echo 'inactive')"
    echo "File Monitor: $(systemctl is-active file-monitor.service 2>/dev/null || echo 'inactive')"
    echo "ClamAV Monitor: $(systemctl is-active clamav-monitor.service 2>/dev/null || echo 'inactive')"
} >> "$REPORT_FILE"

log "END: Daily security scan completed"

# Send notification
MESSAGE_SUMMARY="📊 Daily Security Scan Complete
🖥️ Server: $(hostname)
📅 Date: $(date '+%Y-%m-%d')
🔍 Malware Scan: $MALWARE_STATUS
📈 Status: $(if echo "$MALWARE_STATUS" | grep -q "🚨"; then echo "❌ NEEDS ATTENTION"; else echo "✅ ALL CLEAR"; fi)"

send_telegram_notification "$MESSAGE_SUMMARY"

# Urgent notification for threats
if echo "$MALWARE_STATUS" | grep -q "🚨"; then
    URGENT_MESSAGE="🚨 URGENT: Malware detected in daily scan
🖥️ Server: $(hostname)
🔍 Infected Files: $INFECTED_FILES
⚠️ Immediate review required!"
    send_telegram_notification "$URGENT_MESSAGE"
fi
