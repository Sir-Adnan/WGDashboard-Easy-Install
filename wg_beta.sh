#!/bin/bash

# ==================================================
#   WGDASHBOARD MASTER v20.0 - The Ultimate UI
#   Visuals: Inspired by GRE Master (Cyberpunk)
#   Logic: V11 (Bug Free & Secure)
# ==================================================

# --- 🎨 THEME & COLORS (Matches your GRE script) ---
BOLD='\033[1m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
WHITE='\033[1;37m'
GREY='\033[0;90m'
NC='\033[0m'
HI_CYAN='\033[0;96m'
HI_PINK='\033[0;95m'
HI_GREEN='\033[0;92m'

# --- CONSTANTS ---
INSTALL_DIR="/opt/wgdashboard"
BACKUP_SCRIPT_PATH="/usr/local/bin/wgd-backup.sh"
PROJECT_NAME="wgdashboard"
VERSION="20.0"
AUTHOR="UnknownZero"

# --- UTILS ---

get_public_ip() {
    local ip=$(curl -s --max-time 2 https://api.ipify.org)
    if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then echo "$ip"; return; fi
    ip=$(curl -s --max-time 2 https://ipv4.icanhazip.com)
    if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then echo "$ip"; return; fi
    hostname -I | awk '{print $1}'
}

# --- UI COMPONENTS ---

draw_logo() {
    clear
    echo -e "${HI_CYAN}"
    echo " _       __   ______     ____            __     "
    echo "| |     / /  / ____/    / __ \  ____    / /     "
    echo "| | /| / /  / / __     / / / / / __ \  / /      "
    echo "| |/ |/ /  / /_/ /    / /_/ / / /_/ / /_/       "
    echo "|__/|__/   \____/    /_____/  \____/ (_)        "
    echo -e "${NC}"
    echo -e "      ${HI_PINK}VPN DASHBOARD MANAGER${NC} | ${GREY}v${VERSION}${NC}"
    echo ""
}

draw_dashboard() {
    # Data Gathering
    local ip=$(get_public_ip)
    local ram=$(free -h | awk '/Mem:/ {print $3 "/" $2}')
    local load=$(awk '{print $1}' /proc/loadavg)
    
    # App Status
    local status="${RED}OFFLINE${NC}"
    local port="--"
    if [ -d "$INSTALL_DIR" ] && docker compose -p "$PROJECT_NAME" ps | grep -q "Up"; then
        status="${HI_GREEN}ONLINE${NC}"
        port=$(grep "wgd_port=" "$INSTALL_DIR/compose.yaml" 2>/dev/null | cut -d'=' -f2 | tr -d ' "')
    fi
    
    # Backup Status
    local bkp="${GREY}Disabled${NC}"
    if [ -f "$BACKUP_SCRIPT_PATH" ]; then bkp="${HI_CYAN}Active${NC}"; fi

    # Drawing the Box (GRE Style)
    echo -e "${HI_CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    printf "${HI_CYAN}║${NC}  🌐 IP: %-20b   💾 RAM: %-20b ${HI_CYAN}║${NC}\n" "${WHITE}$ip${NC}" "${WHITE}$ram${NC}"
    printf "${HI_CYAN}║${NC}  📊 Load: %-18b   🚀 Port: %-19b ${HI_CYAN}║${NC}\n" "${WHITE}$load${NC}" "${YELLOW}${port:-10086}${NC}"
    printf "${HI_CYAN}║${NC}  🔋 Panel: %-28b 📦 Backup: %-16b ${HI_CYAN}║${NC}\n" "$status" "$bkp"
    echo -e "${HI_CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_item() {
    local id=$1
    local title=$2
    local desc=$3
    # Dots padding
    local dots="........................................"
    printf " ${HI_GREEN}[%d]${NC} ${HI_CYAN}%-18s${NC} ${GREY}%s${NC}\n" "$id" "$title" "$desc"
}

msg_box() {
    local type="$1"
    local text="$2"
    case $type in
        "info")  echo -e " ${BLUE}ℹ${NC}  $text" ;;
        "ok")    echo -e " ${HI_GREEN}✔${NC}  $text" ;;
        "warn")  echo -e " ${YELLOW}⚠${NC}  $text" ;;
        "err")   echo -e " ${RED}✖${NC}  $text" ;;
        "inp")   echo -ne " ${HI_PINK}➤${NC}  $text" ;;
    esac
}

# --- MODULES ---

