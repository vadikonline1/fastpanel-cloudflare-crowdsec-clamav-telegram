#!/bin/bash
set -e

# === CONFIG ===
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

SCRIPT_DIR="/etc/automation-web-hosting"
ENV_FILE="$SCRIPT_DIR/hosting_env.env"
NOTIFY_SCRIPT="$SCRIPT_DIR/telegram_notify.sh"
LOG_FILE="$SCRIPT_DIR/log/clamav-realtime.log"
PID_FILE="$SCRIPT_DIR/clamav-monitor.pid"

# === FUNCTIE LOG ===
log() {
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$message" >> "$LOG_FILE"
}

# === INIT LOG ===
mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"
chmod 644 "$LOG_FILE"

log "=== ClamAV Monitor - START ==="

# === VERIFICARE INSTANTA DUPLA ===
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE")
    if kill -0 "$OLD_PID" 2>/dev/null; then
        log "ERROR: Another instance is already running (PID: $OLD_PID)"
        exit 1
    else
        log "WARNING: Stale PID file found, removing..."
        rm -f "$PID_FILE"
    fi
fi

echo $$ > "$PID_FILE"

# === VARIABILA PENTRU EVITARE DUPLICARE ===
CLEANUP_DONE=0

# === FUNCTIE CLEANUP ===
cleanup() {
    if [ $CLEANUP_DONE -eq 1 ]; then
        return
    fi
    CLEANUP_DONE=1
    
    log "Sending stop notification..."
    STOP_MESSAGE="🔴 ClamAV Monitor Stopped
🖥️ Server: $(hostname)
⏰ Time: $(date '+%Y-%m-%d %H:%M:%S')"
    
    if TELEGRAM_BOT_TOKEN="$TELEGRAM_BOT_TOKEN" TELEGRAM_CHAT_ID="$TELEGRAM_CHAT_ID" "$NOTIFY_SCRIPT" "$STOP_MESSAGE"; then
        log "✅ Stop notification sent"
    else
        log "❌ Failed to send stop notification"
    fi

    rm -f "$PID_FILE"
    log "=== ClamAV Monitor - STOP ==="
}

trap cleanup EXIT

# === INCARCA MEDIUL ===
if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
    export TELEGRAM_BOT_TOKEN
    export TELEGRAM_CHAT_ID
    log "Environment loaded from: $ENV_FILE"
else
    log "ERROR: No env file found at $ENV_FILE"
    exit 1
fi

