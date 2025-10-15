#!/bin/bash
set -e

# === CONFIG ===
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

SCRIPT_DIR="/etc/automation-web-hosting"
ENV_FILE="$SCRIPT_DIR/hosting_env.env"
NOTIFY_SCRIPT="$SCRIPT_DIR/telegram_notify.sh"
LOG_FILE="$SCRIPT_DIR/log/clamav-realtime.log"

# === INIT LOG ===
mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"
chmod 644 "$LOG_FILE"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

log "=== ClamAV Monitor - Start ==="

# === ENVIRONMENT ===
if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
    log "Environment loaded from: $ENV_FILE"
else
    log "WARNING: No env file found at $ENV_FILE"
fi

# === COMMAND CHECK ===
INOTIFYWAIT_CMD=$(command -v inotifywait)
CLAMSCAN_CMD=$(command -v clamscan)

if [ -z "$INOTIFYWAIT_CMD" ] || [ -z "$CLAMSCAN_CMD" ]; then
    log "ERROR: Required tools missing (inotifywait or clamscan)"
    exit 1
fi

log "Using: $INOTIFYWAIT_CMD and $CLAMSCAN_CMD"

# === MONITOR PATHS ===
MONITOR_PATHS=("/var/www" "/tmp")
log "Monitoring: ${MONITOR_PATHS[*]}"

# === SCAN FUNCTION ===
scan_file() {
    local file_path="$1"

    # Doar fișiere regulate
    if [ ! -f "$file_path" ]; then
        return
    fi

    # Ignoră fișiere temporare, cache etc.
    if [[ "$file_path" =~ \.(log|tmp|cache|swp|swx|lock)$ ]]; then
        return
    fi

    sleep 1  # asigură că fișierul e complet scris

    local file_size
    file_size=$(stat -c%s "$file_path" 2>/dev/null || echo 0)
    log "🔍 SCAN START: $file_path ($file_size bytes)"

    # Rulează clamscan cu --infected --remove
    local output
# Run scan and capture output
output=$($CLAMSCAN_CMD --infected --remove "$file_path" 2>&1)
exit_code=$?

# Detect infection based on output, not just exit code
if echo "$output" | grep -q "FOUND"; then
    threat=$(echo "$output" | grep "FOUND" | sed 's/.*: //; s/ FOUND.*//')
    log "🚨 INFECTED REMOVED: $file_path (Threat: ${threat:-Unknown})"
    
    # Optional: Telegram notification
    if [ -f "$NOTIFY_SCRIPT" ] && [ -x "$NOTIFY_SCRIPT" ]; then
        message="🚨 MALWARE DETECTED & REMOVED
📁 File: $(basename "$file_path")
📂 Path: $(dirname "$file_path")
🦠 Threat: ${threat:-Unknown}
🖥️ Server: $(hostname)
⏰ Time: $(date '+%Y-%m-%d %H:%M:%S')
🔒 Action: File automatically removed"
        $NOTIFY_SCRIPT "$message" &
    fi

elif [ $exit_code -eq 0 ]; then
    log "✅ CLEAN: $file_path"
elif [ $exit_code -eq 2 ]; then
    log "⚠️ SCAN ERROR: $file_path (exit code: $exit_code)"
else
    log "⚠️ UNKNOWN RESULT: $file_path (exit code: $exit_code)"
fi

            ;;
        *)
            log "⚠️ SCAN ERROR: $file_path (Exit $exit_code)"
            ;;
    esac
}

# === MAIN MONITOR LOOP ===
log "=== Monitoring started ==="
$INOTIFYWAIT_CMD -m -r -q -e close_write -e moved_to \
    --exclude='.*\.(log|tmp|cache|swp|swx|lock)$' \
    --format '%w%f' \
    "${MONITOR_PATHS[@]}" | while read -r file_path; do
        log "📁 EVENT: $file_path"
        scan_file "$file_path" &
    done