install_panel() {
    draw_logo
    echo -e "\n${YELLOW}➤ INSTALLATION WIZARD${NC}"
    echo -e "${GREY}──────────────────────────────────────────────────────────────${NC}"
    
    local def_ip=$(get_public_ip)
    msg_box "inp" "Public IP [Default: $def_ip]: "; read IP_IN
    PUBLIC_IP=${IP_IN:-$def_ip}
    
    msg_box "inp" "Username [Default: admin]: "; read USER_IN
    WGD_USER=${USER_IN:-admin}
    
    while true; do
        msg_box "inp" "Password: "; read -s WGD_PASS; echo ""
        if [ -n "$WGD_PASS" ]; then break; fi
        msg_box "err" "Password cannot be empty!"
    done
    
    msg_box "inp" "Port [Default: 10086]: "; read PORT_IN
    WGD_PORT=${PORT_IN:-10086}

    echo -e "\n${BLUE}➤ System Configuration...${NC}"
    if ! grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf; then echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf; fi
    sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1

    if ! docker compose version &>/dev/null; then
        msg_box "warn" "Installing Docker Engine..."
        apt-get update -qq >/dev/null 2>&1
        apt-get install -y -qq ca-certificates curl gnupg lsb-release >/dev/null 2>&1
        mkdir -p /etc/apt/keyrings
        curl -fsSL --max-time 10 https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list >/dev/null
        apt-get update -qq >/dev/null 2>&1
        apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin >/dev/null 2>&1
    fi

    echo -e "${BLUE}➤ Deploying Containers...${NC}"
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

    echo ""
    msg_box "ok" "Installation Successful!"
    echo -e "   Login: ${HI_CYAN}http://${PUBLIC_IP}:${WGD_PORT}${NC}"
    read -p "   Press Enter..."
}

