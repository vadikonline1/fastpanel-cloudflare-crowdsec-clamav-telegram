#!/bin/bash
set -e

# Load environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/hosting_env.env"
source "${SCRIPT_DIR}/telegram_notify.sh"

log() {
    echo -e "🔹 $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

install_clamav() {
    log "Installing ClamAV..."
    
    if command -v clamscan &> /dev/null; then
        log "✅ ClamAV already installed"
        return 0
    fi
    
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        clamav clamav-daemon clamav-freshclam
    
    # Update virus database
    freshclam && log "✅ ClamAV database updated"
    
    systemctl enable clamav-daemon
    systemctl enable clamav-freshclam
    systemctl start clamav-daemon
    
    log "✅ ClamAV installed and started"
}

setup_file_monitoring() {
    log "Setting up file monitoring service..."
    
    # Create file monitor script
    cat > "$BOUNCER_DIR/file-monitor.sh" << 'EOF'
#!/bin/bash
# File Monitor with Immediate Notifications
# version 002

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/hosting_env.env"
source "${SCRIPT_DIR}/telegram_notify.sh"

LOG_FILE="$LOG_DIR/file-monitor.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

log "START: File monitor started"

while true; do
    inotifywait -r -e create,delete,modify,move \
        --exclude='.*\.(log|tmp|cache|swp|swx)$' \
        --exclude='.*/(cache|temp|logs|\.git)/' \
        --format '%w%f %e %T' \
        --timefmt '%Y-%m-%d %H:%M:%S' \
        $MONITOR_PATHS 2>/dev/null | \
    while read file_path event time; do
        filename=$(basename "$file_path")
        directory=$(dirname "$file_path")
        
        # Determine priority
        case "$event" in
            "CREATE") priority="🟢"; emoji="📄" ;;
            "DELETE") priority="🟡"; emoji="🗑️" ;;
            "MODIFY") priority="🟠"; emoji="✏️" ;;
            *) priority="⚪"; emoji="📁" ;;
        esac
        
        message="$priority $emoji File $event - IMMEDIATE
📂 Directory: $directory  
📄 File: $filename
⏰ Time: $time
🖥️ Server: $(hostname)"
        
        log "EVENT: $file_path - $event"
        send_telegram_notification "$message" &
    done
    sleep 3
done
EOF

    chmod 750 "$BOUNCER_DIR/file-monitor.sh"
    
    # Create systemd service
    cat > "$SERVICE_DIR/file-monitor.service" << EOF
[Unit]
Description=File System Monitor
After=network.target

[Service]
Type=simple
ExecStart=$BOUNCER_DIR/file-monitor.sh
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable file-monitor.service
    systemctl start file-monitor.service
    
    log "✅ File monitoring service configured"
}

setup_clamav_services() {
    log "Setting up ClamAV monitoring services..."
    
    # Make scripts executable
    chmod 750 "$BOUNCER_DIR/clamav-onchange.sh"
    chmod 750 "$BOUNCER_DIR/clamav-daily.sh"
    
    # Create systemd service for real-time monitoring
    cat > "$SERVICE_DIR/clamav-monitor.service" << EOF
[Unit]
Description=ClamAV Real-time File Monitor
After=network.target clamav-daemon.service

[Service]
Type=simple
ExecStart=$BOUNCER_DIR/clamav-onchange.sh
Restart=always
RestartSec=10
User=root

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    
    if [ "$ENABLE_CLAMAV_MONITORING" = "true" ]; then
        systemctl enable clamav-monitor.service
        systemctl start clamav-monitor.service
        log "✅ ClamAV real-time monitoring enabled"
    fi
    
    # Schedule daily scans
    if [ "$ENABLE_DAILY_SCANS" = "true" ]; then
        local hour=$(echo "$DAILY_SCAN_TIME" | cut -d: -f1)
        local minute=$(echo "$DAILY_SCAN_TIME" | cut -d: -f2)
        (crontab -l 2>/dev/null | grep -v "clamav-daily.sh"; echo "$minute $hour * * * $BOUNCER_DIR/clamav-daily.sh") | crontab -
        log "✅ Daily ClamAV scans scheduled for $DAILY_SCAN_TIME"
    fi
}

main() {
    log "Starting ClamAV setup..."
    install_clamav
    setup_file_monitoring
    setup_clamav_services
    send_telegram_notification "✅ ClamAV protection system installed and configured"
    log "✅ ClamAV setup completed"
}

main "$@"
