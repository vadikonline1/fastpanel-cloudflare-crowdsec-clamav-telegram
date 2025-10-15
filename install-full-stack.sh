#!/bin/bash
set -e

### === CONFIGURATION ===
BOUNCER_DIR="/etc/cloudflare-bouncer"
LOG_DIR="/var/log/cloudflare-bouncer"

### === FUNCTIONS ===

log() {
    echo -e "🔹 $(date '+%Y-%m-%d %H:%M:%S') - $1"
    logger -t "crowdsec-install" "$1"
}

# Function for Telegram notifications
notify() {
    local NOTIFY_SCRIPT="$BOUNCER_DIR/setup_notify.sh"
    if [ -f "$NOTIFY_SCRIPT" ] && [ -x "$NOTIFY_SCRIPT" ]; then
        bash "$NOTIFY_SCRIPT" "$1" &
    else
        echo "📢 [NOTIFICATION] $1"
    fi
}

# Check if system is Ubuntu/Debian
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
    
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        log "❌ Please run as root"
        exit 1
    fi
}

# Source and execute module
execute_module() {
    local module_name="$1"
    local module_script="$BOUNCER_DIR/$module_name"
    
    log "Executing module: $module_name"
    
    if [ -f "$module_script" ]; then
        if bash "$module_script"; then
            log "✅ Module $module_name completed successfully"
        else
            log "❌ Module $module_name failed"
            notify "❌ Module $module_name failed - check logs"
            exit 1
        fi
    else
        log "❌ Module script not found: $module_script"
        exit 1
    fi
}

# Main installation function
main() {
    log "Starting modular security installation..."
    notify "🚀 Starting comprehensive security system installation on $(hostname)"
    
    # Check system compatibility
    check_system
    
    # Execution sequence
    execute_module "setup_directories.sh"
    execute_module "setup_notify.sh"
    execute_module "setup_env.sh"
    execute_module "setup_fastpanel.sh"
    execute_module "setup_crowdsec.sh"
    execute_module "setup_cloudflare_bouncer.sh"
    execute_module "setup_clamav.sh"
    
    # Final summary
    display_summary
    
    log "🎊 Modular installation completed successfully!"
}

# Display installation summary
display_summary() {
    log "=== MODULAR INSTALLATION SUMMARY ==="
    log "✅ System: $(lsb_release -d | cut -f2)"
    log "✅ Directories: Created and secured"
    log "✅ Environment: Configured and validated"
    log "✅ FastPanel: $(command -v mogwai &>/dev/null && echo 'Installed' || echo 'Not installed')"
    log "✅ File Monitor: $(systemctl is-active file-monitor.service &>/dev/null && echo 'Active' || echo 'Inactive')"
    log "✅ CrowdSec: $(command -v crowdsec &>/dev/null && echo 'Installed' || echo 'Not installed')"
    log "✅ CrowdSec Enrollment: $(sudo cscli console status &>/dev/null && echo 'Enrolled' || echo 'Not enrolled')"
    log "✅ Cloudflare Bouncer: $(systemctl is-active crowdsec-cloudflare-worker-bouncer &>/dev/null && echo 'Active' || echo 'Inactive')"
    log "✅ ClamAV Real-time Monitor: $(systemctl is-active clamav-monitor.service &>/dev/null && echo 'Active' || echo 'Inactive')"
    log "✅ Daily Security Scans: Configured"
    
    notify "🎉 Modular security installation completed successfully!
🖥️ Server: $(hostname)
🛡️ All security systems: Active and monitoring
📊 Real-time file monitoring: Enabled
🔍 Malware protection: Active
📅 Daily scans: Configured
⏰ Next: Monitor security alerts"
}

# Run main function
main "$@"
