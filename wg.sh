#!/bin/bash

# =========================================================
#  WGDashboard Manager - Ultimate UI Edition (V3.0)
# =========================================================

# --- Colors & Styles ---
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

# --- UI Functions ---

# Draw a Box around text
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
    
    # Split text by newline and print each line
    echo "$text" | while IFS= read -r line; do
        printf "║ %-60s ║\n" "  $line"
    done
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${N}"
}

# Progress Bar Animation
progress_bar() {
    local duration=${1}
    local block="█"
    local empty="░"
    local width=40
    
    for ((i=0; i<=100; i+=5)); do
        local filled=$((i * width / 100))
        local unfilled=$((width - filled))
        
        # Create bar string
        local bar=$(printf "%0.s$block" $(seq 1 $filled))
        local space=$(printf "%0.s$empty" $(seq 1 $unfilled))
        
        printf "\r ${C}[${bar}${space}]${N} ${G}%3d%%${N}" "$i"
        sleep $(echo "$duration / 20" | bc -l 2>/dev/null || echo "0.1")
    done
    echo ""
}

# Header
header() {
    clear
    echo -e "${C}"
    echo "  _       __   ______     ____            __     "
    echo " | |     / /  / ____/    / __ \  ____    / /     "
    echo " | | /| / /  / / __     / / / / / __ \  / /      "
    echo " | |/ |/ /  / /_/ /    / /_/ / / /_/ / /_/       "
    echo " |__/|__/   \____/    /_____/  \____/ (_)        "
    echo -e "${N}"
    echo -e " ${P}:: Ultimate WireGuard Dashboard Manager ::${N}"
    echo ""
}

# Input Helper
get_input() {
    local prompt="$1"
    local default="$2"
    if [ -n "$default" ]; then
        echo -ne " ${Y}➤${N} $prompt ${C}[Default: $default]${N}: "
    else
        echo -ne " ${Y}➤${N} $prompt: "
    fi
}

# --- System Check ---
if [ "$EUID" -ne 0 ]; then
    draw_box "ERROR" "Please run this script as root (sudo)." "$R"
    exit 1
fi

# --- Modules ---

