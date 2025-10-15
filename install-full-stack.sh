#!/bin/bash
set -e

# =============================================================================
# MAIN HOSTING AUTOMATION INSTALLATION SCRIPT
# =============================================================================

# Load environment and utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/hosting_env.env"
source "${SCRIPT_DIR}/telegram_notify.sh"

# Logging function
log() {
    echo -e "🔹 $(date '+%Y-%m-%d %H:%M:%S') - $1"
    logger -t "hosting-automation" "$1"
}

# Display banner
display_banner() {
    echo "=================================================="
    echo "    HOSTING AUTOMATION FULL-STACK INSTALLATION"
    echo "=================================================="
    echo "📁 Directory: $BOUNCER_DIR"
    echo "📝 Logs: $LOG_DIR"
    echo "🛡️  Security: CrowdSec + ClamAV + Cloudflare"
    echo "=================================================="
}

# Check system compatibility
check_system() {
    log "Checking system compatibility..."
    
    if [ ! -f /etc/debian_version ] && [ ! -f /etc/lsb-release ]; then
        log "❌ This script is only for Debian/Ubuntu systems"
        exit 1
    fi
    
    if command -v lsb_release >/dev/null 2>&1; then
        DISTRO=$(lsb_release -d | cut -f2)
        log "✅ System verified: $DISTRO"
    else
        log "✅ Debian/Ubuntu system detected"
    fi
    
    if [ "$EUID" -ne 0 ]; then
        log "❌ Please run as root"
        exit 1
    fi
}

# Validate environment
validate_environment() {
    log "Validating environment configuration..."
    
    # Check if environment file exists
    if [ ! -f "$SCRIPT_DIR/hosting_env.env" ]; then
        log "❌ Environment file not found: hosting_env.env"
        log "Please create the environment file with your configuration"
        exit 1
    fi
    
    # Load environment
    set -o allexport
    source "$SCRIPT_DIR/hosting_env.env"
    set +o allexport
    
    # Validate required variables
    local required_vars=(
        "CF_API_TOKEN" 
        "CF_ACCOUNT_ID" 
        "FASTPANEL_PASSWORD"
        "TELEGRAM_BOT_TOKEN"
        "TELEGRAM_CHAT_ID"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var}" ]] || [[ "${!var}" == *"your_"* ]]; then
            log "❌ Please configure $var in hosting_env.env"
            exit 1
        fi
    done
    
    log "✅ Environment validation completed"
}

# Main installation sequence
main_installation() {
    local steps=(
        "setup_directories.sh:::Creating directory structure"
        "telegram_notify.sh:::Setting up Telegram notifications"
        "setup_fastpanel.sh:::Installing FastPanel"
        "setup_crowdsec.sh:::Installing CrowdSec security"
        "setup_cloudflare_bouncer.sh:::Configuring Cloudflare bouncer"
        "setup_clamav.sh:::Setting up ClamAV protection"
    )
    
    for step in "${steps[@]}"; do
        local script="${step%%:::*}"
        local description="${step##*:::}"
        
        log "➡️ $description"
        if [ -f "$SCRIPT_DIR/$script" ]; then
            if bash "$SCRIPT_DIR/$script"; then
                log "✅ $description - SUCCESS"
            else
                log "❌ $description - FAILED"
                return 1
            fi
        else
            log "❌ Script not found: $script"
            return 1
        fi
    done
}

# Final configuration and startup
final_setup() {
    log "Performing final configuration..."
    
    # Set proper permissions
    chmod 750 "$BOUNCER_DIR"
    chmod 600 "$SCRIPT_DIR/hosting_env.env"
    chmod 750 "$SCRIPT_DIR"/*.sh
    
    # Create log rotation
    cat > /etc/logrotate.d/automation-hosting << EOF
/etc/automation-web-hosting/log/clamav-realtime.log {
    daily
    rotate 7
    missingok
    notifempty
    compress
    delaycompress
    create 644 root root
    dateext
    dateformat -%Y%m%d
    postrotate
        systemctl kill -s HUP clamav-monitor.service >/dev/null 2>&1 || true
    endscript
}
EOF

    # Reload systemd
    systemctl daemon-reload
    
    log "✅ Final configuration completed"
}

# Display installation summary
display_summary() {
    log "=== INSTALLATION SUMMARY ==="
    log "✅ System: $(lsb_release -d | cut -f2)"
    log "✅ Directories: $BOUNCER_DIR"
    log "✅ FastPanel: $(command -v mogwai &>/dev/null && echo 'Installed' || echo 'Not installed')"
    log "✅ CrowdSec: $(command -v crowdsec &>/dev/null && echo 'Installed' || echo 'Not installed')"
    log "✅ Cloudflare Bouncer: $(systemctl is-active crowdsec-cloudflare-worker-bouncer &>/dev/null && echo 'Active' || echo 'Inactive')"
    log "✅ ClamAV Monitoring: $(systemctl is-active clamav-monitor.service &>/dev/null && echo 'Active' || echo 'Inactive')"
    log "✅ File Monitoring: $(systemctl is-active file-monitor.service &>/dev/null && echo 'Active' || echo 'Inactive')"
    log "✅ Daily Scans: Scheduled for ${DAILY_SCAN_TIME}"
    
    # Send completion notification
    send_telegram_notification "🎉 Hosting Automation installation completed!
🖥️ Server: $(hostname)
🛡️ All security systems are now active
📊 Monitoring: File changes & malware detection
📅 Daily scans: ${DAILY_SCAN_TIME}
✅ Status: Operational"
}

# Main execution flow
main() {
    display_banner
    check_system
    validate_environment
    
    log "Starting full-stack hosting automation installation..."
    send_telegram_notification "🚀 Starting hosting automation installation on $(hostname)"
    
    if main_installation; then
        final_setup
        display_summary
        log "🎊 Installation completed successfully!"
    else
        log "❌ Installation failed - check logs for details"
        send_telegram_notification "❌ Hosting automation installation failed on $(hostname)"
        exit 1
    fi
}

# Run main function
main "$@"
