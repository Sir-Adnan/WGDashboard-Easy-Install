#!/bin/bash

# =========================================================
#  WGDashboard Manager - Debug Edition (V6.0)
# =========================================================

# --- Colors ---
R='\033[0;31m'
G='\033[0;32m'
Y='\033[1;33m'
B='\033[0;34m'
P='\033[0;35m'
C='\033[0;36m'
W='\033[1;37m'
N='\033[0m'

# --- Configuration ---
INSTALL_DIR="/opt/wgdashboard"
BACKUP_SCRIPT_PATH="/usr/local/bin/wgd-backup.sh"

# --- UI Helper Functions ---

draw_box() {
    local title="$1"
    local text="$2"
    local color="$3"
    
    echo -e "${color}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    if [ -n "$title" ]; then
        printf "║ %-60s ║\n" "  $title"
        echo "╠══════════════════════════════════════════════════════════════╣"
    fi
    echo "$text" | while IFS= read -r line; do
        printf "║ %-60s ║\n" "  $line"
    done
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${N}"
}

header() {
    clear
    echo -e "${P}"
    echo "  _       __   ______     ____            __     "
    echo " | |     / /  / ____/    / __ \  ____    / /     "
    echo " | | /| / /  / / __     / / / / / __ \  / /      "
    echo " | |/ |/ /  / /_/ /    / /_/ / / /_/ / /_/       "
    echo " |__/|__/   \____/    /_____/  \____/ (_)        "
    echo -e "${N}"
    echo -e " ${C}:: Ultimate WireGuard Dashboard Manager ::${N}"
    echo ""
}

# --- Check Root ---
if [ "$EUID" -ne 0 ]; then
    echo -e "${R}❌ Error: Please run as root (sudo).${N}"
    exit 1
fi

# --- Modules ---

