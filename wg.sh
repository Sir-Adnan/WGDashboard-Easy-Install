#!/bin/bash

# =========================================================
#  WGDashboard Manager - V18 (Clean UI Edition)
#  Author: UnknownZero
#  Fixes: Broken Colors, HTML IP Errors, Alignment
# =========================================================

# --- Safe Colors (Standard ANSI) ---
# Using standard colors ensures compatibility with all terminals
C_RESET='\033[0m'
C_BOLD='\033[1m'
C_RED='\033[31m'
C_GREEN='\033[32m'
C_YELLOW='\033[33m'
C_BLUE='\033[34m'
C_PURPLE='\033[35m'
C_CYAN='\033[36m'
C_WHITE='\033[37m'
C_GRAY='\033[90m'

# --- Configuration ---
INSTALL_DIR="/opt/wgdashboard"
BACKUP_SCRIPT_PATH="/usr/local/bin/wgd-backup.sh"
PROJECT_NAME="wgdashboard"
VERSION="18.0"
AUTHOR="UnknownZero"

# --- Robust IP Detection (Fixes HTML Dump) ---
get_public_ip() {
    # Try 1: ipify
    local ip=$(curl -s --max-time 2 https://api.ipify.org)
    if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then echo "$ip"; return; fi
    
    # Try 2: icanhazip
    ip=$(curl -s --max-time 2 https://ipv4.icanhazip.com)
    if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then echo "$ip"; return; fi
    
    # Fallback
    hostname -I | awk '{print $1}'
}

# --- UI Functions ---

# Print a formatted menu line
# Usage: print_line "Number" "Title" "Description" "Color"
print_line() {
    local id=$1
    local title=$2
    local desc=$3
    local color=${4:-$C_GREEN}
    
    printf " ${color}[%s]${C_RESET} %-22s ${C_GRAY}%s${C_RESET}\n" "$id" "$title" "$desc"
}

print_category() {
    echo -e "\n ${C_YELLOW}:: $1 ::${C_RESET}"
}

header() {
    clear
    # Clean ASCII Logo
    echo -e "${C_CYAN}"
    echo " _       __   ______     __  ___"
    echo "| |     / /  / ____/    /  |/  /"
    echo "| | /| / /  / / __     / /|_/ / "
    echo "| |/ |/ /  / /_/ /    / /  / /  "
    echo "|__/|__/   \____/    /_/  /_/   "
    echo -e "${C_RESET}"
    
    echo -e " Manager v${VERSION} by ${C_PURPLE}${AUTHOR}${C_RESET}"
    echo -e " ${C_GRAY}──────────────────────────────────────────────────────────${C_RESET}"
    
    # --- System Stats ---
    local sys_ip=$(get_public_ip)
    
    # RAM Calculation
    local ram_used=$(free -m | awk '/Mem:/ {print $3}')
    local ram_total=$(free -m | awk '/Mem:/ {print $2}')
    local ram_color="${C_GREEN}"
    if [ "$ram_used" -gt "$((ram_total * 80 / 100))" ]; then ram_color="${C_RED}"; fi
    
    # Load Average
    local sys_load=$(cat /proc/loadavg | awk '{print $1}')
    
    # App Status Check
    local status_text="${C_RED}OFFLINE${C_RESET}"
    local port_text="--"
    
    if [ -d "$INSTALL_DIR" ]; then
        if docker compose -p "$PROJECT_NAME" ps | grep -q "Up"; then
            status_text="${C_GREEN}ONLINE${C_RESET}"
        fi
        # Extract Port
        local p=$(grep "wgd_port=" "$INSTALL_DIR/compose.yaml" 2>/dev/null | cut -d'=' -f2 | tr -d ' "')
        port_text="${p:-10086}"
    else
        status_text="${C_GRAY}NOT INSTALLED${C_RESET}"
    fi

    # Backup Status
    local bkp_text="${C_GRAY}DISABLED${C_RESET}"
    if [ -f "$BACKUP_SCRIPT_PATH" ]; then
        bkp_text="${C_GREEN}ACTIVE${C_RESET}"
    fi

    # --- Dashboard Style Info ---
    # Using printf for perfect alignment
    printf " ${C_BLUE}%-6s${C_RESET} %-18s ${C_BLUE}%-6s${C_RESET} %-10s\n" "IP:" "$sys_ip" "RAM:" "${ram_color}${ram_used}${C_RESET}/${ram_total}MB"
    printf " ${C_BLUE}%-6s${C_RESET} %-18s ${C_BLUE}%-6s${C_RESET} %-10s\n" "Load:" "$sys_load" "Panel:" "$status_text"
    printf " ${C_BLUE}%-6s${C_RESET} %-18s ${C_BLUE}%-6s${C_RESET} %-10s\n" "Port:" "$port_text" "Bkp:" "$bkp_text"
    
    echo -e " ${C_GRAY}──────────────────────────────────────────────────────────${C_RESET}"
}

msg_box() {
    local type="$1"
    local text="$2"
    case $type in
        "info")    echo -e " ${C_BLUE}ℹ${C_RESET}  $text" ;;
        "success") echo -e " ${C_GREEN}✔${C_RESET}  $text" ;;
        "warn")    echo -e " ${C_YELLOW}⚠${C_RESET}  $text" ;;
        "error")   echo -e " ${C_RED}✖${C_RESET}  $text" ;;
        "input")   echo -ne " ${C_CYAN}➤${C_RESET}  $text" ;;
    esac
}

