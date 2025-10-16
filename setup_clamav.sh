#!/bin/bash
set -e

# ==========================
# CONFIG
# ==========================
SCRIPT_DIR="/etc/automation-web-hosting"
LOG_DIR="$SCRIPT_DIR/log"
SERVICE_DIR="/etc/systemd/system"
BOUNCER_DIR="$SCRIPT_DIR"
ENV_FILE="$SCRIPT_DIR/hosting_env.env"
NOTIFY_SCRIPT="$SCRIPT_DIR/telegram_notify.sh"

# Directoare și setări ClamAV
CLAMAV_SCAN_PATHS=("/var/www" "/tmp")
CLAMAV_MAX_FILE_SIZE="25M"
ENABLE_CLAMAV_MONITORING="true"
ENABLE_DAILY_SCANS="true"
DAILY_SCAN_TIME="00:00"

# ==========================
# FUNCTIONS
# ==========================
log() {
    mkdir -p "$LOG_DIR"
    echo -e "🔹 $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_DIR/setup.log"
}

rotate_logs() {
    find "$LOG_DIR" -type f -name "*.log" -mtime +7 -exec rm -f {} \;
    log "✅ Log rotation executed: removed logs older than 7 days"
}

send_telegram_notification() {
    [ -f "$NOTIFY_SCRIPT" ] && [ -x "$NOTIFY_SCRIPT" ] && "$NOTIFY_SCRIPT" "$1"
}

# ==========================
# INSTALLATION FUNCTIONS
# ==========================
install_clamav() {
    log "Installing ClamAV..."
    if ! command -v clamscan &> /dev/null; then
        DEBIAN_FRONTEND=noninteractive apt-get install -y clamav clamav-daemon clamav-freshclam
        freshclam
        systemctl enable clamav-daemon
        systemctl enable clamav-freshclam
        systemctl start clamav-daemon
        log "✅ ClamAV installed and started"
    else
        log "✅ ClamAV already installed"
    fi
}

setup_clamav_services() {
    log "Setting up ClamAV monitoring..."
    chmod 750 "$BOUNCER_DIR/clamav-onchange.sh" || true
    chmod 750 "$BOUNCER_DIR/clamav-daily.sh" || true

    # Create systemd service
    cat > "$SERVICE_DIR/clamav-monitor.service" <<EOF
[Unit]
Description=ClamAV Real-time File Monitor
After=network.target local-fs.target

[Service]
Type=simple
ExecStart=$BOUNCER_DIR/clamav-onchange.sh
Restart=always
RestartSec=5
User=root
WorkingDirectory=$BOUNCER_DIR
EnvironmentFile=$ENV_FILE
StandardOutput=append:$LOG_DIR/clamav-realtime.log
StandardError=append:$LOG_DIR/clamav-realtime.log

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    [ "$ENABLE_CLAMAV_MONITORING" = "true" ] && systemctl enable --now clamav-monitor.service

    # Daily scan cron
    if [ "$ENABLE_DAILY_SCANS" = "true" ]; then
        hour=$(echo "$DAILY_SCAN_TIME" | cut -d: -f1)
        minute=$(echo "$DAILY_SCAN_TIME" | cut -d: -f2)
        (crontab -l 2>/dev/null | grep -v "clamav-daily.sh"; echo "$minute $hour * * * $BOUNCER_DIR/clamav-daily.sh") | crontab -
        log "✅ Daily ClamAV scans scheduled for $DAILY_SCAN_TIME"
    fi
}

install_rkhunter() {
    log "Installing RKHunter..."
    if ! command -v rkhunter &> /dev/null; then
        DEBIAN_FRONTEND=noninteractive apt-get install -y rkhunter
    fi
    log "✅ RKHunter installed"
    # Daily cron
    cat > /etc/cron.d/rkhunter-daily <<EOF
0 2 * * * root /usr/bin/rkhunter --update && /usr/bin/rkhunter --check --sk
EOF
    log "✅ RKHunter daily cron created"
}

install_maldet() {
    log "Installing Maldet..."
    if ! command -v maldet &> /dev/null; then
        wget -qO- http://www.rfxn.com/downloads/maldetect-current.tar.gz | tar -xz -C /tmp
        cd /tmp/maldetect-*
        ./install.sh
        cd -
    fi
    log "✅ Maldet installed"
}

health_check() {
    log "🔍 Verifying services..."
    log "ClamAV Monitor: $(systemctl is-active clamav-monitor.service || echo 'inactive')"
    log "RKHunter cron: $(test -f /etc/cron.d/rkhunter-daily && echo 'present' || echo 'missing')"
}

# ==========================
# MAIN
# ==========================
main() {
    log "🚀 Starting installation of security suite..."
    rotate_logs
    install_clamav
    setup_clamav_services
    install_rkhunter
    install_maldet
    health_check
    send_telegram_notification "✅ Security suite installed and configured"
    log "✅ Security suite setup finished"
}

main "$@"
