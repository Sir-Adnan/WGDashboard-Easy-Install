#!/bin/bash

# =========================================================
#  WGDashboard Manager - V14 (UnknownZero UI Edition)
#  Author: UnknownZero
#  Features: Live Status Check, System Stats, Modern UI
# =========================================================

# --- Palette ---
RESET='\033[0m'
BOLD='\033[1m'

# Foreground
WHITE='\033[37m'
BLACK='\033[30m'
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
MAGENTA='\033[35m'
CYAN='\033[36m'
GRAY='\033[90m'

# Background
BG_RED='\033[41m'
BG_GREEN='\033[42m'
BG_BLUE='\033[44m'

# --- Configuration ---
INSTALL_DIR="/opt/wgdashboard"
BACKUP_SCRIPT_PATH="/usr/local/bin/wgd-backup.sh"
PROJECT_NAME="wgdashboard"
VERSION="14.0"
AUTHOR="UnknownZero"

# --- UI Functions ---

# Centered Text
center_text() {
    local text="$1"
    local width=70
    local padding=$(( (width - ${#text}) / 2 ))
    printf "%*s%s%*s\n" $padding "" "$text" $padding ""
}

# Drawing Lines
draw_line() {
    printf "${GRAY}──────────────────────────────────────────────────────────────────────${RESET}\n"
}

# Header with ASCII Art & Info
header() {
    clear
    echo -e "${MAGENTA}"
    cat << "EOF"
  _    _       _                              ______              
 | |  | |     | |                            |___  /              
 | |  | |_ __ | | ___ __   _____      ___ __    / / ___ _ __ ___  
 | |  | | '_ \| |/ / '_ \ / _ \ \ /\ / / '_ \  / / / _ \ '__/ _ \ 
 | |__| | | | |   <| | | | (_) \ V  V /| | | |/ /_|  __/ | | (_) |
  \____/|_| |_|_|\_\_| |_|\___/ \_/\_/ |_| |_/_____\___|_|  \___/ 
                                                                  
EOF
    echo -e "${RESET}"
    center_text "${BOLD}WGDashboard Manager - V${VERSION}${RESET}"
    center_text "Powered by ${CYAN}${AUTHOR}${RESET}"
    draw_line
    
    # System Stats
    SERVER_IP=$(curl -s --max-time 2 ifconfig.me || hostname -I | awk '{print $1}')
    UPTIME=$(uptime -p | sed 's/up //')
    RAM=$(free -h | awk '/Mem:/ {print $3 "/" $2}')
    
    echo -e " ${BOLD}SYSTEM INFO:${RESET}"
    echo -e " ${GRAY}├─ IP:${RESET} ${WHITE}$SERVER_IP${RESET}"
    echo -e " ${GRAY}├─ RAM:${RESET} ${WHITE}$RAM${RESET}"
    echo -e " ${GRAY}└─ Uptime:${RESET} ${WHITE}$UPTIME${RESET}"
    
    draw_line
    
    # Application Status Logic
    echo -e " ${BOLD}APPLICATION STATUS:${RESET}"
    if [ -d "$INSTALL_DIR" ]; then
        # Check Docker Status
        if docker compose -p "$PROJECT_NAME" ps | grep -q "Up"; then
            STATUS="${BG_GREEN}${BLACK} ONLINE ${RESET}"
        else
            STATUS="${BG_RED}${WHITE} OFFLINE ${RESET}"
        fi
        
        # Extract Port from compose.yaml
        PORT=$(grep "wgd_port=" "$INSTALL_DIR/compose.yaml" 2>/dev/null | cut -d'=' -f2)
        PORT=${PORT:-"Unknown"}
        
        # Extract Username
        USER=$(grep "username=" "$INSTALL_DIR/compose.yaml" 2>/dev/null | cut -d'=' -f2 | tr -d '"')
        USER=${USER:-"Unknown"}
        
        echo -e " ${GRAY}├─ Status:${RESET} $STATUS"
        echo -e " ${GRAY}├─ URL:${RESET}    http://${SERVER_IP}:${CYAN}${PORT}${RESET}"
        echo -e " ${GRAY}└─ User:${RESET}   ${YELLOW}${USER}${RESET}"
        
        # Backup Check
        if [ -f "$BACKUP_SCRIPT_PATH" ]; then
             echo -e " ${GRAY}└─ Backup:${RESET} ${GREEN}Active (Cron)${RESET}"
        else
             echo -e " ${GRAY}└─ Backup:${RESET} ${RED}Not Configured${RESET}"
        fi
    else
        echo -e " ${GRAY}└─ Status:${RESET} ${RED}NOT INSTALLED${RESET}"
    fi
    draw_line
    echo ""
}

# Message Box
msg_box() {
    local type="$1"
    local text="$2"
    case $type in
        "info")  echo -e " ${BLUE}ℹ${RESET}  $text" ;;
        "success") echo -e " ${GREEN}✔${RESET}  $text" ;;
        "warn")  echo -e " ${YELLOW}⚠${RESET}  $text" ;;
        "error") echo -e " ${RED}✖${RESET}  $text" ;;
        "input") echo -ne " ${MAGENTA}➤${RESET}  $text" ;;
    esac
}