install_panel() {
    header
    draw_box "STEP 1: INSTALLATION" \
    "We are about to install Docker and WGDashboard.\nThis will set up the web panel and WireGuard VPN.\n\nRequired: Port 10086 (TCP) and 51820 (UDP)." \
    "$B"

    # 1. Sysctl
    echo -e " ${C}➜ Configuring System Kernel...${N}"
    if ! grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf; then
        echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    fi
    sysctl -w net.ipv4.ip_forward=1 > /dev/null 2>&1

    # 2. Docker
    if ! command -v docker &> /dev/null; then
        echo -e " ${C}➜ Docker not found. Installing...${N}"
        apt-get update -qq >/dev/null 2>&1
        apt-get install -y -qq ca-certificates curl gnupg lsb-release >/dev/null 2>&1
        mkdir -p /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
        apt-get update -qq >/dev/null 2>&1
        apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin >/dev/null 2>&1
        progress_bar 2
    else
        echo -e " ${G}✔ Docker is already installed.${N}"
    fi

    # 3. Inputs
    echo ""
    draw_box "CONFIGURATION" "Enter the details for your dashboard." "$P"
    
    DETECTED_IP=$(curl -s https://api.ipify.org || echo "127.0.0.1")
    get_input "Public IP" "$DETECTED_IP"; read IP_IN; PUBLIC_IP=${IP_IN:-$DETECTED_IP}
    
    get_input "Dashboard Username" "admin"; read USER_IN; WGD_USER=${USER_IN:-admin}
    
    while true; do
        get_input "Dashboard Password" ""; read -s WGD_PASS; echo ""
        if [ -n "$WGD_PASS" ]; then break; fi
        echo -e " ${R}⚠ Password cannot be empty!${N}"
    done
    
    get_input "Dashboard Port" "10086"; read PORT_IN; WGD_PORT=${PORT_IN:-10086}
    get_input "WireGuard UDP Port" "51820"; read WG_IN; WG_PORT=${WG_IN:-51820}

    # 4. Deploy
    echo ""
    echo -e " ${C}➜ Deploying Container...${N}"
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
    progress_bar 3

    # 5. Firewall
    if command -v ufw &> /dev/null && ufw status | grep -q "active"; then
        ufw allow $WGD_PORT/tcp >/dev/null
        ufw allow $WG_PORT/udp >/dev/null
        echo -e " ${G}✔ Firewall ports opened.${N}"
    fi

    echo ""
    draw_box "INSTALLATION COMPLETE" \
    "URL: http://${PUBLIC_IP}:${WGD_PORT}\nUsername: ${WGD_USER}\nPassword: (Hidden)" \
    "$G"
    
    read -p "Press Enter to return to menu..."
}

setup_backup_bot() {
    header
    draw_box "AUTO-BACKUP SETUP" \
    "This tool creates a Telegram Bot service that automatically\nzips your WireGuard configs and sends them to your chat.\n\nYou need a Bot Token from @BotFather and your Chat ID." \
    "$B"

    # Check Prereq
    if ! docker ps -a | grep -q wgdashboard; then
        echo -e " ${R}✖ WGDashboard container not found. Install it first.${N}"
        read -p "Press Enter..."
        return
    fi

    echo -e " ${C}➜ Installing dependencies (zip, curl, cron)...${N}"
    apt-get update -qq >/dev/null 2>&1
    apt-get install -y -qq zip curl cron >/dev/null 2>&1
    progress_bar 1

    echo ""
    draw_box "BOT CREDENTIALS" "Enter your Telegram Bot details below." "$P"
    
    get_input "Bot Token" ""; read TG_TOKEN
    get_input "Chat ID" ""; read TG_CHATID

    if [[ -z "$TG_TOKEN" || -z "$TG_CHATID" ]]; then
        echo -e " ${R}✖ Error: Token and Chat ID are required.${N}"
        read -p "Press Enter..."
        return
    fi

    echo ""
    draw_box "CUSTOMIZATION" \
    "Choose a name for your backup file.\nExample: 'Server-Germany' or 'VPN-Client-1'.\nAllowed: Letters, Numbers, Dots(.), Dashes(-)." \
    "$P"
    
    get_input "Backup Filename Prefix" "WGD-Backup"; read PREFIX_IN
    
    # SANITIZATION FIX: Allow dots, alphanumeric, dashes, underscores
    BACKUP_PREFIX=${PREFIX_IN:-WGD-Backup}
    CLEAN_PREFIX=$(echo "$BACKUP_PREFIX" | tr -dc 'a-zA-Z0-9-._')
    
    if [ -z "$CLEAN_PREFIX" ]; then CLEAN_PREFIX="WGD-Backup"; fi

    # Create the script
    # FIX: We inject variables directly using quotes to prevent "command not found" errors
    cat <<EOF > "$BACKUP_SCRIPT_PATH"
#!/bin/bash

# Configuration
TOKEN="${TG_TOKEN}"
CHAT_ID="${TG_CHATID}"
PREFIX="${CLEAN_PREFIX}"

# Dynamic Variables
SERVER_IP=\$(curl -s ifconfig.me || hostname -I | awk '{print \$1}')
DATE=\$(date +'%Y-%m-%d_%H-%M')
FILENAME="\${PREFIX}_\${DATE}"
BACKUP_DIR="/tmp/\${FILENAME}"
ZIP_FILE="/tmp/\${FILENAME}.zip"

# Create Temp Directory
mkdir -p "\${BACKUP_DIR}"

# Copy Data (Suppress errors if volumes are empty)
cp -r /var/lib/docker/volumes/wgdashboard_conf/_data "\${BACKUP_DIR}/wireguard_config" 2>/dev/null
cp -r /var/lib/docker/volumes/wgdashboard_data/_data "\${BACKUP_DIR}/dashboard_data" 2>/dev/null

# Zip It
cd /tmp
zip -r "\${ZIP_FILE}" "\${FILENAME}" >/dev/null 2>&1

# Send to Telegram
CAPTION="📦 *Backup Notification*%0A🏷 Name: \`\${PREFIX}\`%0A🖥 IP: \`\${SERVER_IP}\`%0A📅 Date: \$(date +'%Y-%m-%d %H:%M')"

curl -s -F document=@"\${ZIP_FILE}" "https://api.telegram.org/bot\${TOKEN}/sendDocument?chat_id=\${CHAT_ID}&caption=\${CAPTION}&parse_mode=Markdown" >/dev/null

# Cleanup
rm -rf "\${BACKUP_DIR}" "\${ZIP_FILE}"
EOF

    chmod +x "$BACKUP_SCRIPT_PATH"
    echo -e " ${G}✔ Backup script created at $BACKUP_SCRIPT_PATH${N}"

    echo ""
    draw_box "SCHEDULING" "How often should the backup run?" "$P"
    echo -e " ${C}1)${N} Every 30 Minutes"
    echo -e " ${C}2)${N} Every 6 Hours"
    echo -e " ${C}3)${N} Daily (Select Hour)"
    echo ""
    get_input "Select Option" "3"; read FREQ
    
    CRON_CMD=""
    case $FREQ in
        1) CRON_CMD="*/30 * * * *" ;;
        2) CRON_CMD="0 */6 * * * *" ;;
        3) 
            get_input "Enter Hour (0-23)" "3"; read H
            H=${H:-3}
            CRON_CMD="0 $H * * *" 
            ;;
        *) CRON_CMD="0 3 * * *" ;;
    esac

    # Remove old jobs and add new one
    (crontab -l 2>/dev/null | grep -v "$BACKUP_SCRIPT_PATH") | crontab -
    (crontab -l 2>/dev/null; echo "$CRON_CMD $BACKUP_SCRIPT_PATH") | crontab -
    
    echo ""
    echo -e " ${G}✔ Cronjob scheduled successfully!${N}"
    echo -e " ${C}➜ Sending a test backup now...${N}"
    
    # Execute immediately to test
    bash "$BACKUP_SCRIPT_PATH"
    
    echo -e " ${G}✔ Test backup sent. Check your Telegram!${N}"
    read -p "Press Enter to return..."
}