setup_backup_bot() {
    draw_logo
    echo -e "\n${YELLOW}➤ TELEGRAM BACKUP SETUP${NC}"
    echo -e "${GREY}──────────────────────────────────────────────────────────────${NC}"
    
    apt-get update -qq >/dev/null 2>&1; apt-get install -y -qq tar gzip curl cron >/dev/null 2>&1

    msg_box "inp" "Bot Token: "; read TG_TOKEN
    msg_box "inp" "Chat ID: "; read TG_CHATID
    
    if [[ -z "$TG_TOKEN" || -z "$TG_CHATID" ]]; then
        msg_box "err" "Credentials required."
        read -p "   Press Enter..."; return
    fi

    msg_box "info" "Verifying Connection..."
    TEST=$(curl -s --max-time 10 -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" -d chat_id="${TG_CHATID}" -d text="🔌 Connection Verified by WGDashboard Manager")
    
    if [[ "$TEST" != *"\"ok\":true"* ]]; then
        msg_box "err" "Connection Failed."
        read -p "   Press Enter..."; return
    fi
    msg_box "ok" "Verified!"

    echo ""
    msg_box "inp" "Server Name (e.g. UAE-1): "; read PREFIX_IN
    BACKUP_PREFIX=${PREFIX_IN:-WGD-Backup}
    CLEAN_PREFIX=$(echo "$BACKUP_PREFIX" | tr -dc 'a-zA-Z0-9-._')

    rm -f "$BACKUP_SCRIPT_PATH"; touch "$BACKUP_SCRIPT_PATH"; chmod +x "$BACKUP_SCRIPT_PATH"
    
    # --- WRITE SCRIPT ---
    echo "#!/bin/bash" > "$BACKUP_SCRIPT_PATH"
    echo "export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" >> "$BACKUP_SCRIPT_PATH"
    echo "TOKEN=\"$TG_TOKEN\"" >> "$BACKUP_SCRIPT_PATH"
    echo "CHAT_ID=\"$TG_CHATID\"" >> "$BACKUP_SCRIPT_PATH"
    echo "PREFIX=\"$CLEAN_PREFIX\"" >> "$BACKUP_SCRIPT_PATH"
    echo "PROJECT=\"$PROJECT_NAME\"" >> "$BACKUP_SCRIPT_PATH"
    
    cat <<'EOS' >> "$BACKUP_SCRIPT_PATH"
SERVER_IP=$(curl -s --max-time 5 ifconfig.me || hostname -I | awk '{print $1}')
DATE=$(date +'%Y-%m-%d %H:%M')
FILENAME="${PREFIX}_$(date +'%Y-%m-%d_%H-%M')"
TEMP_DIR=$(mktemp -d)
BACKUP_DIR="${TEMP_DIR}/${FILENAME}"
ARCHIVE_FILE="${TEMP_DIR}/${FILENAME}.tar.gz"
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
tar -czf "${ARCHIVE_FILE}" "${FILENAME}" >/dev/null 2>&1

# --- BEAUTIFUL HTML CAPTION ---
CAPTION="🔐 <b>WGDashboard Backup</b>
━━━━━━━━━━━━━━━━━━
🏷 <b>Server:</b> <code>${PREFIX}</code>
🌍 <b>IP Addr:</b> <code>${SERVER_IP}</code>
📅 <b>Time:</b> <code>${DATE}</code>
━━━━━━━━━━━━━━━━━━
✅ <i>Config & Database Secured.</i>"

curl -s --max-time 45 -F chat_id="${CHAT_ID}" -F caption="${CAPTION}" -F parse_mode="HTML" -F document=@"${ARCHIVE_FILE}" "https://api.telegram.org/bot${TOKEN}/sendDocument"
rm -rf "${TEMP_DIR}"
EOS
    
    echo ""
    echo -e "   ${HI_CYAN}[1]${NC} Every 30 Minutes"
    echo -e "   ${HI_CYAN}[2]${NC} Custom Interval (Every X hours)"
    echo -e "   ${HI_CYAN}[3]${NC} Daily (At specific hour)"
    echo ""
    msg_box "inp" "Select Frequency: "; read FREQ
    
    case $FREQ in
        1) 
            CRON="*/30 * * * *" 
            ;;
        2) 
            echo -e "   ${GREY}Specify the interval in hours (e.g., '2' = every 2 hours, '6' = every 6 hours).${NC}"
            msg_box "inp" "Enter hours [1-23]: "; read C_HOUR
            if [[ ! "$C_HOUR" =~ ^[0-9]+$ ]] || [ "$C_HOUR" -lt 1 ] || [ "$C_HOUR" -gt 23 ]; then
                msg_box "warn" "Invalid input. Defaulting to every 1 hour."
                C_HOUR=1
            fi
            CRON="0 */${C_HOUR} * * *" 
            ;; 
        3) 
            msg_box "inp" "Hour (0-23): "; read H
            if [[ ! "$H" =~ ^[0-9]+$ ]] || [ "$H" -lt 0 ] || [ "$H" -gt 23 ]; then
                H=0
            fi
            CRON="0 ${H} * * *" 
            ;;
        *) 
            CRON="0 3 * * *" 
            ;;
    esac

    (crontab -l 2>/dev/null | grep -vF "$BACKUP_SCRIPT_PATH") | crontab -
    (crontab -l 2>/dev/null; echo "$CRON $BACKUP_SCRIPT_PATH") | crontab -
    
    echo ""
    msg_box "ok" "Backup Scheduled! Sending test file now..."
    bash "$BACKUP_SCRIPT_PATH"
    read -p "   Press Enter..."
}