# --- Check Root ---
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: Please run as root.${RESET}"
    exit 1
fi

# --- Modules ---

install_panel() {
    header
    msg_box "info" "Starting Installation Wizard..."
    echo ""
    
    msg_box "input" "Public IP [Default: Auto]: "; read IP_IN
    DETECTED_IP=$(curl -s --max-time 3 ifconfig.me || echo "127.0.0.1")
    PUBLIC_IP=${IP_IN:-$DETECTED_IP}
    
    msg_box "input" "Username [Default: admin]: "; read USER_IN
    WGD_USER=${USER_IN:-admin}
    
    while true; do
        msg_box "input" "Password: "; read -s WGD_PASS; echo ""
        if [ -n "$WGD_PASS" ]; then break; fi
        msg_box "error" "Password cannot be empty!"
    done
    
    msg_box "input" "Panel Port [Default: 10086]: "; read PORT_IN
    WGD_PORT=${PORT_IN:-10086}

    echo ""
    msg_box "info" "Configuring System & Docker..."
    
    # Sysctl
    if ! grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf; then echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf; fi
    sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1

    # Docker
    if ! docker compose version &>/dev/null; then
        msg_box "warn" "Docker not found. Installing..."
        apt-get update -qq >/dev/null 2>&1
        apt-get install -y -qq ca-certificates curl gnupg lsb-release >/dev/null 2>&1
        mkdir -p /etc/apt/keyrings
        curl -fsSL --max-time 10 https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list >/dev/null
        apt-get update -qq >/dev/null 2>&1
        apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin >/dev/null 2>&1
    fi

    msg_box "info" "Deploying Containers..."
    mkdir -p "$INSTALL_DIR"; cd "$INSTALL_DIR"

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
    docker compose -p "$PROJECT_NAME" up -d >/dev/null 2>&1
    
    # UFW
    if command -v ufw &>/dev/null && ufw status | grep -q "active"; then
        ufw allow $WGD_PORT/tcp >/dev/null; ufw allow 51820/udp >/dev/null
    fi

    echo ""
    msg_box "success" "Installation Complete!"
    read -p "Press Enter to return..."
}

