#!/bin/bash
set -e

# Load environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/hosting_env.env"
source "${SCRIPT_DIR}/telegram_notify.sh"

LOG_FILE="$LOG_DIR/clamav-realtime.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

log "START: ClamAV real-time monitor started"

while true; do
    inotifywait -r -e close_write,moved_to \
        --exclude='.*\.(log|tmp|cache|swp|swx)$' \
        --format '%w%f %e %T' \
        --timefmt '%Y-%m-%d %H:%M:%S' \
        $CLAMAV_MONITOR_PATHS 2>/dev/null | \
    while read file_path event time; do
        if [ ! -f "$file_path" ]; then
            continue
        fi
        
        log "SCANNING: $file_path"
        SCAN_RESULT=$(clamscan --max-filesize="$CLAMAV_MAX_FILE_SIZE" "$file_path" 2>&1)
        
        if echo "$SCAN_RESULT" | grep -q "Infected files: 0"; then
            log "CLEAN: $file_path"
        else
            THREAT=$(echo "$SCAN_RESULT" | grep -o "FOUND: .*" | cut -d':' -f2 | xargs || echo "Unknown")
            
            # Quarantine file
            mkdir -p "$CLAMAV_QUARANTINE_DIR"
            mv "$file_path" "$CLAMAV_QUARANTINE_DIR/" 2>/dev/null
            
            MESSAGE="🚨 MALWARE DETECTED - REAL-TIME
📁 File: $(basename "$file_path")
📂 Path: $(dirname "$file_path")  
🦠 Threat: $THREAT
⏰ Time: $time
🖥️ Server: $(hostname)
🔒 Action: File quarantined"
            
            log "THREAT: $file_path - $THREAT"
            send_telegram_notification "$MESSAGE" &
        fi
    done
    sleep 5
done