# --- Check Root ---
if [ "$EUID" -ne 0 ]; then echo -e "${C_RED}Error: Please run as root.${C_RESET}"; exit 1; fi

# --- Modules ---

install_panel() {
    header
    msg_box "info" "Starting Installation..."
    echo ""
    
    local ip=$(get_public_ip)
    msg_box "input" "Public IP [$ip]: "; read IP_IN
    PUBLIC_IP=${IP_IN:-$ip}
    
    msg_box "input" "Username [admin]: "; read USER_IN
    WGD_USER=${USER_IN:-admin}
    
    while true; do
        msg_box "input" "Password: "; read -s WGD_PASS; echo ""
        if [ -n "$WGD_PASS" ]; then break; fi
        msg_box "error" "Password cannot be empty."
    done
    
    msg_box "input" "Port [10086]: "; read PORT_IN
    WGD_PORT=${PORT_IN:-10086}

    echo ""
    msg_box "info" "Installing Dependencies..."
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

    msg_box "info" "Deploying Container..."
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

    msg_box "success" "Install Complete! Access: http://${PUBLIC_IP}:${WGD_PORT}"
    read -p "Press Enter to return..."
}

setup_backup_bot() {
    header
    msg_box "info" "Telegram Backup Setup"
    echo ""
    
    apt-get update -qq >/dev/null 2>&1; apt-get install -y -qq zip curl cron >/dev/null 2>&1

    msg_box "input" "Bot Token: "; read TG_TOKEN
    msg_box "input" "Chat ID: "; read TG_CHATID
    
    if [[ -z "$TG_TOKEN" || -z "$TG_CHATID" ]]; then
        msg_box "error" "Missing credentials."
        read -p "Enter..."
        return
    fi

    msg_box "info" "Verifying Token..."
    TEST=$(curl -s --max-time 10 -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" -d chat_id="${TG_CHATID}" -d text="🔌 Connection Verified!")
    
    if [[ "$TEST" != *"\"ok\":true"* ]]; then
        msg_box "error" "Connection Failed."
        read -p "Enter..."
        return
    fi
    msg_box "success" "Verified!"

    echo ""
    msg_box "input" "Server Name [WGD-Backup]: "; read PREFIX_IN
    BACKUP_PREFIX=${PREFIX_IN:-WGD-Backup}
    CLEAN_PREFIX=$(echo "$BACKUP_PREFIX" | tr -dc 'a-zA-Z0-9-._')

    rm -f "$BACKUP_SCRIPT_PATH"; touch "$BACKUP_SCRIPT_PATH"; chmod +x "$BACKUP_SCRIPT_PATH"
    
    # Generate Script
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
ZIP_FILE="${TEMP_DIR}/${FILENAME}.zip"
mkdir -p "${BACKUP_DIR}"

# Determine Volumes
VOL_CONF=$(docker volume inspect ${PROJECT}_conf --format '{{.Mountpoint}}' 2>/dev/null)
VOL_DATA=$(docker volume inspect ${PROJECT}_data --format '{{.Mountpoint}}' 2>/dev/null)
VOL_ACONF=$(docker volume inspect ${PROJECT}_aconf --format '{{.Mountpoint}}' 2>/dev/null)

if [ -z "$VOL_CONF" ]; then VOL_CONF=$(docker volume inspect wgdashboard_conf --format '{{.Mountpoint}}' 2>/dev/null); fi
if [ -z "$VOL_DATA" ]; then VOL_DATA=$(docker volume inspect wgdashboard_data --format '{{.Mountpoint}}' 2>/dev/null); fi
if [ -z "$VOL_ACONF" ]; then VOL_ACONF=$(docker volume inspect wgdashboard_aconf --format '{{.Mountpoint}}' 2>/dev/null); fi

# Copy
if [ -n "$VOL_CONF" ] && [ -d "$VOL_CONF" ]; then cp -r "$VOL_CONF" "${BACKUP_DIR}/wireguard_conf"; fi
if [ -n "$VOL_DATA" ] && [ -d "$VOL_DATA" ]; then cp -r "$VOL_DATA" "${BACKUP_DIR}/dashboard_data"; fi
if [ -n "$VOL_ACONF" ] && [ -d "$VOL_ACONF" ]; then cp -r "$VOL_ACONF" "${BACKUP_DIR}/amnezia_conf"; fi

cd "${TEMP_DIR}"
zip -r "${ZIP_FILE}" "${FILENAME}" >/dev/null 2>&1

# CLEAN & TIDY CAPTION
CAPTION="📦 <b>Backup Report</b>
━━━━━━━━━━━━━━━
🏷 <b>Name:</b> <code>${PREFIX}</code>
🌍 <b>IP:</b> <code>${SERVER_IP}</code>
📅 <b>Date:</b> <code>${DATE}</code>
━━━━━━━━━━━━━━━
✅ <i>Securely archived config & db</i>"

curl -s --max-time 45 -F chat_id="${CHAT_ID}" -F caption="${CAPTION}" -F parse_mode="HTML" -F document=@"${ZIP_FILE}" "https://api.telegram.org/bot${TOKEN}/sendDocument"
rm -rf "${TEMP_DIR}"
EOS
    
    echo ""
    msg_box "info" "Frequency Selection:"
    echo -e "   ${C_CYAN}1)${C_RESET} Every 30 Minutes"
    echo -e "   ${C_CYAN}2)${C_RESET} Every 6 Hours"
    echo -e "   ${C_CYAN}3)${C_RESET} Daily"
    msg_box "input" "Select Option: "; read FREQ
    
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
    msg_box "warn" "Restore Wizard (Overwrites Data)"
    echo ""
    
    mapfile -t BACKUPS < <(ls /root/*.zip 2>/dev/null)
    if [ ${#BACKUPS[@]} -eq 0 ]; then
        msg_box "error" "No .zip files in /root/"
        read -p "Enter..."
        return
    fi

    echo -e "${C_GRAY}Available Backups:${C_RESET}"
    i=1
    for f in "${BACKUPS[@]}"; do
        echo -e " ${C_CYAN}$i)${C_RESET} $(basename "$f")"
        ((i++))
    done
    echo ""
    
    msg_box "input" "Select File #: "; read CHOICE
    if [[ ! "$CHOICE" =~ ^[0-9]+$ ]] || [ "$CHOICE" -lt 1 ] || [ "$CHOICE" -gt "${#BACKUPS[@]}" ]; then
        msg_box "error" "Invalid."
        read -p "Enter..."
        return
    fi
    
    FILE_FULL_PATH="${BACKUPS[$((CHOICE-1))]}"
    
    msg_box "input" "Type 'restore' to confirm: "; read CONFIRM
    if [ "$CONFIRM" == "restore" ]; then
        msg_box "info" "Restoring..."
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
        msg_box "success" "Restore Complete!"
    fi
    read -p "Enter..."
}

uninstall_all() {
    header
    msg_box "warn" "UNINSTALL EVERYTHING"
    msg_box "input" "Type 'yes' to confirm: "; read CONFIRM
    if [ "$CONFIRM" == "yes" ]; then
        if [ -d "$INSTALL_DIR" ]; then cd "$INSTALL_DIR"; docker compose -p "$PROJECT_NAME" down >/dev/null 2>&1; fi
        rm -rf "$INSTALL_DIR" "$BACKUP_SCRIPT_PATH"
        (crontab -l 2>/dev/null | grep -vF "$BACKUP_SCRIPT_PATH") | crontab -
        
        echo ""
        msg_box "input" "Wipe data volumes? (yes/no): "; read WIPE
        if [ "$WIPE" == "yes" ]; then
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
    msg_box "success" "Backup Disabled."
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

# --- Main Loop ---
while true; do
    header
    
    print_category "PANEL MANAGEMENT"
    print_line 1 "Install Dashboard" "Deploy new VPN Panel"
    print_line 2 "Update Dashboard" "Update Core (Safe)"
    print_line 5 "View Logs" "Debug Containers" $C_BLUE
    
    print_category "BACKUP & RESTORE"
    print_line 3 "Setup Bot" "Auto-Backup to Telegram"
    print_line 4 "Restore Data" "Restore from .zip File"
    print_line 6 "Disable Bot" "Stop Cron Jobs" $C_RED
    
    print_category "DANGER ZONE"
    print_line 0 "Uninstall" "Remove All Components" $C_RED
    
    echo ""
    echo -e " ${C_GRAY}Press 9 to Exit${C_RESET}"
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