install_panel() {
    header
    draw_box "STEP 1: INSTALLATION" \
    "Installing Docker & WGDashboard.\nEnsure Ports: 10086 (TCP), 51820 (UDP)" "$B"

    echo -e " ${C}➜ Configuring System...${N}"
    if ! grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf; then
        echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    fi
    sysctl -w net.ipv4.ip_forward=1 > /dev/null 2>&1

    if ! command -v docker &> /dev/null; then
        echo -e " ${C}➜ Installing Docker...${N}"
        apt-get update -qq >/dev/null 2>&1
        apt-get install -y -qq ca-certificates curl gnupg lsb-release >/dev/null 2>&1
        mkdir -p /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
        apt-get update -qq >/dev/null 2>&1
        apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin >/dev/null 2>&1
    else
        echo -e " ${G}✔ Docker is ready.${N}"
    fi

    echo ""
    draw_box "CONFIGURATION" "Enter dashboard details." "$P"
    
    DETECTED_IP=$(curl -s https://api.ipify.org || echo "127.0.0.1")
    echo -ne " ${Y}➤${N} Public IP [Default: $DETECTED_IP]: "; read IP_IN
    PUBLIC_IP=${IP_IN:-$DETECTED_IP}
    
    echo -ne " ${Y}➤${N} Username [Default: admin]: "; read USER_IN
    WGD_USER=${USER_IN:-admin}
    
    while true; do
        echo -ne " ${Y}➤${N} Password: "; read -s WGD_PASS; echo ""
        if [ -n "$WGD_PASS" ]; then break; fi
        echo -e " ${R}⚠ Password is required!${N}"
    done
    
    echo -ne " ${Y}➤${N} Port [Default: 10086]: "; read PORT_IN
    WGD_PORT=${PORT_IN:-10086}
    
    echo -e "\n ${C}➜ Deploying...${N}"
    mkdir -p "$INSTALL_DIR"
    cd "$INSTALL_DIR"

    cat <<EOF > compose.yaml
services:
  wgdashboard:
    image: ghcr.io/wgdashboard/wgdashboard:latest
    container_name: wgdashboard
    restart: unless-stopped
    network_mode: host
    environment:
      - TZ=UTC
      - public_ip=${PUBLIC_IP}
      - username=${WGD_USER}
      - password=${WGD_PASS}
      - wgd_port=${WGD_PORT}
      - global_dns=1.1.1.1
      - wg_autostart=true
    volumes:
      - aconf:/etc/amnezia/amneziawg
      - conf:/etc/wireguard
      - data:/data
    cap_add:
      - NET_ADMIN
volumes:
  aconf:
  conf:
  data:
EOF

    docker compose up -d > /dev/null 2>&1
    
    if command -v ufw &> /dev/null && ufw status | grep -q "active"; then
        ufw allow $WGD_PORT/tcp >/dev/null
        ufw allow 51820/udp >/dev/null
    fi

    echo ""
    echo -e " ${G}✔ INSTALLATION SUCCESSFUL!${N}"
    echo -e "   URL: http://${PUBLIC_IP}:${WGD_PORT}"
    read -p "Press Enter to continue..."
}

setup_backup_bot() {
    header
    draw_box "TELEGRAM AUTO-BACKUP" "Setup automated backups to Telegram." "$B"

    if ! docker ps -a | grep -q wgdashboard; then
        echo -e " ${R}✖ Dashboard not found. Install it first.${N}"
        read -p "Press Enter..."
        return
    fi

    echo -e " ${C}➜ Installing dependencies...${N}"
    apt-get update -qq >/dev/null 2>&1
    apt-get install -y -qq zip curl cron >/dev/null 2>&1

    echo ""
    draw_box "CREDENTIALS" "Enter Bot Token & Chat ID.\nMake sure you have STARTED the bot in Telegram!" "$P"
    echo -ne " ${Y}➤${N} Bot Token: "; read TG_TOKEN
    echo -ne " ${Y}➤${N} Chat ID: "; read TG_CHATID

    if [[ -z "$TG_TOKEN" || -z "$TG_CHATID" ]]; then
        echo -e " ${R}✖ Error: Missing credentials.${N}"
        read -p "Press Enter..."
        return
    fi

    # --- NEW: Connection Verification ---
    echo ""
    echo -e " ${C}➜ Verifying credentials with Telegram API...${N}"
    
    # 1. Check Token
    BOT_INFO=$(curl -s "https://api.telegram.org/bot${TG_TOKEN}/getMe")
    if [[ "$BOT_INFO" != *"\"ok\":true"* ]]; then
        echo -e " ${R}✖ Error: Invalid Bot Token!${N}"
        echo -e "   Telegram Response: $BOT_INFO"
        read -p "Press Enter to try again..."
        return
    fi

    # 2. Check Chat ID (Send Text)
    echo -e " ${C}➜ Sending test message to verify Chat ID...${N}"
    MSG_TEST=$(curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" -d chat_id="${TG_CHATID}" -d text="🔌 Connection Successful! Server is ready to send backups.")
    
    if [[ "$MSG_TEST" != *"\"ok\":true"* ]]; then
        echo -e " ${R}✖ Error: Cannot send message to this Chat ID!${N}"
        echo -e " ${Y}⚠ Did you click /start in your bot?${N}"
        echo -e "   Telegram Response: $MSG_TEST"
        read -p "Press Enter to try again..."
        return
    fi
    
    echo -e " ${G}✔ Connection Verified!${N}"
    
    # --- Proceed to Setup ---

    echo ""
    draw_box "NAMING" "Unique name for this server (Allowed: A-Z, 0-9, . , -)" "$P"
    echo -ne " ${Y}➤${N} Backup Name [Default: WGD-Backup]: "; read PREFIX_IN
    
    BACKUP_PREFIX=${PREFIX_IN:-WGD-Backup}
    CLEAN_PREFIX=$(echo "$BACKUP_PREFIX" | tr -dc 'a-zA-Z0-9-._')

    # Create Script
    cat <<EOF > "$BACKUP_SCRIPT_PATH"
#!/bin/bash
# Config
TOKEN="${TG_TOKEN}"
CHAT_ID="${TG_CHATID}"
PREFIX="${CLEAN_PREFIX}"
EOF

    cat <<'EOF' >> "$BACKUP_SCRIPT_PATH"

# Dynamic Info
SERVER_IP=$(curl -s ifconfig.me || hostname -I | awk '{print $1}')
DATE=$(date +'%Y-%m-%d_%H-%M')
FILENAME="${PREFIX}_${DATE}"
BACKUP_DIR="/tmp/${FILENAME}"
ZIP_FILE="/tmp/${FILENAME}.zip"

# Create Temp Folder
mkdir -p "${BACKUP_DIR}"

# Copy Data
cp -r /var/lib/docker/volumes/wgdashboard_conf/_data "${BACKUP_DIR}/wireguard_config" 2>/dev/null
cp -r /var/lib/docker/volumes/wgdashboard_data/_data "${BACKUP_DIR}/dashboard_data" 2>/dev/null

# Zip
cd /tmp
zip -r "${ZIP_FILE}" "${FILENAME}" >/dev/null 2>&1

# Send to Telegram
CAPTION="📦 *Backup Notification*%0A🏷 Name: \`${PREFIX}\`%0A🖥 IP: \`${SERVER_IP}\`%0A📅 Date: $(date +'%Y-%m-%d %H:%M')"

# Send Document and Capture Response
RESPONSE=$(curl -s -F document=@"${ZIP_FILE}" "https://api.telegram.org/bot${TOKEN}/sendDocument?chat_id=${CHAT_ID}&caption=${CAPTION}&parse_mode=Markdown")

# Check if failed (for manual run debugging)
if [[ "$RESPONSE" != *"\"ok\":true"* ]]; then
    echo "❌ Telegram Upload Failed: $RESPONSE"
else
    echo "✅ Backup Uploaded Successfully"
fi

# Cleanup
rm -rf "${BACKUP_DIR}" "${ZIP_FILE}"
EOF

    chmod +x "$BACKUP_SCRIPT_PATH"
    echo -e " ${G}✔ Script generated at $BACKUP_SCRIPT_PATH${N}"

    echo ""
    draw_box "FREQUENCY" "Select backup interval." "$P"
    echo -e " ${C}1)${N} Every 30 Minutes"
    echo -e " ${C}2)${N} Every 6 Hours"
    echo -e " ${C}3)${N} Daily"
    echo ""
    echo -ne " ${Y}➤${N} Select [1-3]: "; read FREQ
    
    case $FREQ in
        1) CRON="*/30 * * * *" ;;
        2) CRON="0 */6 * * * *" ;;
        3) 
            echo -ne " ${Y}➤${N} Hour (0-23): "; read H
            CRON="0 ${H:-3} * * *" 
            ;;
        *) CRON="0 3 * * *" ;;
    esac

    (crontab -l 2>/dev/null | grep -v "$BACKUP_SCRIPT_PATH") | crontab -
    (crontab -l 2>/dev/null; echo "$CRON $BACKUP_SCRIPT_PATH") | crontab -
    
    echo ""
    echo -e " ${G}✔ Scheduled!${N}"
    echo -e " ${Y}➜ Sending file backup test...${N}"
    
    # Run test and show output
    bash "$BACKUP_SCRIPT_PATH"
    
    echo ""
    read -p "Press Enter to return..."
}