restore_backup() {
    draw_logo
    echo -e "\n${YELLOW}➤ RESTORE WIZARD${NC}"
    echo -e "${GREY}──────────────────────────────────────────────────────────────${NC}"
    
    mapfile -t BACKUPS < <(ls /root/*.tar.gz 2>/dev/null)
    if [ ${#BACKUPS[@]} -eq 0 ]; then
        msg_box "err" "No .tar.gz files found in /root/ directory."
        read -p "   Press Enter..."; return
    fi

    echo -e "   ${WHITE}Available Backups in /root/:${NC}"
    i=1
    for f in "${BACKUPS[@]}"; do
        echo -e "   ${GREEN}[$i]${NC} $(basename "$f")"
        ((i++))
    done
    echo ""
    
    msg_box "inp" "Select File Number: "; read CHOICE
    if [[ ! "$CHOICE" =~ ^[0-9]+$ ]] || [ "$CHOICE" -lt 1 ] || [ "$CHOICE" -gt "${#BACKUPS[@]}" ]; then
        msg_box "err" "Invalid selection."
        read -p "   Press Enter..."; return
    fi
    
    FILE_FULL_PATH="${BACKUPS[$((CHOICE-1))]}"
    
    echo ""
    echo -e "   ${RED}⚠ WARNING: This will OVERWRITE all current VPN users/data!${NC}"
    msg_box "inp" "Type 'restore' to confirm: "; read CONFIRM
    if [ "$CONFIRM" == "restore" ]; then
        echo ""
        msg_box "info" "Installing Extraction Tools..."
        apt-get install -y -qq tar gzip >/dev/null
        
        msg_box "info" "Stopping Panel..."
        if [ -d "$INSTALL_DIR" ]; then cd "$INSTALL_DIR"; docker compose -p "$PROJECT_NAME" down >/dev/null 2>&1; fi
        
        msg_box "info" "Extracting Data..."
        TEMP_RESTORE=$(mktemp -d)
        tar -xzf "$FILE_FULL_PATH" -C "$TEMP_RESTORE"
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
        msg_box "info" "Restarting Panel..."
        docker compose -p "$PROJECT_NAME" up -d >/dev/null 2>&1
        rm -rf "$TEMP_RESTORE"
        echo ""
        msg_box "ok" "Restore Completed Successfully!"
    fi
    read -p "   Press Enter..."
}

uninstall_all() {
    echo -e "\n${RED}➤ UNINSTALL${NC}"
    msg_box "inp" "Are you sure? (yes/no): "; read CONFIRM
    if [ "$CONFIRM" == "yes" ]; then
        if [ -d "$INSTALL_DIR" ]; then cd "$INSTALL_DIR"; docker compose -p "$PROJECT_NAME" down >/dev/null 2>&1; fi
        rm -rf "$INSTALL_DIR" "$BACKUP_SCRIPT_PATH"
        (crontab -l 2>/dev/null | grep -vF "$BACKUP_SCRIPT_PATH") | crontab -
        
        msg_box "inp" "Delete ALL VPN Data? (y/n): "; read WIPE
        if [ "$WIPE" == "y" ]; then
             docker volume rm ${PROJECT_NAME}_conf ${PROJECT_NAME}_data ${PROJECT_NAME}_aconf >/dev/null 2>&1
             docker volume rm wgdashboard_conf wgdashboard_data wgdashboard_aconf >/dev/null 2>&1
             msg_box "ok" "Data Wiped."
        fi
        msg_box "ok" "Uninstalled."
    fi
    read -p "   Press Enter..."
}

remove_backup_only() {
    (crontab -l 2>/dev/null | grep -vF "$BACKUP_SCRIPT_PATH") | crontab -
    rm -f "$BACKUP_SCRIPT_PATH"
    msg_box "ok" "Backup Disabled."
    read -p "   Press Enter..."
}

update_panel() {
    if [ -d "$INSTALL_DIR" ]; then 
        cd "$INSTALL_DIR"
        msg_box "info" "Pulling images..."
        docker compose -p "$PROJECT_NAME" pull
        docker compose -p "$PROJECT_NAME" up -d
        docker image prune -f >/dev/null 2>&1
        msg_box "ok" "Updated."
    else
        msg_box "err" "Not installed."
    fi
    read -p "   Press Enter..."
}

view_logs() {
    if [ -d "$INSTALL_DIR" ]; then cd "$INSTALL_DIR"; docker compose -p "$PROJECT_NAME" logs -f --tail=50; else msg_box "err" "Not installed."; read -p "   Press Enter..."; fi
}

# --- MAIN LOOP ---
while true; do
    draw_logo
    draw_dashboard
    
    echo -e "${YELLOW} MANAGEMENT${NC}"
    print_item 1 "Install Panel" "Deploy new VPN Panel"
    print_item 2 "Update Panel" "Update Core (Safe)"
    print_item 3 "View Logs" "Debug Containers"
    
    echo -e "${GREY}──────────────────────────────────────────────────────────────${NC}"
    echo -e "${YELLOW} BACKUP & RESTORE${NC}"
    print_item 4 "Setup Bot" "Auto-Backup to Telegram"
    print_item 5 "Restore Data" "Restore from .tar.gz File"
    print_item 6 "Disable Bot" "Stop Cron Jobs"
    
    echo -e "${GREY}──────────────────────────────────────────────────────────────${NC}"
    echo -e "${YELLOW} SYSTEM${NC}"
    echo -e " ${BOLD}[0] ${RED}Uninstall${NC}       ${GREY}Remove All Components${NC}"
    echo -e " ${BOLD}[9] ${WHITE}Exit${NC}"
    
    echo ""
    echo -ne " ${HI_PINK}➤ Select Option : ${NC}"
    read OPTION
    
    case $OPTION in
        1) install_panel ;;
        2) update_panel ;;
        3) view_logs ;;
        4) setup_backup_bot ;;
        5) restore_backup ;;
        6) remove_backup_only ;;
        0) uninstall_all ;;
        9) clear; exit 0 ;;
        *) ;;
    esac
done