# === VERIFICARE VARIABILE TELEGRAM ===
if [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
    log "ERROR: Telegram variables not set"
    exit 1
fi

# === VERIFICARE COMENZI ===
INOTIFYWAIT_CMD=$(command -v inotifywait)
CLAMSCAN_CMD=$(command -v clamscan)

if [ -z "$INOTIFYWAIT_CMD" ]; then
    log "ERROR: inotifywait not found. Install inotify-tools package."
    exit 1
fi

if [ -z "$CLAMSCAN_CMD" ]; then
    log "ERROR: clamscan not found. Install clamav package."
    exit 1
fi

log "Tools found: inotifywait=$INOTIFYWAIT_CMD, clamscan=$CLAMSCAN_CMD"

# === VERIFICARE SCRIPT NOTIFICARE ===
if [ ! -f "$NOTIFY_SCRIPT" ]; then
    log "ERROR: Notification script not found: $NOTIFY_SCRIPT"
    exit 1
fi

if [ ! -x "$NOTIFY_SCRIPT" ]; then
    log "WARNING: Notification script not executable, fixing..."
    chmod +x "$NOTIFY_SCRIPT"
fi

# === NOTIFICARE LA PORNIRE ===
log "Sending startup notification..."
START_MESSAGE="🟢 ClamAV Monitor Started
🖥️ Server: $(hostname)
⏰ Time: $(date '+%Y-%m-%d %H:%M:%S')
📂 Monitoring: /var/www, /tmp"

if TELEGRAM_BOT_TOKEN="$TELEGRAM_BOT_TOKEN" TELEGRAM_CHAT_ID="$TELEGRAM_CHAT_ID" "$NOTIFY_SCRIPT" "$START_MESSAGE"; then
    log "✅ Startup notification sent successfully"
else
    log "❌ Startup notification failed"
fi

# === MONITOR PATHS ===
MONITOR_PATHS=("/var/www" "/tmp")
for path in "${MONITOR_PATHS[@]}"; do
    if [ ! -d "$path" ]; then
        log "WARNING: Monitor path does not exist: $path"
    else
        log "Monitoring path: $path"
    fi
done

# === SCAN FUNCTION IMBUNATATITA ===
scan_file() {
    local file_path="$1"
    local file_id="$(date +%s%N)"

    log "[$file_id] SCAN_FILE called: $file_path"

    if [ ! -f "$file_path" ]; then
        log "[$file_id] File does not exist, skipping: $file_path"
        return
    fi

    # Exclude fișiere temporare
    if [[ "$file_path" =~ \.(log|tmp|cache|swp|swx|lock)$ ]]; then
        log "[$file_id] Temporary file, skipping: $file_path"
        return
    fi

    # Așteaptă să se completeze scrierea
    sleep 2

    if [ ! -f "$file_path" ]; then
        log "[$file_id] File disappeared after sleep: $file_path"
        return
    fi

    local file_size
    file_size=$(stat -c%s "$file_path" 2>/dev/null || echo 0)
    
    if [ "$file_size" -eq 0 ]; then
        log "[$file_id] Empty file, skipping: $file_path"
        return
    fi

    log "[$file_id] Scanning file: $file_path ($file_size bytes)"

    # Scanare cu gestionare mai bună a output-ului
    local output
    local exit_code=0
    
    # Folosește un fișier temporar pentru output
    local temp_output="/tmp/clamscan_${file_id}.txt"
    
    # Rulează clamscan și capturează output-ul
    output=$($CLAMSCAN_CMD --infected --remove "$file_path" 2>&1) || exit_code=$?
    
    log "[$file_id] Clamscan finished with exit code: $exit_code"
    log "[$file_id] Clamscan output: $output"

    # Verifică rezultatul scanării
    if echo "$output" | grep -q "FOUND"; then
        threat=$(echo "$output" | grep "FOUND" | awk -F': ' '{print $NF}' | awk '{print $1}')
        log "[$file_id] 🚨 INFECTED REMOVED: $file_path (Threat: ${threat:-Unknown})"
        
        # Notificare Telegram
        MALWARE_MESSAGE="🚨 MALWARE DETECTED & REMOVED
📁 File: $(basename "$file_path")
📂 Path: $(dirname "$file_path")  
🦠 Threat: ${threat:-Unknown}
🖥️ Server: $(hostname)
⏰ Time: $(date '+%Y-%m-%d %H:%M:%S')
🔒 Action: File automatically removed"

        log "[$file_id] Sending Telegram notification..."
        
        if TELEGRAM_BOT_TOKEN="$TELEGRAM_BOT_TOKEN" TELEGRAM_CHAT_ID="$TELEGRAM_CHAT_ID" "$NOTIFY_SCRIPT" "$MALWARE_MESSAGE"; then
            log "[$file_id] ✅ Telegram notification sent successfully"
        else
            log "[$file_id] ❌ Telegram notification failed"
        fi

    elif [ $exit_code -eq 0 ]; then
        log "[$file_id] ✅ CLEAN: $file_path"
    elif [ $exit_code -eq 1 ]; then
        # Clamscan returnează 1 pentru virus găsit (după --remove)
        if echo "$output" | grep -q "FOUND"; then
            threat=$(echo "$output" | grep "FOUND" | awk -F': ' '{print $NF}' | awk '{print $1}')
            log "[$file_id] 🚨 INFECTED REMOVED (exit 1): $file_path (Threat: ${threat:-Unknown})"
            
            MALWARE_MESSAGE="🚨 MALWARE DETECTED & REMOVED
📁 File: $(basename "$file_path")
📂 Path: $(dirname "$file_path")  
🦠 Threat: ${threat:-Unknown}
🖥️ Server: $(hostname)
⏰ Time: $(date '+%Y-%m-%d %H:%M:%S')
🔒 Action: File automatically removed"

            log "[$file_id] Sending Telegram notification..."
            
            if TELEGRAM_BOT_TOKEN="$TELEGRAM_BOT_TOKEN" TELEGRAM_CHAT_ID="$TELEGRAM_CHAT_ID" "$NOTIFY_SCRIPT" "$MALWARE_MESSAGE"; then
                log "[$file_id] ✅ Telegram notification sent successfully"
            else
                log "[$file_id] ❌ Telegram notification failed"
            fi
        else
            log "[$file_id] ⚠️ UNKNOWN RESULT (exit 1): $file_path (output: $output)"
        fi
    elif [ $exit_code -eq 124 ]; then
        log "[$file_id] ⚠️ SCAN TIMEOUT: $file_path"
    elif [ $exit_code -eq 2 ]; then
        log "[$file_id] ⚠️ SCAN ERROR: $file_path (exit code: $exit_code, output: $output)"
    else
        log "[$file_id] ⚠️ UNKNOWN RESULT: $file_path (exit code: $exit_code, output: $output)"
    fi
    
    # Curăță fișierul temporar dacă există
    rm -f "$temp_output" 2>/dev/null || true
}

# === MAIN MONITOR LOOP ===
log "=== Starting monitor loop ==="

# Verifică dacă inotifywait poate rula
log "Testing inotifywait..."
if timeout 5s $INOTIFYWAIT_CMD -r -e close_write --format '%w%f' "/tmp" 2>&1 | head -5; then
    log "inotifywait test successful"
else
    log "ERROR: inotifywait test failed"
    exit 1
fi

log "=== Starting continuous monitoring ==="

# Rulează monitorizarea continuă
$INOTIFYWAIT_CMD -m -r -q -e close_write -e moved_to \
    --exclude='.*\.(log|tmp|cache|swp|swx|lock)$' \
    --format '%w%f' \
    "${MONITOR_PATHS[@]}" | while read -r file_path; do
        log "📁 EVENT DETECTED: $file_path"
        scan_file "$file_path" &
    done

log "=== Monitor loop ended ==="