uninstall_all() {
    header
    draw_box "UNINSTALL" "Delete Dashboard & Bot?" "$R"
    echo -ne " ${Y}➤${N} Type 'yes' to confirm: "; read CONFIRM
    
    if [ "$CONFIRM" == "yes" ]; then
        if [ -d "$INSTALL_DIR" ]; then cd "$INSTALL_DIR"; docker compose down >/dev/null 2>&1; fi
        rm -rf "$INSTALL_DIR" "$BACKUP_SCRIPT_PATH"
        (crontab -l 2>/dev/null | grep -v "$BACKUP_SCRIPT_PATH") | crontab -
        echo -e " ${G}✔ Deleted.${N}"
    else
        echo -e " ${R}✖ Cancelled.${N}"
    fi
    read -p "Press Enter..."
}

view_logs() {
    header
    if [ -d "$INSTALL_DIR" ]; then
        cd "$INSTALL_DIR"
        echo -e "${C}--- Logs (Ctrl+C to exit) ---${N}"
        docker compose logs -f --tail=20
    else
        echo -e "${R}Not installed.${N}"
        read -p "Press Enter..."
    fi
}

update_panel() {
    if [ -d "$INSTALL_DIR" ]; then
        cd "$INSTALL_DIR"
        echo -e "${C}➜ Updating...${N}"
        docker compose pull
        docker compose up -d
        docker image prune -f >/dev/null 2>&1
        echo -e "${G}✔ Done.${N}"
    else
        echo -e "${R}Not installed.${N}"
    fi
    read -p "Press Enter..."
}

# --- Main Menu ---
while true; do
    header
    echo -e " ${G}1)${N} Install Dashboard"
    echo -e " ${G}2)${N} Update Dashboard"
    echo -e " ${G}3)${N} Setup Backup Bot ${Y}(New)${N}"
    echo -e " ${G}4)${N} View Logs"
    echo -e " ${R}0)${N} Uninstall"
    echo -e " ${R}9)${N} Exit"
    echo ""
    echo -ne " ${Y}➤${N} Option: "; read OPTION
    
    case $OPTION in
        1) install_panel ;;
        2) update_panel ;;
        3) setup_backup_bot ;;
        4) view_logs ;;
        0) uninstall_all ;;
        9) clear; exit 0 ;;
        *) echo -e " ${R}Invalid.${N}"; sleep 1 ;;
    esac
done
