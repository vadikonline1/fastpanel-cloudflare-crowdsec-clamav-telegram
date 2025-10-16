#!/bin/bash
set -e

# === CONFIG ===
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/hosting_env.env"
NOTIFY_SCRIPT="$SCRIPT_DIR/telegram_notify.sh"

[ -f "$ENV_FILE" ] && source "$ENV_FILE"
[ -f "$NOTIFY_SCRIPT" ] && source "$NOTIFY_SCRIPT"

LOG_DIR="${LOG_DIR:-$SCRIPT_DIR/log}"
REPORT_FILE="$LOG_DIR/weekly-report-$(date +%Y%m%d).log"
RETENTION_DAYS=30

mkdir -p "$LOG_DIR"
touch "$REPORT_FILE"
chmod 644 "$REPORT_FILE"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$REPORT_FILE"
}

# === CLEAN OLD REPORTS ===
find "$LOG_DIR" -type f -name "weekly-report-*.log" -mtime +$RETENTION_DAYS -delete 2>/dev/null || true

log "📊 START: Weekly security & performance report"

# === SERVER INFO ===
{
    echo "🧾 WEEKLY SERVER HEALTH REPORT"
    echo "====================================="
    echo "🖥️ Hostname: $(hostname)"
    echo "📅 Date: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "🕓 Uptime: $(uptime -p)"
    echo ""
} > "$REPORT_FILE"

# === SYSTEM PERFORMANCE ===
{
    echo "⚙️ SYSTEM PERFORMANCE"
    echo "-------------------------------------"
    echo "CPU Load (1/5/15 min): $(awk '{print $1" "$2" "$3}' /proc/loadavg)"
    echo "Memory Usage:"
    free -h | awk 'NR==1 || NR==2 {print}'
    echo ""
    echo "Disk Usage:"
    df -h --total | grep -E '^(/|total)' | awk '{printf "%-20s %-10s %-10s %-10s %-10s\n", $1, $2, $3, $4, $5}'
    echo ""
} >> "$REPORT_FILE"

# === TOP RESOURCE CONSUMERS ===
{
    echo "🔥 TOP 5 CPU PROCESSES"
    echo "-------------------------------------"
    ps -eo pid,comm,%cpu,%mem --sort=-%cpu | head -n 6
    echo ""
    echo "🔥 TOP 5 MEMORY PROCESSES"
    echo "-------------------------------------"
    ps -eo pid,comm,%mem,%cpu --sort=-%mem | head -n 6
    echo ""
} >> "$REPORT_FILE"

# === CLAMAV STATS (from last 7 days logs) ===
if ls "$LOG_DIR"/clamav-daily.log* >/dev/null 2>&1; then
    log "Analyzing ClamAV logs..."
    INFECTED_COUNT=$(grep -h "🚨" "$LOG_DIR"/clamav-daily.log* | wc -l)
    CLEAN_COUNT=$(grep -h "✅ CLEAN" "$LOG_DIR"/clamav-daily.log* | wc -l)
    echo "🧬 CLAMAV SUMMARY (last 7 days)" >> "$REPORT_FILE"
    echo "-------------------------------------" >> "$REPORT_FILE"
    echo "✅ Clean files scanned: $CLEAN_COUNT" >> "$REPORT_FILE"
    echo "🚨 Infected detections: $INFECTED_COUNT" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
else
    echo "🧬 ClamAV logs not found, skipping..." >> "$REPORT_FILE"
fi

# === SECURITY TOOLS STATUS ===
{
    echo "🛡️ SECURITY SERVICES STATUS"
    echo "-------------------------------------"
    echo "CrowdSec: $(systemctl is-active crowdsec 2>/dev/null || echo 'inactive')"
    echo "ClamAV Realtime: $(systemctl is-active clamav-monitor.service 2>/dev/null || echo 'inactive')"
    echo "File Monitor: $(systemctl is-active file-monitor.service 2>/dev/null || echo 'inactive')"
    echo "Fail2Ban: $(systemctl is-active fail2ban 2>/dev/null || echo 'inactive')"
    echo ""
} >> "$REPORT_FILE"

# === ROOTKIT CHECK SUMMARY (optional) ===
if [ -f /var/log/rkhunter.log ]; then
    log "Analyzing RKHunter logs..."
    RKH_WARN=$(grep -c "Warning:" /var/log/rkhunter.log || echo 0)
    echo "🕵️ RKHUNTER SUMMARY" >> "$REPORT_FILE"
    echo "-------------------------------------" >> "$REPORT_FILE"
    echo "Warnings found: $RKH_WARN" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
fi

# === SUMMARY STATUS ===
if grep -q "🚨" "$REPORT_FILE"; then
    OVERALL_STATUS="❌ Issues Found"
else
    OVERALL_STATUS="✅ Server Healthy"
fi

# === TELEGRAM MESSAGE ===
SUMMARY_MSG="📊 Weekly Security Report
🖥️ $(hostname)
📅 $(date '+%Y-%m-%d')
💾 Load: $(awk '{print $1" "$2" "$3}' /proc/loadavg)
🔍 ClamAV: $(grep -h '🚨' "$LOG_DIR"/clamav-daily.log* | wc -l) infections this week
🕵️ RKHunter: $(grep -c 'Warning:' /var/log/rkhunter.log 2>/dev/null || echo 0) warnings
📈 Status: $OVERALL_STATUS"

send_telegram_notification "$SUMMARY_MSG"

# === END ===
log "✅ Weekly report completed successfully"
exit 0
