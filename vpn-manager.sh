#!/bin/bash

# --- VPN Manager Menu (Core Logic) ---

# --- Colors and Logging ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
info() { echo -e "${BLUE}[MANAGER]${NC} $1"; }

# --- Configuration Loading ---
INSTALL_DIR="/usr/local/etc/vpn-manager"
CONFIG_FILE="${INSTALL_DIR}/config.conf"
XRAY_CONFIG_FILE="/usr/local/etc/xray/config.json"
source "${CONFIG_FILE}" # Load DOMAIN, MAIN_PROTOCOL, INSTALL_DATE

# --- Manager Functions (Simplified) ---

show_service_status() {
    info "--- Service Status ---"
    echo "SSH Status: $(systemctl is-active sshd)"
    echo "Dropbear Status: $(systemctl is-active dropbear)"
    echo "Xray Status: $(systemctl is-active xray)"
    # Add other service checks here (e.g., BadVPN, SlowDNS)
    echo "----------------------"
}

create_user_account() {
    info "--- Create New User ---"
    read -p "Enter new username (for SSH/Xray): " USERNAME
    read -s -p "Enter password: " PASSWORD
    echo 
    read -p "Enter expiry days (e.g., 7): " DAYS
    
    if id "$USERNAME" &>/dev/null; then
        warn "User $USERNAME already exists."
        return
    fi
    
    # 1. SSH Account Creation
    useradd -m -s /bin/false $USERNAME
    echo "$USERNAME:$PASSWORD" | chpasswd
    chage -E $(date -d "+$DAYS days" +%Y-%m-%d) $USERNAME
    
    # 2. Xray Client ID Generation and Injection (Requires 'jq')
    local XRAY_CLIENT_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')
    local CLIENT_TYPE="id" # Assume VLESS
    if [[ "$MAIN_PROTOCOL" == "trojan" ]]; then
        CLIENT_TYPE="password"
    fi
    
    # Inject client to Xray config using jq
    jq '.inbounds[0].settings.clients += [{ "'${CLIENT_TYPE}'": "'${XRAY_CLIENT_ID}'", "level": 0, "remark": "'${USERNAME}'" }]' ${XRAY_CONFIG_FILE} > ${XRAY_CONFIG_FILE}.tmp
    mv ${XRAY_CONFIG_FILE}.tmp ${XRAY_CONFIG_FILE}
    systemctl restart xray
    
    log "✅ User $USERNAME created successfully."
    display_user_info $USERNAME $XRAY_CLIENT_ID $PASSWORD
}

display_user_info() {
    local USERNAME="$1"
    local XRAY_CLIENT_ID="$2"
    local SSH_PASSWORD="$3"
    
    local EXPIRED_DATE=$(chage -l $USERNAME | grep "Account expires" | awk '{print $NF}')
    local SERVER_IP=$(curl -s https://ipinfo.io/ip)
    
    echo
    log "=============================================="
    log "  Premium Server SSH/Xray Account"
    log "=============================================="
    echo "Username: ${USERNAME}"
    echo "Password: ${SSH_PASSWORD}"
    echo "Expired: ${EXPIRED_DATE}"
    echo "=================Connection==================="
    echo "IP/Host: ${SERVER_IP}"
    echo "Domain SSH/TLS: ${DOMAIN}"
    echo "OpenSSH Port: 22"
    echo "SSH/Dropbear Port: 143, 109"
    echo "Xray Port: 443"
    echo "BadVPN UDPGW: 7300"
    echo "----------------------------------------------"
    echo "VLESS/Trojan Link (443):"
    
    local ENCODED_PATH="/ws-kpchannel" # Should be loaded from config
    local CLIENT_LINK
    
    # Simplified Link Generation
    if [[ "$MAIN_PROTOCOL" == "vless" ]]; then
        CLIENT_LINK="vless://${XRAY_CLIENT_ID}@${DOMAIN}:443?path=${ENCODED_PATH}&security=tls&alpn=h2%2Chttp%2F1.1&encryption=none&host=${DOMAIN}&type=ws&sni=${DOMAIN}#${USERNAME}-${MAIN_PROTOCOL^^}"
    else
         CLIENT_LINK="trojan://${XRAY_CLIENT_ID}@${DOMAIN}:443?path=${ENCODED_PATH}&security=tls&alpn=h2%2Chttp%2F1.1&host=${DOMAIN}&type=ws&sni=${DOMAIN}#${USERNAME}-${MAIN_PROTOCOL^^}"
    fi
    
    echo -e "${BLUE}${CLIENT_LINK}${NC}"
    echo "----------------------------------------------"
}

# --- Main Menu ---
management_menu() {
    while true; do
        clear
        log "=== KP CHANNEL VPN MANAGER ==="
        show_service_status
        echo "1. Create New User"
        echo "2. Extend User Expiry Date"
        echo "3. Delete User"
        echo "4. Show All Active Users"
        echo "5. Server Status & Links"
        echo "0. Exit"
        echo "--------------------------------"
        
        read -p "Enter choice (0-5): " choice
        
        case $choice in
            1) create_user_account ;;
            2) warn "Feature not implemented yet.";;
            3) warn "Feature not implemented yet.";;
            4) warn "Feature not implemented yet.";;
            5) display_user_info "Admin" "N/A" "N/A" ;; # Just displays server info
            0) log "Exiting Manager. Goodbye!"; break ;;
            *) warn "Invalid choice. Please try again." ;;
        esac
        
        read -n 1 -s -r -p "Press any key to continue to Menu..."
    done
}


if [[ "$#" -eq 1 && "$1" == "menu" ]]; then
    management_menu
else
    # Only the installer should call the main install function
    error "This script should be called via the 'vpn' alias after installation."
fi
