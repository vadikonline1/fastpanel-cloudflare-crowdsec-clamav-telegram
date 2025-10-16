#!/bin/bash
#set -e

# =============================================================================
# MAIN HOSTING AUTOMATION INSTALLATION SCRIPT
# =============================================================================
FASTPANEL_LOG="/var/www/fastuser/data/log/clam_log"
# Load environment and utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/hosting_env.env"
source "${SCRIPT_DIR}/telegram_notify.sh"

# Logging function
log() {
    echo -e "🔹 $(date '+%Y-%m-%d %H:%M:%S') - $1"
    logger -t "hosting-automation" "$1"
}

# Prepare system: update and install required packages
prepare_system() {
    log "Updating system packages and installing dependencies..."

    # Update and upgrade
    apt update && apt -y upgrade

    # List of required packages
    local packages=(
        mc
        inotify-tools
        clamav
        clamav-daemon
        curl
        jq
        sudo
    )

    # Install packages if not already installed
    for pkg in "${packages[@]}"; do
        if ! dpkg -s "$pkg" &> /dev/null; then
            log "Installing missing package: $pkg"
            apt install -y "$pkg"
        else
            log "✅ Package already installed: $pkg"
        fi
    done

    # Ensure inotifywait is available (from inotify-tools)
    if ! command -v inotifywait &> /dev/null; then
        log "❌ inotifywait not found even after installing inotify-tools"
        exit 1
    fi

    # Update ClamAV database
    log "Updating ClamAV virus definitions..."
    systemctl stop clamav-freshclam.service || true
    freshclam || log "⚠️ ClamAV database update failed"
    systemctl start clamav-freshclam.service || true

    log "✅ System preparation complete"
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

    local failed_steps=()

    # Dezactivăm oprirea automată la erori
    set +e

    for step in "${steps[@]}"; do
        local script="${step%%:::*}"
        local description="${step##*:::}"

        log "➡️ $description"
        if [ -f "$SCRIPT_DIR/$script" ]; then
            bash "$SCRIPT_DIR/$script"
            local status=$?
            if [ $status -eq 0 ]; then
                log "✅ $description - SUCCESS"
            else
                log "❌ $description - FAILED (exit code: $status)"
                failed_steps+=("$description")
            fi
        else
            log "❌ Script not found: $script"
            failed_steps+=("$description (missing script)")
        fi
    done

    # Reactivăm comportamentul normal
    set -e

    # Dacă ceva a eșuat, trimite raport, dar nu opri instalarea complet
    if [ ${#failed_steps[@]} -gt 0 ]; then
        log "⚠️  Some installation steps failed:"
        for fail in "${failed_steps[@]}"; do
            log "   - $fail"
        done
        send_telegram_notification "⚠️ Installation finished with errors on $(hostname)
Failed steps:
$(printf '%s\n' "${failed_steps[@]}")"
    fi
}


# Final configuration and startup
final_setup() {
    log "Performing final configuration..."
    
    # Set proper permissions
    chmod 750 "$BOUNCER_DIR"
    chmod 600 "$SCRIPT_DIR/hosting_env.env"
    chmod 750 "$SCRIPT_DIR"/*.sh
    
    sudo mkdir -p "$FASTPANEL_LOG"
    sudo mount --bind /etc/automation-web-hosting/log "$FASTPANEL_LOG"
    echo "/etc/automation-web-hosting/log "$FASTPANEL_LOG" none bind 0 0" | sudo tee -a /etc/fstab
    sudo mount -a
    sudo chown -R fastuser:fastuser "$FASTPANEL_LOG"
    sudo chmod -R 755 "$FASTPANEL_LOG"

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
    prepare_system
    
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
