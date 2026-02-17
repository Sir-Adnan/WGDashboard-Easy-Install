#!/bin/bash

# =========================================================
#  WGDashboard Manager - V15 (Remastered UI)
#  Author: UnknownZero
#  Fixes: IP Detection Bug, Color Rendering, New Logo
# =========================================================

# --- Safe Color Definitions (tput fallback) ---
if command -v tput >/dev/null 2>&1; then
    RED=$(tput setaf 1)
    GREEN=$(tput setaf 2)
    YELLOW=$(tput setaf 3)
    BLUE=$(tput setaf 4)
    MAGENTA=$(tput setaf 5)
    CYAN=$(tput setaf 6)
    WHITE=$(tput setaf 7)
    BOLD=$(tput bold)
    RESET=$(tput sgr0)
else
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    MAGENTA='\033[0;35m'
    CYAN='\033[0;36m'
    WHITE='\033[0;37m'
    BOLD='\033[1m'
    RESET='\033[0m'
fi

# --- Configuration ---
INSTALL_DIR="/opt/wgdashboard"
BACKUP_SCRIPT_PATH="/usr/local/bin/wgd-backup.sh"
PROJECT_NAME="wgdashboard"
VERSION="15.0"
AUTHOR="UnknownZero"

# --- Robust IP Detection Function ---
get_public_ip() {
    # Try source 1
    local ip=$(curl -s --max-time 2 https://api.ipify.org)
    if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then echo "$ip"; return; fi
    
    # Try source 2
    ip=$(curl -s --max-time 2 https://ipv4.icanhazip.com)
    if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then echo "$ip"; return; fi
    
    # Fallback
    echo "Unknown"
}

# --- UI Functions ---

draw_line() {
    printf "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"
}

center_text() {
    local text="$1"
    local color="$2"
    local width=70
    local padding=$(( (width - ${#text}) / 2 ))
    printf "%*s${color}%s${RESET}%*s\n" $padding "" "$text" $padding ""
}

header() {
    clear
    # New WG Logo
    echo -e "${CYAN}"
    cat << "EOF"
  _       __   ______     ____            __     
 | |     / /  / ____/    / __ \  ____    / /     
 | | /| / /  / / __     / / / / / __ \  / /      
 | |/ |/ /  / /_/ /    / /_/ / / /_/ / /_/       
 |__/|__/   \____/    /_____/  \____/ (_)        
                                                 
EOF
    echo -e "${RESET}"
    
    center_text "WGDashboard Manager v${VERSION}" "${BOLD}${WHITE}"
    center_text "By ${AUTHOR}" "${MAGENTA}"
    echo ""
    
    # System Info Gathering
    local sys_ip=$(get_public_ip)
    local sys_ram=$(free -h | awk '/Mem:/ {print $3 "/" $2}')
    local sys_uptime=$(uptime -p | sed 's/up //')
    
    # Status Box
    echo -e "${BLUE}┌─────────────────────[ ${BOLD}${WHITE}SYSTEM STATUS${BLUE} ]─────────────────────┐${RESET}"
    printf "${BLUE}│${RESET}  %-14s : %-35s  ${BLUE}│${RESET}\n" "${GRAY}Server IP${RESET}" "${WHITE}${sys_ip}${RESET}"
    printf "${BLUE}│${RESET}  %-14s : %-35s  ${BLUE}│${RESET}\n" "${GRAY}RAM Usage${RESET}" "${WHITE}${sys_ram}${RESET}"
    printf "${BLUE}│${RESET}  %-14s : %-35s  ${BLUE}│${RESET}\n" "${GRAY}Uptime${RESET}" "${WHITE}${sys_uptime}${RESET}"
    
    # App Status Logic
    if [ -d "$INSTALL_DIR" ]; then
        if docker compose -p "$PROJECT_NAME" ps | grep -q "Up"; then
             STATUS="${GREEN}● ONLINE${RESET}"
        else
             STATUS="${RED}● OFFLINE${RESET}"
        fi
        
        # Get Port safely
        local port=$(grep "wgd_port=" "$INSTALL_DIR/compose.yaml" 2>/dev/null | cut -d'=' -f2 | tr -d ' "')
        port=${port:-"????"}
        
        printf "${BLUE}│${RESET}  %-14s : %-35s  ${BLUE}│${RESET}\n" "${GRAY}Panel Status${RESET}" "${STATUS}"
        printf "${BLUE}│${RESET}  %-14s : %-35s  ${BLUE}│${RESET}\n" "${GRAY}Dashboard URL${RESET}" "http://${sys_ip}:${CYAN}${port}${RESET}"
        
        if [ -f "$BACKUP_SCRIPT_PATH" ]; then
             printf "${BLUE}│${RESET}  %-14s : %-35s  ${BLUE}│${RESET}\n" "${GRAY}Auto-Backup${RESET}" "${GREEN}Active${RESET}"
        else
             printf "${BLUE}│${RESET}  %-14s : %-35s  ${BLUE}│${RESET}\n" "${GRAY}Auto-Backup${RESET}" "${RED}Disabled${RESET}"
        fi
    else
        printf "${BLUE}│${RESET}  %-14s : %-35s  ${BLUE}│${RESET}\n" "${GRAY}Panel Status${RESET}" "${RED}NOT INSTALLED${RESET}"
    fi
    echo -e "${BLUE}└────────────────────────────────────────────────────────────┘${RESET}"
    echo ""
}

# --- Standardized Input/Output ---
print_info() { echo -e " ${BLUE}ℹ${RESET}  $1"; }
print_success() { echo -e " ${GREEN}✔${RESET}  $1"; }
print_error() { echo -e " ${RED}✖${RESET}  $1"; }
print_warn() { echo -e " ${YELLOW}⚠${RESET}  $1"; }

get_input() {
    local prompt="$1"
    local default="$2"
    if [ -n "$default" ]; then
        echo -ne " ${MAGENTA}➤${RESET} $prompt ${GRAY}[$default]${RESET}: "
    else
        echo -ne " ${MAGENTA}➤${RESET} $prompt: "
    fi
}

# --- Check Root ---
if [ "$EUID" -ne 0 ]; then print_error "Please run as root."; exit 1; fi

# --- Modules ---

install_panel() {
    header
    print_info "Starting Installation..."
    echo ""
    
    local detected_ip=$(get_public_ip)
    get_input "Public IP" "$detected_ip"; read IP_IN
    PUBLIC_IP=${IP_IN:-$detected_ip}
    
    get_input "Username" "admin"; read USER_IN
    WGD_USER=${USER_IN:-admin}
    
    while true; do
        get_input "Password"; read -s WGD_PASS; echo ""
        if [ -n "$WGD_PASS" ]; then break; fi
        print_error "Password is required."
    done
    
    get_input "Port" "10086"; read PORT_IN
    WGD_PORT=${PORT_IN:-10086}

    echo ""
    print_info "Configuring Environment..."
    if ! grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf; then echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf; fi
    sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1

    if ! docker compose version &>/dev/null; then
        print_warn "Installing Docker Engine..."
        apt-get update -qq >/dev/null 2>&1
        apt-get install -y -qq ca-certificates curl gnupg lsb-release >/dev/null 2>&1
        mkdir -p /etc/apt/keyrings
        curl -fsSL --max-time 10 https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list >/dev/null
        apt-get update -qq >/dev/null 2>&1
        apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin >/dev/null 2>&1
    fi

    print_info "Deploying Container..."
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

    print_success "Installation Complete!"
    read -p "Press Enter to continue..."
}

setup_backup_bot() {
    header
    print_info "Telegram Auto-Backup Setup"
    echo ""
    
    apt-get update -qq >/dev/null 2>&1; apt-get install -y -qq zip curl cron >/dev/null 2>&1

    get_input "Bot Token"; read TG_TOKEN
    get_input "Chat ID"; read TG_CHATID
    
    if [[ -z "$TG_TOKEN" || -z "$TG_CHATID" ]]; then
        print_error "Credentials missing."
        read -p "Enter..."
        return
    fi

    print_info "Testing Connection..."
    TEST=$(curl -s --max-time 10 -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" -d chat_id="${TG_CHATID}" -d text="🔌 Verified by UnknownZero Script")
    
    if [[ "$TEST" != *"\"ok\":true"* ]]; then
        print_error "Connection Failed! Check Token/ID."
        read -p "Enter..."
        return
    fi
    print_success "Verified!"

    echo ""
    get_input "Server Name" "WGD-Backup"; read PREFIX_IN
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

CAPTION="📦 *Backup Complete*%0A🏷 Name: ${PREFIX}%0A🖥 IP: ${SERVER_IP}%0A📅 Date: ${DATE}"
curl -s --max-time 45 -F chat_id="${CHAT_ID}" -F caption="${CAPTION}" -F document=@"${ZIP_FILE}" "https://api.telegram.org/bot${TOKEN}/sendDocument"
rm -rf "${TEMP_DIR}"
EOS
    
    echo ""
    print_info "Select Backup Frequency:"
    echo -e "   ${CYAN}1)${RESET} Every 30 Minutes"
    echo -e "   ${CYAN}2)${RESET} Every 6 Hours"
    echo -e "   ${CYAN}3)${RESET} Daily"
    get_input "Option"; read FREQ
    
    case $FREQ in
        1) CRON="*/30 * * * *" ;;
        2) CRON="0 */6 * * *" ;; 
        3) get_input "Hour (0-23)"; read H; CRON="0 ${H:-0} * * *" ;;
        *) CRON="0 3 * * *" ;;
    esac

    (crontab -l 2>/dev/null | grep -vF "$BACKUP_SCRIPT_PATH") | crontab -
    (crontab -l 2>/dev/null; echo "$CRON $BACKUP_SCRIPT_PATH") | crontab -
    
    print_success "Backup Scheduled! Sending test file..."
    bash "$BACKUP_SCRIPT_PATH"
    read -p "Press Enter to continue..."
}

restore_backup() {
    header
    print_warn "Restore Wizard (Overwrites Data)"
    echo ""
    
    mapfile -t BACKUPS < <(ls /root/*.zip 2>/dev/null)
    if [ ${#BACKUPS[@]} -eq 0 ]; then
        print_error "No .zip files found in /root/"
        read -p "Press Enter..."
        return
    fi

    echo -e "${GRAY}Available Backups:${RESET}"
    i=1
    for f in "${BACKUPS[@]}"; do
        echo -e " ${CYAN}$i)${RESET} $(basename "$f")"
        ((i++))
    done
    echo ""
    
    get_input "Select File #"; read CHOICE
    if [[ ! "$CHOICE" =~ ^[0-9]+$ ]] || [ "$CHOICE" -lt 1 ] || [ "$CHOICE" -gt "${#BACKUPS[@]}" ]; then
        print_error "Invalid selection."
        read -p "Enter..."
        return
    fi
    
    FILE_FULL_PATH="${BACKUPS[$((CHOICE-1))]}"
    
    echo ""
    get_input "Type 'restore' to confirm"; read CONFIRM
    if [ "$CONFIRM" == "restore" ]; then
        print_info "Restoring..."
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
        print_success "Restore Complete!"
    fi
    read -p "Press Enter..."
}

uninstall_all() {
    header
    print_warn "DANGER: Uninstalling Everything"
    get_input "Type 'yes' to confirm"; read CONFIRM
    if [ "$CONFIRM" == "yes" ]; then
        if [ -d "$INSTALL_DIR" ]; then cd "$INSTALL_DIR"; docker compose -p "$PROJECT_NAME" down >/dev/null 2>&1; fi
        rm -rf "$INSTALL_DIR" "$BACKUP_SCRIPT_PATH"
        (crontab -l 2>/dev/null | grep -vF "$BACKUP_SCRIPT_PATH") | crontab -
        
        echo ""
        get_input "Type 'delete' to wipe ALL VPN DATA"; read WIPE
        if [ "$WIPE" == "delete" ]; then
             docker volume rm ${PROJECT_NAME}_conf ${PROJECT_NAME}_data ${PROJECT_NAME}_aconf >/dev/null 2>&1
             docker volume rm wgdashboard_conf wgdashboard_data wgdashboard_aconf >/dev/null 2>&1
             print_success "Data Wiped."
        fi
        print_success "Uninstalled."
    fi
    read -p "Enter..."
}

remove_backup_only() {
    (crontab -l 2>/dev/null | grep -vF "$BACKUP_SCRIPT_PATH") | crontab -
    rm -f "$BACKUP_SCRIPT_PATH"
    print_success "Backup Disabled."
    read -p "Enter..."
}

update_panel() {
    if [ -d "$INSTALL_DIR" ]; then 
        cd "$INSTALL_DIR"
        print_info "Updating..."
        docker compose -p "$PROJECT_NAME" pull
        docker compose -p "$PROJECT_NAME" up -d
        docker image prune -f >/dev/null 2>&1
        print_success "Updated."
    else
        print_error "Not installed."
    fi
    read -p "Enter..."
}

view_logs() {
    if [ -d "$INSTALL_DIR" ]; then cd "$INSTALL_DIR"; docker compose -p "$PROJECT_NAME" logs -f --tail=50; else print_error "Not installed."; read -p "Enter..."; fi
}

# --- Main Menu Loop ---
while true; do
    header
    echo -e " ${BOLD}MAIN MENU:${RESET}"
    printf "  ${GREEN}%-2s${RESET} %-25s ${GRAY}%s${RESET}\n" "1" "Install Dashboard" "(Setup VPN Panel)"
    printf "  ${GREEN}%-2s${RESET} %-25s ${GRAY}%s${RESET}\n" "2" "Update Dashboard" "(Keep Data)"
    printf "  ${GREEN}%-2s${RESET} %-25s ${GRAY}%s${RESET}\n" "3" "Setup Backup Bot" "(Telegram Auto)"
    printf "  ${GREEN}%-2s${RESET} %-25s ${GRAY}%s${RESET}\n" "4" "Restore Backup" "(From .zip)"
    printf "  ${BLUE}%-2s${RESET} %-25s ${GRAY}%s${RESET}\n" "5" "View Logs" "(Debug)"
    printf "  ${RED}%-2s${RESET} %-25s ${GRAY}%s${RESET}\n" "6" "Disable Backup" "(Stop Cron)"
    printf "  ${RED}%-2s${RESET} %-25s ${GRAY}%s${RESET}\n" "0" "Uninstall" "(Delete All)"
    echo ""
    echo -e "  ${GRAY}9. Exit${RESET}"
    echo ""
    get_input "Option"; read OPTION
    
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
