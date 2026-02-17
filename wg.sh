#!/bin/bash

# =========================================================
#  WGDashboard Manager - V11 (Production Ready)
#  Changes: Fixed Cron PATH, Deep Uninstall Option,
#           Project Name Locking, Robust Error Handling.
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
PROJECT_NAME="wgdashboard"

# --- UI Helper Functions ---
draw_box() {
    local title="$1"; local text="$2"; local color="$3"
    echo -e "${color}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    if [ -n "$title" ]; then printf "║ %-60s ║\n" "  $title"; echo "╠══════════════════════════════════════════════════════════════╣"; fi
    echo "$text" | while IFS= read -r line; do printf "║ %-60s ║\n" "  $line"; done
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

if [ "$EUID" -ne 0 ]; then echo -e "${R}❌ Error: Run as root.${N}"; exit 1; fi

# --- Modules ---

install_panel() {
    header
    draw_box "INSTALLATION" "Installing Docker & Dashboard.\nPorts: 10086 (TCP), 51820 (UDP)" "$B"
    
    echo -e " ${C}➜ Configuring System...${N}"
    if ! grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf; then echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf; fi
    sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1

    # Check for Docker Compose Plugin
    if ! docker compose version &>/dev/null; then
        echo -e " ${C}➜ Installing Docker & Compose Plugin...${N}"
        apt-get update -qq >/dev/null 2>&1
        apt-get install -y -qq ca-certificates curl gnupg lsb-release >/dev/null 2>&1
        mkdir -p /etc/apt/keyrings
        curl -fsSL --max-time 10 https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list >/dev/null
        apt-get update -qq >/dev/null 2>&1
        apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin >/dev/null 2>&1
    fi

    echo ""
    draw_box "CONFIG" "Dashboard Details" "$P"
    
    DETECTED_IP=$(curl -s --max-time 5 https://api.ipify.org || echo "127.0.0.1")
    
    echo -ne " ${Y}➤${N} Public IP [Default: $DETECTED_IP]: "; read IP_IN; PUBLIC_IP=${IP_IN:-$DETECTED_IP}
    echo -ne " ${Y}➤${N} Username [Default: admin]: "; read USER_IN; WGD_USER=${USER_IN:-admin}
    while true; do echo -ne " ${Y}➤${N} Password: "; read -s WGD_PASS; echo ""; if [ -n "$WGD_PASS" ]; then break; fi; done
    echo -ne " ${Y}➤${N} Port [Default: 10086]: "; read PORT_IN; WGD_PORT=${PORT_IN:-10086}

    echo -e "\n ${C}➜ Deploying...${N}"
    mkdir -p "$INSTALL_DIR"; cd "$INSTALL_DIR"

    # YAML generation with quoted variables
    cat <<EOF > compose.yaml
services:
  wgdashboard:
    image: ghcr.io/wgdashboard/wgdashboard:latest
    container_name: wgdashboard
    restart: unless-stopped
    network_mode: host
    environment:
      - TZ=UTC
      - public_ip="${PUBLIC_IP}"
      - username="${WGD_USER}"
      - password="${WGD_PASS}"
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
    # Using -p to enforce project name for reliable volume names
    docker compose -p "$PROJECT_NAME" up -d >/dev/null 2>&1
    
    if command -v ufw &>/dev/null && ufw status | grep -q "active"; then ufw allow $WGD_PORT/tcp >/dev/null; ufw allow 51820/udp >/dev/null; fi
    echo -e " ${G}✔ Installed: http://${PUBLIC_IP}:${WGD_PORT}${N}"; read -p "Press Enter..."
}

setup_backup_bot() {
    header
    draw_box "AUTO-BACKUP V11" "Backs up CONFIG + DATA + DB + AMNEZIA." "$B"
    apt-get update -qq >/dev/null 2>&1; apt-get install -y -qq zip curl cron >/dev/null 2>&1

    echo ""; draw_box "CREDENTIALS" "Enter Bot Token & Chat ID." "$P"
    echo -ne " ${Y}➤${N} Bot Token: "; read TG_TOKEN
    echo -ne " ${Y}➤${N} Chat ID: "; read TG_CHATID
    if [[ -z "$TG_TOKEN" || -z "$TG_CHATID" ]]; then echo -e " ${R}✖ Missing inputs.${N}"; read -p "Enter..."; return; fi

    echo -e " ${C}➜ Verifying...${N}"
    TEST=$(curl -s --max-time 10 -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" -d chat_id="${TG_CHATID}" -d text="🔌 Connection Verified!")
    if [[ "$TEST" != *"\"ok\":true"* ]]; then echo -e " ${R}✖ Connection Failed!${N}"; read -p "Enter..."; return; fi
    echo -e " ${G}✔ Connection Successful!${N}"

    echo ""; draw_box "NAMING" "Server Name (e.g. UAE-Server)" "$P"
    echo -ne " ${Y}➤${N} Name [Default: WGD-Backup]: "; read PREFIX_IN
    BACKUP_PREFIX=${PREFIX_IN:-WGD-Backup}
    CLEAN_PREFIX=$(echo "$BACKUP_PREFIX" | tr -dc 'a-zA-Z0-9-._')

    # --- GENERATING BACKUP SCRIPT ---
    echo -e " ${C}➜ Generating Script...${N}"
    
    rm -f "$BACKUP_SCRIPT_PATH"
    touch "$BACKUP_SCRIPT_PATH"
    chmod +x "$BACKUP_SCRIPT_PATH"

    # Part 1: Header & Variables
    echo "#!/bin/bash" > "$BACKUP_SCRIPT_PATH"
    # Important: Set PATH for Cron execution to find 'docker' command
    echo "export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" >> "$BACKUP_SCRIPT_PATH"
    echo "TOKEN=\"$TG_TOKEN\"" >> "$BACKUP_SCRIPT_PATH"
    echo "CHAT_ID=\"$TG_CHATID\"" >> "$BACKUP_SCRIPT_PATH"
    echo "PREFIX=\"$CLEAN_PREFIX\"" >> "$BACKUP_SCRIPT_PATH"
    echo "PROJECT=\"$PROJECT_NAME\"" >> "$BACKUP_SCRIPT_PATH"
    
    # Part 2: Logic
    cat <<'EOS' >> "$BACKUP_SCRIPT_PATH"

# Dynamic Variables
SERVER_IP=$(curl -s --max-time 5 ifconfig.me || hostname -I | awk '{print $1}')
DATE=$(date +'%Y-%m-%d_%H-%M')
FILENAME="${PREFIX}_${DATE}"

TEMP_DIR=$(mktemp -d)
BACKUP_DIR="${TEMP_DIR}/${FILENAME}"
ZIP_FILE="${TEMP_DIR}/${FILENAME}.zip"

mkdir -p "${BACKUP_DIR}"

# --- DYNAMIC VOLUME PATH DETECTION ---
# Inspecting volumes based on project name prefix

VOL_CONF=$(docker volume inspect ${PROJECT}_conf --format '{{.Mountpoint}}' 2>/dev/null)
VOL_DATA=$(docker volume inspect ${PROJECT}_data --format '{{.Mountpoint}}' 2>/dev/null)
VOL_ACONF=$(docker volume inspect ${PROJECT}_aconf --format '{{.Mountpoint}}' 2>/dev/null)

# Fallback for default names if project name lookup fails
if [ -z "$VOL_CONF" ]; then VOL_CONF=$(docker volume inspect wgdashboard_conf --format '{{.Mountpoint}}' 2>/dev/null); fi
if [ -z "$VOL_DATA" ]; then VOL_DATA=$(docker volume inspect wgdashboard_data --format '{{.Mountpoint}}' 2>/dev/null); fi
if [ -z "$VOL_ACONF" ]; then VOL_ACONF=$(docker volume inspect wgdashboard_aconf --format '{{.Mountpoint}}' 2>/dev/null); fi

# Copy Volumes
if [ -n "$VOL_CONF" ] && [ -d "$VOL_CONF" ]; then cp -r "$VOL_CONF" "${BACKUP_DIR}/wireguard_conf"; fi
if [ -n "$VOL_DATA" ] && [ -d "$VOL_DATA" ]; then cp -r "$VOL_DATA" "${BACKUP_DIR}/dashboard_data"; fi
if [ -n "$VOL_ACONF" ] && [ -d "$VOL_ACONF" ]; then cp -r "$VOL_ACONF" "${BACKUP_DIR}/amnezia_conf"; fi

# Zip
cd "${TEMP_DIR}"
zip -r "${ZIP_FILE}" "${FILENAME}" >/dev/null 2>&1

# Send to Telegram
CAPTION="📦 *Backup Complete*%0A🏷 Name: ${PREFIX}%0A🖥 IP: ${SERVER_IP}%0A📅 Date: ${DATE}"

curl -s --max-time 45 \
  -F chat_id="${CHAT_ID}" \
  -F caption="${CAPTION}" \
  -F document=@"${ZIP_FILE}" \
  "https://api.telegram.org/bot${TOKEN}/sendDocument"

# Cleanup
rm -rf "${TEMP_DIR}"
EOS

    echo -e " ${G}✔ Script generated at $BACKUP_SCRIPT_PATH${N}"

    echo ""; draw_box "FREQUENCY" "Select Interval" "$P"
    echo -e " ${C}1)${N} 30 Mins  ${C}2)${N} 6 Hours  ${C}3)${N} Daily"
    echo -ne " ${Y}➤${N} Option: "; read FREQ
    case $FREQ in
        1) CRON="*/30 * * * *" ;;
        2) CRON="0 */6 * * *" ;; 
        3) echo -ne " ${Y}➤${N} Hour (0-23): "; read H; CRON="0 ${H:-0} * * *" ;;
        *) CRON="0 3 * * *" ;;
    esac

    (crontab -l 2>/dev/null | grep -vF "$BACKUP_SCRIPT_PATH") | crontab -
    (crontab -l 2>/dev/null; echo "$CRON $BACKUP_SCRIPT_PATH") | crontab -
    
    echo -e " ${G}✔ Scheduled! Sending test...${N}"
    bash "$BACKUP_SCRIPT_PATH"
    echo -e " ${G}✔ Test executed.${N}"; read -p "Press Enter..."
}