uninstall_all() {
    header
    draw_box "UNINSTALL" "This will DELETE the Dashboard, Users, and Backup Bot.\nProceed with caution!" "$R"
    
    get_input "Type 'yes' to confirm" ""; read CONFIRM
    if [ "$CONFIRM" == "yes" ]; then
        echo -e " ${C}➜ Stopping services...${N}"
        if [ -d "$INSTALL_DIR" ]; then cd "$INSTALL_DIR"; docker compose down >/dev/null 2>&1; fi
        
        echo -e " ${C}➜ Removing files...${N}"
        rm -rf "$INSTALL_DIR" "$BACKUP_SCRIPT_PATH"
        
        echo -e " ${C}➜ Removing scheduled tasks...${N}"
        (crontab -l 2>/dev/null | grep -v "$BACKUP_SCRIPT_PATH") | crontab -
        
        echo -e " ${G}✔ Uninstallation complete.${N}"
    else
        echo -e " ${Y}⚠ Cancelled.${N}"
    fi
    read -p "Press Enter..."
}

view_logs() {
    header
    draw_box "LIVE LOGS" "Press Ctrl+C to exit log view." "$B"
    if [ -d "$INSTALL_DIR" ]; then
        cd "$INSTALL_DIR"
        docker compose logs -f --tail=20
    else
        echo -e " ${R}✖ Not installed.${N}"
        read -p "Press Enter..."
    fi
}

update_panel() {
    header
    draw_box "UPDATE" "Pulling latest docker images..." "$B"
    if [ -d "$INSTALL_DIR" ]; then
        cd "$INSTALL_DIR"
        docker compose pull
        docker compose up -d
        docker image prune -f >/dev/null 2>&1
        echo -e " ${G}✔ Update Complete.${N}"
    else
        echo -e " ${R}✖ Not installed.${N}"
    fi
    read -p "Press Enter..."
}

# --- Main Loop ---
while true; do
    header
    
    # Menu Options
    echo -e " ${C}1)${N} Install Dashboard  ${W}➜${N} Setup VPN Panel"
    echo -e " ${C}2)${N} Update Dashboard   ${W}➜${N} Get latest version"
    echo -e " ${C}3)${N} Setup Backup Bot   ${W}➜${N} Telegram Auto-Backup"
    echo -e " ${C}4)${N} View Logs          ${W}➜${N} Debugging"
    echo -e " ${C}0)${N} Uninstall          ${W}➜${N} Delete everything"
    echo -e " ${R}9) Exit${N}"
    echo ""
    
    get_input "Select Option"; read OPTION
    
    case $OPTION in
        1) install_panel ;;
        2) update_panel ;;
        3) setup_backup_bot ;;
        4) view_logs ;;
        0) uninstall_all ;;
        9) clear; exit 0 ;;
        *) echo -e " ${R}Invalid option.${N}"; sleep 1 ;;
    esac
done
