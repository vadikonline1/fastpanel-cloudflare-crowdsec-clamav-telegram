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

setup_clamav_services() {
    log "Setting up ClamAV monitoring services..."
    
    # Make scripts executable
    chmod 750 "$BOUNCER_DIR/clamav-onchange.sh"
    chmod 750 "$BOUNCER_DIR/clamav-daily.sh"
    
    # Create systemd service for real-time monitoring
    cat > "$SERVICE_DIR/clamav-monitor.service" << EOF
[Unit]
Description=ClamAV Real-time File Monitor
After=network.target local-fs.target
Wants=network.target

[Service]
Type=simple
ExecStart=/etc/automation-web-hosting/clamav-onchange.sh
Restart=always
RestartSec=5
User=root
WorkingDirectory=/etc/automation-web-hosting
EnvironmentFile=/etc/automation-web-hosting/hosting_env.env
StandardOutput=append:/etc/automation-web-hosting/log/clamav-realtime.log
StandardError=append:/etc/automation-web-hosting/log/clamav-realtime.log
NoNewPrivileges=yes
PrivateTmp=no
ProtectSystem=no
ProtectHome=no

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
    setup_clamav_services
    send_telegram_notification "✅ ClamAV protection system installed and configured"
    log "✅ ClamAV setup completed"
}

main "$@"
