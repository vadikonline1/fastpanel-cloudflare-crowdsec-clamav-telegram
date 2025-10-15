#!/bin/bash
set -e

# Load environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/hosting_env.env"
source "${SCRIPT_DIR}/telegram_notify.sh"

log() {
    echo -e "🔹 $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

create_directories() {
    log "Creating directory structure..."
    
    local dirs=(
        "$BOUNCER_DIR"
        "$LOG_DIR"
        "$CROWDSEC_DIR/bouncers"
        "$CROWDSEC_DIR/plugins"
        "$CLAMAV_QUARANTINE_DIR"
    )
    
    for dir in "${dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            mkdir -p "$dir"
            chmod 750 "$dir"
            log "✅ Created: $dir"
        else
            log "✅ Exists: $dir"
        fi
    done
    
    # Set ownership for quarantine directory
    chown clamav:clamav "$CLAMAV_QUARANTINE_DIR" 2>/dev/null || true
}

main() {
    log "Setting up directory structure..."
    create_directories
    log "✅ Directory setup completed"
}

main "$@"
