#!/bin/bash

# =========================================================
#  WGDashboard Manager - V19 (Standard Stable UI)
#  Author: UnknownZero
#  Fixes: Removed raw ANSI codes, used tput for compatibility
# =========================================================

# --- Safe Color Management ---
# We use tput which adapts to the terminal. 
# If terminal doesn't support color, it returns empty strings (safe).
if command -v tput >/dev/null 2>&1; then
    RED=$(tput setaf 1)
    GREEN=$(tput setaf 2)
    YELLOW=$(tput setaf 3)
    BLUE=$(tput setaf 4)
    CYAN=$(tput setaf 6)
    BOLD=$(tput bold)
    RESET=$(tput sgr0)
else
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    CYAN=""
    BOLD=""
    RESET=""
fi

# --- Configuration ---
INSTALL_DIR="/opt/wgdashboard"
BACKUP_SCRIPT_PATH="/usr/local/bin/wgd-backup.sh"
PROJECT_NAME="wgdashboard"
VERSION="19.0"

# --- Functions ---

get_public_ip() {
    # Simple and robust IP check
    local ip=$(curl -s --max-time 2 https://api.ipify.org)
    if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then echo "$ip"; return; fi
    hostname -I | awk '{print $1}'
}

draw_line() {
    echo -e "${BLUE}------------------------------------------------------------${RESET}"
}

header() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "  WGDASHBOARD MANAGER - v${VERSION}"
    echo "  Powered by UnknownZero"
    echo -e "${RESET}"
    
    draw_line
    
    # --- System Stats ---
    local sys_ip=$(get_public_ip)
    local ram_usage=$(free -h | awk '/Mem:/ {print $3 "/" $2}')
    local load=$(awk '{print $1}' /proc/loadavg)
    
    # --- App Status ---
    local app_status="${RED}NOT INSTALLED${RESET}"
    local app_port="--"
    
    if [ -d "$INSTALL_DIR" ]; then
        if docker compose -p "$PROJECT_NAME" ps | grep -q "Up"; then
            app_status="${GREEN}RUNNING${RESET}"
        else
            app_status="${RED}STOPPED${RESET}"
        fi
        local p=$(grep "wgd_port=" "$INSTALL_DIR/compose.yaml" 2>/dev/null | cut -d'=' -f2 | tr -d ' "')
        app_port="${p:-10086}"
    fi
    
    # --- Backup Status ---
    local bkp_status="${YELLOW}INACTIVE${RESET}"
    if [ -f "$BACKUP_SCRIPT_PATH" ]; then
        bkp_status="${GREEN}ACTIVE (Cron)${RESET}"
    fi

    # --- Display Info Table ---
    # Using simple echo for safety against formatting bugs
    echo -e " SERVER IP : ${BOLD}${sys_ip}${RESET}"
    echo -e " RAM USAGE : ${ram_usage}   |   LOAD: ${load}"
    echo -e " STATUS    : ${app_status}      |   PORT: ${app_port}"
    echo -e " BACKUP    : ${bkp_status}"
    
    draw_line
}

# Helper to print menu items cleanly
print_menu_item() {
    local num="$1"
    local txt="$2"
    local desc="$3"
    # Using printf for clean alignment
    printf " ${GREEN}[%s]${RESET} %-20s ${YELLOW}%s${RESET}\n" "$num" "$txt" "$desc"
}

msg() {
    local type=$1
    local txt=$2
    if [ "$type" == "info" ]; then echo -e " ${BLUE}[INFO]${RESET} $txt"; fi
    if [ "$type" == "ok" ]; then echo -e " ${GREEN}[OK]${RESET}   $txt"; fi
    if [ "$type" == "err" ]; then echo -e " ${RED}[ERR]${RESET}  $txt"; fi
    if [ "$type" == "warn" ]; then echo -e " ${YELLOW}[WARN]${RESET} $txt"; fi
}

input_prompt() {
    echo -ne " ${CYAN}>>${RESET} $1"
}

# --- Check Root ---
if [ "$EUID" -ne 0 ]; then echo "Please run as root."; exit 1; fi

# --- Modules ---

install_panel() {
    header
    msg "info" "Starting Installation..."
    echo ""
    
    local def_ip=$(get_public_ip)
    input_prompt "Public IP [$def_ip]: "; read IP_IN
    PUBLIC_IP=${IP_IN:-$def_ip}
    
    input_prompt "Username [admin]: "; read USER_IN
    WGD_USER=${USER_IN:-admin}
    
    while true; do
        input_prompt "Password: "; read -s WGD_PASS; echo ""
        if [ -n "$WGD_PASS" ]; then break; fi
        msg "err" "Password required."
    done
    
    input_prompt "Port [10086]: "; read PORT_IN
    WGD_PORT=${PORT_IN:-10086}

    echo ""
    msg "info" "Configuring Docker..."
    
    if ! grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf; then echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf; fi
    sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1

    if ! docker compose version &>/dev/null; then
        msg "warn" "Installing Docker Engine..."
        apt-get update -qq >/dev/null 2>&1
        apt-get install -y -qq ca-certificates curl gnupg lsb-release >/dev/null 2>&1
        mkdir -p /etc/apt/keyrings
        curl -fsSL --max-time 10 https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list >/dev/null
        apt-get update -qq >/dev/null 2>&1
        apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin >/dev/null 2>&1
    fi

    msg "info" "Creating Configuration..."
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
    
    if command -v ufw &>/dev/null && ufw status | grep -q "active"; then
        ufw allow $WGD_PORT/tcp >/dev/null; ufw allow 51820/udp >/dev/null
    fi

    msg "ok" "Installation Complete."
    echo "    URL: http://${PUBLIC_IP}:${WGD_PORT}"
    read -p "Press Enter..."
}