setup_backup_bot() {
    header
    msg_box "info" "Telegram Auto-Backup Setup"
    echo ""
    
    # Check Deps
    if ! command -v zip &>/dev/null; then 
        msg_box "warn" "Installing dependencies..."
        apt-get update -qq >/dev/null; apt-get install -y -qq zip curl cron >/dev/null
    fi

    msg_box "input" "Bot Token: "; read TG_TOKEN
    msg_box "input" "Chat ID: "; read TG_CHATID
    
    if [[ -z "$TG_TOKEN" || -z "$TG_CHATID" ]]; then
        msg_box "error" "Missing credentials."
        read -p "Enter..."
        return
    fi

    msg_box "info" "Verifying Connection..."
    TEST=$(curl -s --max-time 10 -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" -d chat_id="${TG_CHATID}" -d text="🔌 Connection Verified by UnknownZero Script")
    
    if [[ "$TEST" != *"\"ok\":true"* ]]; then
        msg_box "error" "Connection Failed! Check Token/ID."
        read -p "Enter..."
        return
    fi
    msg_box "success" "Connected to Telegram!"

    echo ""
    msg_box "input" "Server Name [Default: WGD-Backup]: "; read PREFIX_IN
    BACKUP_PREFIX=${PREFIX_IN:-WGD-Backup}
    CLEAN_PREFIX=$(echo "$BACKUP_PREFIX" | tr -dc 'a-zA-Z0-9-._')

    # Generate Script
    rm -f "$BACKUP_SCRIPT_PATH"; touch "$BACKUP_SCRIPT_PATH"; chmod +x "$BACKUP_SCRIPT_PATH"
    
    echo "#!/bin/bash" > "$BACKUP_SCRIPT_PATH"
    echo "export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" >> "$BACKUP_SCRIPT_PATH"
    echo "TOKEN=\"$TG_TOKEN\"" >> "$BACKUP_SCRIPT_PATH"
    echo "CHAT_ID=\"$TG_CHATID\"" >> "$BACKUP_SCRIPT_PATH"
    echo "PREFIX=\"$CLEAN_PREFIX\"" >> "$BACKUP_SCRIPT_PATH"
    echo "PROJECT=\"$PROJECT_NAME\"" >> "$BACKUP_SCRIPT_PATH"
    
    cat <<'EOS' >> "$BACKUP_SCRIPT_PATH"
SERVER_IP=$(curl -s --max-time 5 ifconfig.me || hostname -I | awk '{print $1}')
DATE=$(date +'%Y-%m-%d_%H-%M')
FILENAME="${PREFIX}_${DATE}"
TEMP_DIR=$(mktemp -d)
BACKUP_DIR="${TEMP_DIR}/${FILENAME}"
ZIP_FILE="${TEMP_DIR}/${FILENAME}.zip"
mkdir -p "${BACKUP_DIR}"

VOL_CONF=$(docker volume inspect ${PROJECT}_conf --format '{{.Mountpoint}}' 2>/dev/null)
VOL_DATA=$(docker volume inspect ${PROJECT}_data --format '{{.Mountpoint}}' 2>/dev/null)
VOL_ACONF=$(docker volume inspect ${PROJECT}_aconf --format '{{.Mountpoint}}' 2>/dev/null)

if [ -z "$VOL_CONF" ]; then VOL_CONF=$(docker volume inspect wgdashboard_conf --format '{{.Mountpoint}}' 2>/dev/null); fi
if [ -z "$VOL_DATA" ]; then VOL_DATA=$(docker volume inspect wgdashboard_data --format '{{.Mountpoint}}' 2>/dev/null); fi
if [ -z "$VOL_ACONF" ]; then VOL_ACONF=$(docker volume inspect wgdashboard_aconf --format '{{.Mountpoint}}' 2>/dev/null); fi

if [ -n "$VOL_CONF" ] && [ -d "$VOL_CONF" ]; then cp -r "$VOL_CONF" "${BACKUP_DIR}/wireguard_conf"; fi
if [ -n "$VOL_DATA" ] && [ -d "$VOL_DATA" ]; then cp -r "$VOL_DATA" "${BACKUP_DIR}/dashboard_data"; fi
if [ -n "$VOL_ACONF" ] && [ -d "$VOL_ACONF" ]; then cp -r "$VOL_ACONF" "${BACKUP_DIR}/amnezia_conf"; fi

cd "${TEMP_DIR}"
zip -r "${ZIP_FILE}" "${FILENAME}" >/dev/null 2>&1

CAPTION="📦 *Backup Complete*%0A🏷 Name: ${PREFIX}%0A🖥 IP: ${SERVER_IP}%0A📅 Date: ${DATE}"
curl -s --max-time 45 -F chat_id="${CHAT_ID}" -F caption="${CAPTION}" -F document=@"${ZIP_FILE}" "https://api.telegram.org/bot${TOKEN}/sendDocument"
rm -rf "${TEMP_DIR}"
EOS
    
    echo ""
    msg_box "info" "Select Frequency:"
    echo -e "   ${CYAN}1)${RESET} 30 Minutes"
    echo -e "   ${CYAN}2)${RESET} 6 Hours"
    echo -e "   ${CYAN}3)${RESET} Daily"
    msg_box "input" "Option: "; read FREQ
    
    case $FREQ in
        1) CRON="*/30 * * * *" ;;
        2) CRON="0 */6 * * *" ;; 
        3) msg_box "input" "Hour (0-23): "; read H; CRON="0 ${H:-0} * * *" ;;
        *) CRON="0 3 * * *" ;;
    esac

    (crontab -l 2>/dev/null | grep -vF "$BACKUP_SCRIPT_PATH") | crontab -
    (crontab -l 2>/dev/null; echo "$CRON $BACKUP_SCRIPT_PATH") | crontab -
    
    msg_box "success" "Scheduled! Sending Test Backup..."
    bash "$BACKUP_SCRIPT_PATH"
    read -p "Press Enter..."
}

