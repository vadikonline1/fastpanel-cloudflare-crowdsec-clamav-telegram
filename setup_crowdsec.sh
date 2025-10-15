#!/bin/bash
set -e

# Load environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/hosting_env.env"
source "${SCRIPT_DIR}/telegram_notify.sh"

log() {
    echo -e "🔹 $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

install_crowdsec() {
    log "Checking CrowdSec installation..."
    
    if command -v crowdsec &> /dev/null; then
        log "✅ CrowdSec is already installed"
        
        if sudo cscli console status &>/dev/null; then
            log "✅ CrowdSec already enrolled"
            return 0
        fi
        
        if [ -n "$DASHBOARD_API_KEY" ]; then
            log "Enrolling to CrowdSec console..."
            if sudo cscli console enroll "$DASHBOARD_API_KEY"; then
                log "✅ CrowdSec enrolled successfully"
            fi
        fi
        return 0
    fi
    
    log "Installing CrowdSec..."
    send_telegram_notification "🔄 Installing CrowdSec security system..."
    
    if curl -s https://install.crowdsec.net | sudo sh; then
        log "✅ CrowdSec installed successfully"
        
        if apt install -y crowdsec; then
            # Enroll to console
            if [ -n "$DASHBOARD_API_KEY" ]; then
                sudo cscli console enroll "$DASHBOARD_API_KEY" && \
                log "✅ CrowdSec enrolled to console"
            fi
            
            systemctl enable crowdsec
            systemctl start crowdsec
            log "✅ CrowdSec service started"
        else
            log "❌ Failed to install crowdsec package"
            return 1
        fi
    else
        log "❌ Failed to install CrowdSec"
        return 1
    fi
}

install_collections() {
    log "Installing CrowdSec collections..."
    
    cscli hub update
    
    local collections=(
        "crowdsecurity/linux"
        "crowdsecurity/sshd" 
        "crowdsecurity/nginx"
        "crowdsecurity/apache2"
        "crowdsecurity/base-http-scenarios"
    )
    
    for col in "${collections[@]}"; do
        if ! cscli collections list | grep -q "$col"; then
            cscli collections install "$col" && \
            log "✅ Installed: $col"
        else
            log "✅ Already installed: $col"
        fi
    done
}

configure_acquis() {
    log "Configuring acquis.yaml..."
    
    if [ -f "$ACQUIS_FILE" ] && grep -q "fastpanel-frontend" "$ACQUIS_FILE"; then
        log "✅ Acquis configuration exists"
        return 0
    fi
    
    # Backup existing file
    [ -f "$ACQUIS_FILE" ] && cp "$ACQUIS_FILE" "$ACQUIS_FILE.bak.$(date +%s)"
    
    cat > "$ACQUIS_FILE" << EOF
filenames:
  - /var/log/nginx/access.log
  - /var/log/nginx/error.log
labels:
  type: nginx
---
filenames:
  - /var/www/*/data/logs/*-backend.access.log
  - /var/www/*/data/logs/*-frontend.access.log
  - /var/www/*/data/logs/*-backend.error.log
  - /var/www/*/data/logs/*-frontend.error.log
labels:
  type: nginx
---
filenames:
  - /var/log/apache2/access.log
  - /var/log/apache2/error.log
  - /var/log/apache2/other_vhosts_access.log
labels:
  type: apache2
---
filenames:
  - /var/log/auth.log
  - /var/log/syslog
labels:
  type: syslog
EOF

    systemctl restart crowdsec
    log "✅ Acquis configured and service restarted"
}

main() {
    log "Starting CrowdSec setup..."
    install_crowdsec
    install_collections
    configure_acquis
    send_telegram_notification "✅ CrowdSec security system installed and configured"
    log "✅ CrowdSec setup completed"
}

main "$@"