setup_backup_bot() {
    header
    msg "info" "Telegram Backup Configuration"
    echo ""
    
    apt-get update -qq >/dev/null 2>&1; apt-get install -y -qq zip curl cron >/dev/null 2>&1

    input_prompt "Bot Token: "; read TG_TOKEN
    input_prompt "Chat ID: "; read TG_CHATID
    
    if [[ -z "$TG_TOKEN" || -z "$TG_CHATID" ]]; then
        msg "err" "Input empty."
        read -p "Enter..."
        return
    fi

    msg "info" "Testing Connection..."
    TEST=$(curl -s --max-time 10 -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" -d chat_id="${TG_CHATID}" -d text="Connection Verified - WGDashboard Manager")
    
    if [[ "$TEST" != *"\"ok\":true"* ]]; then
        msg "err" "Failed. Check Token/ID."
        read -p "Enter..."
        return
    fi
    msg "ok" "Verified!"

    echo ""
    input_prompt "Server Name [WGD-Backup]: "; read PREFIX_IN
    BACKUP_PREFIX=${PREFIX_IN:-WGD-Backup}
    CLEAN_PREFIX=$(echo "$BACKUP_PREFIX" | tr -dc 'a-zA-Z0-9-._')

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

CAPTION="Backup: ${PREFIX} | IP: ${SERVER_IP} | Date: ${DATE}"

curl -s --max-time 45 -F chat_id="${CHAT_ID}" -F caption="${CAPTION}" -F document=@"${ZIP_FILE}" "https://api.telegram.org/bot${TOKEN}/sendDocument"
rm -rf "${TEMP_DIR}"
EOS
    
    echo ""
    msg "info" "Frequency:"
    echo "    1) Every 30 Minutes"
    echo "    2) Every 6 Hours"
    echo "    3) Daily"
    input_prompt "Select: "; read FREQ
    
    case $FREQ in
        1) CRON="*/30 * * * *" ;;
        2) CRON="0 */6 * * *" ;; 
        3) input_prompt "Hour (0-23): "; read H; CRON="0 ${H:-0} * * *" ;;
        *) CRON="0 3 * * *" ;;
    esac

    (crontab -l 2>/dev/null | grep -vF "$BACKUP_SCRIPT_PATH") | crontab -
    (crontab -l 2>/dev/null; echo "$CRON $BACKUP_SCRIPT_PATH") | crontab -
    
    msg "ok" "Scheduled! Sending Test Backup..."
    bash "$BACKUP_SCRIPT_PATH"
    read -p "Press Enter..."
}