restore_backup() {
    header
    msg_box "warn" "Restore Wizard - Overwrites Data!"
    echo ""
    
    mapfile -t BACKUPS < <(ls /root/*.zip 2>/dev/null)
    if [ ${#BACKUPS[@]} -eq 0 ]; then
        msg_box "error" "No .zip files found in /root/"
        read -p "Enter..."
        return
    fi

    echo -e "${GRAY}Available Backups:${RESET}"
    i=1
    for f in "${BACKUPS[@]}"; do
        echo -e " ${CYAN}$i)${RESET} $(basename "$f")"
        ((i++))
    done
    echo ""
    
    msg_box "input" "Select File Number: "; read CHOICE
    if [[ ! "$CHOICE" =~ ^[0-9]+$ ]] || [ "$CHOICE" -lt 1 ] || [ "$CHOICE" -gt "${#BACKUPS[@]}" ]; then
        msg_box "error" "Invalid selection."
        read -p "Enter..."
        return
    fi
    
    FILE_FULL_PATH="${BACKUPS[$((CHOICE-1))]}"
    
    echo ""
    msg_box "input" "Type 'restore' to confirm: "; read CONFIRM
    if [ "$CONFIRM" == "restore" ]; then
        msg_box "info" "Restoring..."
        apt-get install -y -qq unzip >/dev/null
        
        # Stop
        if [ -d "$INSTALL_DIR" ]; then cd "$INSTALL_DIR"; docker compose -p "$PROJECT_NAME" down >/dev/null 2>&1; fi
        
        # Extract
        TEMP_RESTORE=$(mktemp -d)
        unzip -q "$FILE_FULL_PATH" -d "$TEMP_RESTORE"
        SOURCE_DIR=$(find "$TEMP_RESTORE" -type d -name "wireguard_conf" | xargs dirname | head -n 1)

        # Detect Volumes
        VOL_CONF=$(docker volume inspect ${PROJECT_NAME}_conf --format '{{.Mountpoint}}' 2>/dev/null)
        VOL_DATA=$(docker volume inspect ${PROJECT_NAME}_data --format '{{.Mountpoint}}' 2>/dev/null)
        VOL_ACONF=$(docker volume inspect ${PROJECT_NAME}_aconf --format '{{.Mountpoint}}' 2>/dev/null)
        
        # Fallback
        if [ -z "$VOL_CONF" ]; then VOL_CONF=$(docker volume inspect wgdashboard_conf --format '{{.Mountpoint}}' 2>/dev/null); fi
        if [ -z "$VOL_DATA" ]; then VOL_DATA=$(docker volume inspect wgdashboard_data --format '{{.Mountpoint}}' 2>/dev/null); fi
        if [ -z "$VOL_ACONF" ]; then VOL_ACONF=$(docker volume inspect wgdashboard_aconf --format '{{.Mountpoint}}' 2>/dev/null); fi

        # Copy
        if [ -n "$VOL_CONF" ] && [ -d "$SOURCE_DIR/wireguard_conf" ]; then rm -rf "$VOL_CONF"/*; cp -r "$SOURCE_DIR/wireguard_conf"/* "$VOL_CONF/"; fi
        if [ -n "$VOL_DATA" ] && [ -d "$SOURCE_DIR/dashboard_data" ]; then rm -rf "$VOL_DATA"/*; cp -r "$SOURCE_DIR/dashboard_data"/* "$VOL_DATA/"; fi
        if [ -n "$VOL_ACONF" ] && [ -d "$SOURCE_DIR/amnezia_conf" ]; then rm -rf "$VOL_ACONF"/*; cp -r "$SOURCE_DIR/amnezia_conf"/* "$VOL_ACONF/"; fi
        
        # Permissions & Start
        chmod -R 755 "$VOL_CONF" "$VOL_DATA" 2>/dev/null
        docker compose -p "$PROJECT_NAME" up -d >/dev/null 2>&1
        rm -rf "$TEMP_RESTORE"
        msg_box "success" "Restore Complete!"
    fi
    read -p "Enter..."
}

uninstall_all() {
    header
    msg_box "warn" "UNINSTALLATION - DANGER ZONE"
    msg_box "input" "Type 'yes' to delete Dashboard & Bot: "; read CONFIRM
    if [ "$CONFIRM" == "yes" ]; then
        if [ -d "$INSTALL_DIR" ]; then cd "$INSTALL_DIR"; docker compose -p "$PROJECT_NAME" down >/dev/null 2>&1; fi
        rm -rf "$INSTALL_DIR" "$BACKUP_SCRIPT_PATH"
        (crontab -l 2>/dev/null | grep -vF "$BACKUP_SCRIPT_PATH") | crontab -
        
        echo ""
        msg_box "input" "Type 'delete' to wipe all VPN DATA: "; read WIPE
        if [ "$WIPE" == "delete" ]; then
             docker volume rm ${PROJECT_NAME}_conf ${PROJECT_NAME}_data ${PROJECT_NAME}_aconf >/dev/null 2>&1
             docker volume rm wgdashboard_conf wgdashboard_data wgdashboard_aconf >/dev/null 2>&1
             msg_box "success" "Data Wiped."
        fi
        msg_box "success" "Uninstalled."
    fi
    read -p "Enter..."
}

remove_backup_only() {
    (crontab -l 2>/dev/null | grep -vF "$BACKUP_SCRIPT_PATH") | crontab -
    rm -f "$BACKUP_SCRIPT_PATH"
    msg_box "success" "Backup disabled."
    read -p "Enter..."
}

update_panel() {
    if [ -d "$INSTALL_DIR" ]; then 
        cd "$INSTALL_DIR"
        msg_box "info" "Updating..."
        docker compose -p "$PROJECT_NAME" pull
        docker compose -p "$PROJECT_NAME" up -d
        docker image prune -f >/dev/null 2>&1
        msg_box "success" "Updated."
    else
        msg_box "error" "Not installed."
    fi
    read -p "Enter..."
}

view_logs() {
    if [ -d "$INSTALL_DIR" ]; then cd "$INSTALL_DIR"; docker compose -p "$PROJECT_NAME" logs -f --tail=50; else msg_box "error" "Not installed."; read -p "Enter..."; fi
}

# --- Main Menu Loop ---
while true; do
    header
    echo -e " ${BOLD}MAIN MENU:${RESET}"
    echo -e " ${GREEN}1.${RESET} Install Dashboard      ${GRAY}(Setup VPN Panel)${RESET}"
    echo -e " ${GREEN}2.${RESET} Update Dashboard       ${GRAY}(Keep Data)${RESET}"
    echo -e " ${GREEN}3.${RESET} Setup Backup Bot       ${GRAY}(Auto Telegram)${RESET}"
    echo -e " ${GREEN}4.${RESET} Restore Backup         ${GRAY}(From .zip)${RESET}"
    echo -e " ${BLUE}5.${RESET} View Logs              ${GRAY}(Debugging)${RESET}"
    echo -e " ${RED}6.${RESET} Disable Backup Only    ${GRAY}(Stop Cron)${RESET}"
    echo -e " ${RED}0.${RESET} Uninstall Everything   ${GRAY}(Delete All)${RESET}"
    echo ""
    echo -e " ${GRAY}9. Exit${RESET}"
    echo ""
    msg_box "input" "Select Option: "; read OPTION
    
    case $OPTION in
        1) install_panel ;;
        2) update_panel ;;
        3) setup_backup_bot ;;
        4) restore_backup ;;
        5) view_logs ;;
        6) remove_backup_only ;;
        0) uninstall_all ;;
        9) clear; exit 0 ;;
        *) ;;
    esac
done
