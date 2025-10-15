#!/bin/bash
set -e

# Load environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/hosting_env.env"
source "${SCRIPT_DIR}/telegram_notify.sh"

log() {
    echo -e "🔹 $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

generate_lapi_key() {
    log "Generating LAPI key for Cloudflare bouncer..."
    
    if [ -f "$SCRIPT_DIR/hosting_env.env" ] && grep -q '^CROWDSEC_LAPI_KEY=' "$SCRIPT_DIR/hosting_env.env"; then
        current_key=$(grep '^CROWDSEC_LAPI_KEY=' "$SCRIPT_DIR/hosting_env.env" | cut -d '=' -f2- | tr -d '"')
        if [[ -n "$current_key" && "$current_key" != "your_crowdsec_lapi_key_here" ]]; then
            export CROWDSEC_LAPI_KEY="$current_key"
            log "✅ LAPI key already exists"
            return 0
        fi
    fi

    # Generate new key
    if sudo cscli bouncers list -o json | jq -e ".[] | select(.name==\"$BOUNCER_NAME\")" &>/dev/null; then
        LAPI_KEY=$(sudo cscli bouncers list -o json | jq -r ".[] | select(.name==\"$BOUNCER_NAME\") | .api_key")
    else
        LAPI_KEY=$(sudo cscli bouncers add "$BOUNCER_NAME" | awk '/API key for/{getline; getline; gsub(/^ +/, "", $0); print}')
    fi

    # Save to environment file
    if grep -q "^CROWDSEC_LAPI_KEY=" "$SCRIPT_DIR/hosting_env.env" 2>/dev/null; then
        sed -i "s|^CROWDSEC_LAPI_KEY=.*|CROWDSEC_LAPI_KEY=\"$LAPI_KEY\"|" "$SCRIPT_DIR/hosting_env.env"
    else
        echo "CROWDSEC_LAPI_KEY=\"$LAPI_KEY\"" >> "$SCRIPT_DIR/hosting_env.env"
    fi

    export CROWDSEC_LAPI_KEY="$LAPI_KEY"
    log "✅ LAPI key generated and saved"
}

install_cloudflare_bouncer() {
    log "Checking Cloudflare bouncer installation..."
    
    if command -v crowdsec-cloudflare-worker-bouncer &> /dev/null; then
        log "✅ Cloudflare bouncer already installed"
        return 0
    fi
    
    log "Installing Cloudflare bouncer..."
    send_telegram_notification "🔄 Installing Cloudflare security bouncer..."
    
    if apt install -y crowdsec-cloudflare-worker-bouncer; then
        log "✅ Cloudflare bouncer installed"
        
        # Generate configuration
        if crowdsec-cloudflare-worker-bouncer -g "$CF_API_TOKEN" -o "$CLOUDFLARE_BOUNCER_CONFIG"; then
            # Update LAPI key in configuration
            sed -i "s|lapi_key:.*|lapi_key: $CROWDSEC_LAPI_KEY|" "$CLOUDFLARE_BOUNCER_CONFIG"
            
            systemctl start crowdsec-cloudflare-worker-bouncer
            systemctl enable crowdsec-cloudflare-worker-bouncer
            
            if systemctl is-active --quiet crowdsec-cloudflare-worker-bouncer; then
                send_telegram_notification "✅ Cloudflare bouncer installed and active"
                log "✅ Cloudflare bouncer configured and running"
            else
                log "⚠️ Cloudflare bouncer service issues"
            fi
        else
            log "❌ Failed to generate bouncer configuration"
            return 1
        fi
    else
        log "❌ Failed to install Cloudflare bouncer"
        return 1
    fi
}

main() {
    log "Starting Cloudflare bouncer setup..."
    generate_lapi_key
    install_cloudflare_bouncer
    log "✅ Cloudflare bouncer setup completed"
}

main "$@"