restore_backup() {
    header
    msg "warn" "Restore Wizard (WARNING: Overwrites Data)"
    echo ""
    
    mapfile -t BACKUPS < <(ls /root/*.zip 2>/dev/null)
    if [ ${#BACKUPS[@]} -eq 0 ]; then
        msg "err" "No .zip files found in /root/"
        read -p "Press Enter..."
        return
    fi

    echo " Available Backups:"
    i=1
    for f in "${BACKUPS[@]}"; do
        echo "    $i) $(basename "$f")"
        ((i++))
    done
    echo ""
    
    input_prompt "Select File Number: "; read CHOICE
    if [[ ! "$CHOICE" =~ ^[0-9]+$ ]] || [ "$CHOICE" -lt 1 ] || [ "$CHOICE" -gt "${#BACKUPS[@]}" ]; then
        msg "err" "Invalid Selection."
        read -p "Press Enter..."
        return
    fi
    
    FILE_FULL_PATH="${BACKUPS[$((CHOICE-1))]}"
    
    echo ""
    input_prompt "Type 'restore' to confirm: "; read CONFIRM
    if [ "$CONFIRM" == "restore" ]; then
        msg "info" "Restoring..."
        apt-get install -y -qq unzip >/dev/null
        
        if [ -d "$INSTALL_DIR" ]; then cd "$INSTALL_DIR"; docker compose -p "$PROJECT_NAME" down >/dev/null 2>&1; fi
        
        TEMP_RESTORE=$(mktemp -d)
        unzip -q "$FILE_FULL_PATH" -d "$TEMP_RESTORE"
        SOURCE_DIR=$(find "$TEMP_RESTORE" -type d -name "wireguard_conf" | xargs dirname | head -n 1)

        VOL_CONF=$(docker volume inspect ${PROJECT_NAME}_conf --format '{{.Mountpoint}}' 2>/dev/null)
        VOL_DATA=$(docker volume inspect ${PROJECT_NAME}_data --format '{{.Mountpoint}}' 2>/dev/null)
        VOL_ACONF=$(docker volume inspect ${PROJECT_NAME}_aconf --format '{{.Mountpoint}}' 2>/dev/null)
        
        if [ -z "$VOL_CONF" ]; then VOL_CONF=$(docker volume inspect wgdashboard_conf --format '{{.Mountpoint}}' 2>/dev/null); fi
        if [ -z "$VOL_DATA" ]; then VOL_DATA=$(docker volume inspect wgdashboard_data --format '{{.Mountpoint}}' 2>/dev/null); fi
        if [ -z "$VOL_ACONF" ]; then VOL_ACONF=$(docker volume inspect wgdashboard_aconf --format '{{.Mountpoint}}' 2>/dev/null); fi

        if [ -n "$VOL_CONF" ] && [ -d "$SOURCE_DIR/wireguard_conf" ]; then rm -rf "$VOL_CONF"/*; cp -r "$SOURCE_DIR/wireguard_conf"/* "$VOL_CONF/"; fi
        if [ -n "$VOL_DATA" ] && [ -d "$SOURCE_DIR/dashboard_data" ]; then rm -rf "$VOL_DATA"/*; cp -r "$SOURCE_DIR/dashboard_data"/* "$VOL_DATA/"; fi
        if [ -n "$VOL_ACONF" ] && [ -d "$SOURCE_DIR/amnezia_conf" ]; then rm -rf "$VOL_ACONF"/*; cp -r "$SOURCE_DIR/amnezia_conf"/* "$VOL_ACONF/"; fi
        
        chmod -R 755 "$VOL_CONF" "$VOL_DATA" 2>/dev/null
        docker compose -p "$PROJECT_NAME" up -d >/dev/null 2>&1
        rm -rf "$TEMP_RESTORE"
        msg "ok" "Restore Complete."
    fi
    read -p "Press Enter..."
}

uninstall_all() {
    header
    msg "warn" "UNINSTALL ALL COMPONENTS"
    input_prompt "Type 'yes' to confirm: "; read CONFIRM
    if [ "$CONFIRM" == "yes" ]; then
        if [ -d "$INSTALL_DIR" ]; then cd "$INSTALL_DIR"; docker compose -p "$PROJECT_NAME" down >/dev/null 2>&1; fi
        rm -rf "$INSTALL_DIR" "$BACKUP_SCRIPT_PATH"
        (crontab -l 2>/dev/null | grep -vF "$BACKUP_SCRIPT_PATH") | crontab -
        
        echo ""
        input_prompt "Wipe DATA? (yes/no): "; read WIPE
        if [ "$WIPE" == "yes" ]; then
             docker volume rm ${PROJECT_NAME}_conf ${PROJECT_NAME}_data ${PROJECT_NAME}_aconf >/dev/null 2>&1
             docker volume rm wgdashboard_conf wgdashboard_data wgdashboard_aconf >/dev/null 2>&1
             msg "ok" "Data Wiped."
        fi
        msg "ok" "Uninstalled."
    fi
    read -p "Press Enter..."
}

remove_backup_only() {
    (crontab -l 2>/dev/null | grep -vF "$BACKUP_SCRIPT_PATH") | crontab -
    rm -f "$BACKUP_SCRIPT_PATH"
    msg "ok" "Backup Disabled."
    read -p "Enter..."
}

update_panel() {
    if [ -d "$INSTALL_DIR" ]; then 
        cd "$INSTALL_DIR"
        msg "info" "Updating..."
        docker compose -p "$PROJECT_NAME" pull
        docker compose -p "$PROJECT_NAME" up -d
        docker image prune -f >/dev/null 2>&1
        msg "ok" "Updated."
    else
        msg "err" "Not installed."
    fi
    read -p "Enter..."
}

view_logs() {
    if [ -d "$INSTALL_DIR" ]; then cd "$INSTALL_DIR"; docker compose -p "$PROJECT_NAME" logs -f --tail=50; else msg "err" "Not installed."; read -p "Enter..."; fi
}

# --- Main Loop ---
while true; do
    header
    
    echo -e "${BOLD} PANEL MANAGEMENT:${RESET}"
    print_menu_item "1" "Install Panel" "Deploy new VPN Dashboard"
    print_menu_item "2" "Update Panel" "Update to latest version"
    print_menu_item "5" "View Logs" "Check System Logs"
    
    echo ""
    echo -e "${BOLD} BACKUP & RESTORE:${RESET}"
    print_menu_item "3" "Setup Backup" "Auto Telegram Backup"
    print_menu_item "4" "Restore Data" "Restore from local .zip"
    print_menu_item "6" "Disable Bot" "Turn off Auto-Backup"
    
    echo ""
    echo -e "${BOLD} DANGER ZONE:${RESET}"
    print_menu_item "0" "Uninstall" "Remove All Components"
    
    echo ""
    echo -e " Press ${RED}9${RESET} to Exit"
    echo ""
    input_prompt "Select Option: "; read OPTION
    
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
