#!/bin/bash
set -e

# ==========================
# SCRIPT DIRECTORY
# ==========================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

# Load the first .env file found in script directory
ENV_FILE=$(find "$SCRIPT_DIR" -maxdepth 1 -name "*.env" | head -n 1)
if [ -z "$ENV_FILE" ]; then
    echo "❌ No .env file found in $SCRIPT_DIR. Exiting."
    exit 1
fi
source "$ENV_FILE"

# Telegram notification script
NOTIFY_SCRIPT="$SCRIPT_DIR/telegram_notify.sh"

# Log directory
LOG_DIR="/etc/automation-web-hosting/log"
mkdir -p "$LOG_DIR"

# ==========================
# FUNCTIONS
# ==========================
log() {
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
Wants=network.target

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
NoNewPrivileges=yes
PrivateTmp=no
ProtectSystem=no
ProtectHome=no

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

    # Daily cron in /etc/cron.d
    cat > /etc/cron.d/rkhunter-daily <<EOF
0 2 * * * root /usr/bin/rkhunter --update && /usr/bin/rkhunter --check --sk >> $LOG_DIR/rkhunter.log 2>&1
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
    log "Maldet: $(command -v maldet &> /dev/null && echo 'installed' || echo 'missing')"
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