remove_backup_only() {
    header
    draw_box "REMOVE BACKUP" "Stops auto-backup. Dashboard remains active." "$R"
    echo -ne " ${Y}➤${N} Confirm 'yes': "; read CONFIRM
    if [ "$CONFIRM" == "yes" ]; then
        (crontab -l 2>/dev/null | grep -vF "$BACKUP_SCRIPT_PATH") | crontab -
        rm -f "$BACKUP_SCRIPT_PATH"
        echo -e " ${G}✔ Backup system removed successfully.${N}"
    else
        echo -e " ${Y}⚠ Cancelled.${N}"
    fi
    read -p "Press Enter..."
}

uninstall_all() {
    header
    draw_box "UNINSTALL" "This will delete the Dashboard & Bot." "$R"
    echo -ne " ${Y}➤${N} Type 'yes' to confirm: "; read CONFIRM
    if [ "$CONFIRM" == "yes" ]; then
        # Stop containers
        if [ -d "$INSTALL_DIR" ]; then 
            cd "$INSTALL_DIR"
            docker compose -p "$PROJECT_NAME" down >/dev/null 2>&1
        fi
        
        # Remove Files
        rm -rf "$INSTALL_DIR" "$BACKUP_SCRIPT_PATH"
        (crontab -l 2>/dev/null | grep -vF "$BACKUP_SCRIPT_PATH") | crontab -
        
        # Ask for Data wipe
        echo ""
        echo -e " ${R}⚠ Do you want to delete ALL VPN data & users? (Docker Volumes)${N}"
        echo -ne " ${Y}➤${N} Type 'delete' to wipe data (or Enter to keep): "; read WIPE
        
        if [ "$WIPE" == "delete" ]; then
            docker volume rm ${PROJECT_NAME}_conf ${PROJECT_NAME}_data ${PROJECT_NAME}_aconf >/dev/null 2>&1
            # Fallback for default names
            docker volume rm wgdashboard_conf wgdashboard_data wgdashboard_aconf >/dev/null 2>&1
            echo -e " ${G}✔ All data wiped.${N}"
        else
            echo -e " ${C}ℹ Data preserved in Docker volumes.${N}"
        fi
        
        echo -e " ${G}✔ Uninstallation complete.${N}"
    fi
    read -p "Press Enter..."
}

