#!/bin/bash

# =========================================================
#  WGDashboard Manager - Minimalist Pro Edition
# =========================================================

# --- Palette (Cyberpunk Theme) ---
C_RESET='\033[0m'
C_RED='\033[1;31m'
C_GREEN='\033[1;32m'
C_YELLOW='\033[1;33m'
C_BLUE='\033[1;34m'
C_PURPLE='\033[1;35m'
C_CYAN='\033[1;36m'
C_WHITE='\033[1;37m'
C_GRAY='\033[0;90m'

# --- Configuration ---
INSTALL_DIR="/opt/wgdashboard"
BACKUP_SCRIPT_PATH="/usr/local/bin/wgd-backup.sh"

# --- System Check ---
if [ "$EUID" -ne 0 ]; then
  echo -e "${C_RED}➜ Error: Must run as root.${C_RESET}"
  exit 1
fi

# --- Helper Functions ---

# Spinner Animation
spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# Dynamic Header
draw_header() {
    clear
    # Get System Info
    SERVER_IP=$(curl -s https://api.ipify.org || hostname -I | awk '{print $1}')
    UPTIME=$(uptime -p | sed 's/up //')
    RAM_USAGE=$(free -h | awk '/Mem:/ {print $3 "/" $2}')

    echo -e "${C_PURPLE}"
    echo "  _       __   ______     ____            __     "
    echo " | |     / /  / ____/    / __ \  ____    / /     "
    echo " | | /| / /  / / __     / / / / / __ \  / /      "
    echo " | |/ |/ /  / /_/ /    / /_/ / / /_/ / /_/       "
    echo " |__/|__/   \____/    /_____/  \____/ (_)        "
    echo -e "${C_RESET}"
    
    echo -e " ${C_GRAY}───────────────────────────────────────────────────${C_RESET}"
    echo -e " ${C_CYAN}SYSTEM STATUS${C_RESET}"
    echo -e " ${C_GRAY}➜ IP:${C_RESET} ${C_WHITE}$SERVER_IP${C_RESET}"
    echo -e " ${C_GRAY}➜ RAM:${C_RESET} ${C_WHITE}$RAM_USAGE${C_RESET}  ${C_GRAY}➜ Uptime:${C_RESET} ${C_WHITE}$UPTIME${C_RESET}"
    echo -e " ${C_GRAY}───────────────────────────────────────────────────${C_RESET}"
    echo ""
}

# Input Prompt Style
ask() {
    local prompt="$1"
    local default="$2"
    if [ -n "$default" ]; then
        echo -ne " ${C_PURPLE}➤${C_RESET} $prompt ${C_GRAY}($default)${C_RESET}: "
    else
        echo -ne " ${C_PURPLE}➤${C_RESET} $prompt: "
    fi
}

# Notification Styles
notify_success() { echo -e " ${C_GREEN}✔ $1${C_RESET}"; }
notify_info() { echo -e " ${C_BLUE}ℹ $1${C_RESET}"; }
notify_warn() { echo -e " ${C_YELLOW}⚠ $1${C_RESET}"; }
press_enter() { echo ""; read -p " Press [Enter] to continue..." dummy; }

# --- Core Modules ---

install_panel() {
    draw_header
    echo -e " ${C_WHITE}INSTALLATION WIZARD${C_RESET}"
    echo ""

    # Sysctl
    notify_info "Configuring Kernel..."
    if ! grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf; then
        echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    fi
    sysctl -w net.ipv4.ip_forward=1 > /dev/null 2>&1

    # Docker
    if ! command -v docker &> /dev/null; then
        notify_info "Installing Docker Engine..."
        (
            apt-get update -qq
            apt-get install -y -qq ca-certificates curl gnupg lsb-release
            mkdir -p /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
            apt-get update -qq
            apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin
        ) & spinner $!
        notify_success "Docker Installed."
    else
        notify_success "Docker is ready."
    fi

    echo ""
    echo -e " ${C_CYAN}CONFIGURATION${C_RESET}"
    
    SERVER_IP=$(curl -s https://api.ipify.org || echo "127.0.0.1")
    ask "Public IP" "$SERVER_IP"; read IP_IN; PUBLIC_IP=${IP_IN:-$SERVER_IP}
    ask "Username" "admin"; read USER_IN; WGD_USER=${USER_IN:-admin}
    ask "Password" ""; read -s WGD_PASS; echo ""
    if [ -z "$WGD_PASS" ]; then notify_warn "Password required!"; press_enter; return; fi
    ask "Panel Port" "10086"; read PORT_IN; WGD_PORT=${PORT_IN:-10086}
    ask "WireGuard Port" "51820"; read WG_IN; WG_PORT=${WG_IN:-51820}

    notify_info "Deploying Container..."
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
    
    # Firewall
    if command -v ufw &> /dev/null && ufw status | grep -q "active"; then
        ufw allow $WGD_PORT/tcp >/dev/null
        ufw allow $WG_PORT/udp >/dev/null
        notify_success "Firewall ports opened."
    fi

    echo ""
    notify_success "INSTALLED SUCCESSFULLY"
    echo -e " ${C_GRAY}➜ Panel URL:${C_RESET} http://${PUBLIC_IP}:${WGD_PORT}"
    press_enter
}

update_panel() {
    draw_header
    echo -e " ${C_WHITE}UPDATE MANAGER${C_RESET}"
    echo ""
    if [ ! -d "$INSTALL_DIR" ]; then notify_warn "Not installed."; press_enter; return; fi
    
    cd "$INSTALL_DIR"
    notify_info "Pulling latest update..."
    docker compose pull & spinner $!
    
    notify_info "Restarting services..."
    docker compose up -d & spinner $!
    
    docker image prune -f > /dev/null 2>&1
    notify_success "Updated to latest version."
    press_enter
}

setup_backup_bot() {
    draw_header
    echo -e " ${C_WHITE}TELEGRAM AUTO-BACKUP${C_RESET}"
    echo ""

    if ! docker volume ls -q | grep -q wgdashboard_conf; then
        notify_warn "Dashboard not found. Install it first."
        press_enter; return
    fi

    notify_info "Installing tools (zip, curl, cron)..."
    apt-get update -qq >/dev/null
    apt-get install -y -qq zip curl cron >/dev/null

    echo ""
    echo -e " ${C_CYAN}BOT CREDENTIALS${C_RESET}"
    ask "Bot Token" ""; read TG_TOKEN
    ask "Chat ID" ""; read TG_CHATID

    if [[ -z "$TG_TOKEN" || -z "$TG_CHATID" ]]; then
        notify_warn "Token and Chat ID are mandatory."
        press_enter; return
    fi

    echo ""
    echo -e " ${C_CYAN}CUSTOMIZATION${C_RESET}"
    echo -e " ${C_GRAY}Choose a name for this backup file (e.g., 'London-Server').${C_RESET}"
    echo -e " ${C_GRAY}Leave empty to use 'WGD-Backup'.${C_RESET}"
    ask "Backup Prefix Name" "WGD-Backup"; read PREFIX_IN
    
    # Use default if empty, sanitize input to remove spaces/special chars
    BACKUP_PREFIX=${PREFIX_IN:-WGD-Backup}
    BACKUP_PREFIX=$(echo "$BACKUP_PREFIX" | tr -dc '[:alnum:]-_')

    # Create Script
    cat <<EOF > "$BACKUP_SCRIPT_PATH"
#!/bin/bash
TOKEN="$TG_TOKEN"
CHAT_ID="$TG_CHATID"
SERVER_IP="\$(curl -s ifconfig.me)"
PREFIX="$BACKUP_PREFIX"
DATE="\$(date +'%Y-%m-%d_%H-%M')"

# Intelligent Naming
FILENAME="\${PREFIX}_\${SERVER_IP}_\${DATE}"
BACKUP_DIR="/tmp/\$FILENAME"
ZIP_FILE="/tmp/\$FILENAME.zip"

mkdir -p "\$BACKUP_DIR"
cp -r /var/lib/docker/volumes/wgdashboard_conf/_data "\$BACKUP_DIR/wireguard_config"
cp -r /var/lib/docker/volumes/wgdashboard_data/_data "\$BACKUP_DIR/dashboard_data"

cd /tmp
zip -r "\$ZIP_FILE" "\$FILENAME" >/dev/null 2>&1

CAPTION="📦 *Backup Notification*%0A🏷️ Name: \`\$PREFIX\`%0A🖥️ IP: \`\$SERVER_IP\`%0A📅 Time: \$(date +'%H:%M %Z')"

curl -s -F document=@"\$ZIP_FILE" "https://api.telegram.org/bot\$TOKEN/sendDocument?chat_id=\$CHAT_ID&caption=\$CAPTION&parse_mode=Markdown" >/dev/null

rm -rf "\$BACKUP_DIR" "\$ZIP_FILE"
EOF
    chmod +x "$BACKUP_SCRIPT_PATH"

    echo ""
    echo -e " ${C_CYAN}SCHEDULE${C_RESET}"
    echo -e " ${C_WHITE}1)${C_RESET} Every 30 Minutes"
    echo -e " ${C_WHITE}2)${C_RESET} Every 6 Hours"
    echo -e " ${C_WHITE}3)${C_RESET} Daily (Select Hour)"
    ask "Select Frequency" "3"; read FREQ
    
    case $FREQ in
        1) CRON="*/30 * * * *" ;;
        2) CRON="0 */6 * * * *" ;;
        3) ask "Hour (0-23)" "3"; read H; CRON="0 ${H:-3} * * *" ;;
        *) CRON="0 3 * * *" ;;
    esac

    (crontab -l 2>/dev/null | grep -v "$BACKUP_SCRIPT_PATH") | crontab -
    (crontab -l 2>/dev/null; echo "$CRON $BACKUP_SCRIPT_PATH") | crontab -

    notify_success "Bot configured successfully!"
    notify_info "Sending a test backup now..."
    bash "$BACKUP_SCRIPT_PATH" & spinner $!
    press_enter
}

uninstall_all() {
    echo ""
    notify_warn "DANGER ZONE: This will delete the panel and bot."
    ask "Type 'yes' to confirm" ""; read CONFIRM
    if [ "$CONFIRM" == "yes" ]; then
        if [ -d "$INSTALL_DIR" ]; then cd "$INSTALL_DIR"; docker compose down >/dev/null 2>&1; fi
        rm -rf "$INSTALL_DIR" "$BACKUP_SCRIPT_PATH"
        (crontab -l 2>/dev/null | grep -v "$BACKUP_SCRIPT_PATH") | crontab -
        notify_success "Uninstalled."
    fi
    press_enter
}

view_logs() {
    if [ -d "$INSTALL_DIR" ]; then
        cd "$INSTALL_DIR"
        clear
        echo -e "${C_CYAN}--- LIVE LOGS (Ctrl+C to Exit) ---${C_RESET}"
        docker compose logs -f --tail=20
    else
        notify_warn "Not installed."
    fi
}

# --- Main Menu Loop ---
while true; do
    draw_header
    
    # Menu Format: Option | Title | Description
    printf "  ${C_GREEN}1${C_RESET} ${C_GRAY}•${C_RESET} ${C_WHITE}%-18s${C_RESET} ${C_GRAY}---${C_RESET} ${C_GRAY}%s${C_RESET}\n" "Install Panel" "Setup Docker & WGDashboard"
    printf "  ${C_GREEN}2${C_RESET} ${C_GRAY}•${C_RESET} ${C_WHITE}%-18s${C_RESET} ${C_GRAY}---${C_RESET} ${C_GRAY}%s${C_RESET}\n" "Update Panel" "Get latest version (Safe)"
    printf "  ${C_GREEN}3${C_RESET} ${C_GRAY}•${C_RESET} ${C_WHITE}%-18s${C_RESET} ${C_GRAY}---${C_RESET} ${C_GRAY}%s${C_RESET}\n" "Backup Bot 🤖" "Configure Telegram Auto-Backup"
    printf "  ${C_GREEN}4${C_RESET} ${C_GRAY}•${C_RESET} ${C_WHITE}%-18s${C_RESET} ${C_GRAY}---${C_RESET} ${C_GRAY}%s${C_RESET}\n" "Live Logs" "View container logs"
    printf "  ${C_RED}0${C_RESET} ${C_GRAY}•${C_RESET} ${C_WHITE}%-18s${C_RESET} ${C_GRAY}---${C_RESET} ${C_GRAY}%s${C_RESET}\n" "Uninstall" "Remove everything"
    
    echo ""
    echo -e "  ${C_CYAN}9${C_RESET} ${C_GRAY}•${C_RESET} Exit"
    echo ""
    
    ask "Select Option" ""
    read OPTION

    case $OPTION in
        1) install_panel ;;
        2) update_panel ;;
        3) setup_backup_bot ;;
        4) view_logs ;;
        0) uninstall_all ;;
        9) clear; exit 0 ;;
        *) notify_warn "Invalid Option"; sleep 1 ;;
    esac
done