view_logs() {
    header
    if [ -d "$INSTALL_DIR" ]; then cd "$INSTALL_DIR"; echo -e "${C}Logs (Ctrl+C exit)${N}"; docker compose -p "$PROJECT_NAME" logs -f --tail=20
    else echo -e "${R}Not installed.${N}"; read -p "Enter..."; fi
}

update_panel() {
    if [ -d "$INSTALL_DIR" ]; then 
        cd "$INSTALL_DIR"
        docker compose -p "$PROJECT_NAME" pull
        docker compose -p "$PROJECT_NAME" up -d
        docker image prune -f >/dev/null 2>&1
        echo -e "${G}✔ Updated.${N}"
    else 
        echo -e "${R}Not installed.${N}"
    fi
    read -p "Enter..."
}

while true; do
    header
    echo -e " ${G}1)${N} Install Panel"
    echo -e " ${G}2)${N} Update Panel"
    echo -e " ${G}3)${N} Setup Backup Bot ${Y}(V11)${N}"
    echo -e " ${R}4)${N} Remove Backup Only"
    echo -e " ${B}5)${N} View Logs"
    echo -e " ${R}0)${N} Uninstall All"
    echo -e " ${R}9)${N} Exit"
    echo ""; echo -ne " ${Y}➤${N} Option: "; read OPTION
    case $OPTION in
        1) install_panel ;;
        2) update_panel ;;
        3) setup_backup_bot ;;
        4) remove_backup_only ;;
        5) view_logs ;;
        0) uninstall_all ;;
        9) clear; exit 0 ;;
        *) ;;
    esac
done
