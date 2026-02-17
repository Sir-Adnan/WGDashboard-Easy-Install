#!/bin/bash

# ==========================================
#  WGDashboard Ultimate Manager - Pro GUI
# ==========================================

# --- تنظیمات رنگ‌بندی (Palette) ---
# Bold Colors
B_RED='\033[1;31m'
B_GREEN='\033[1;32m'
B_YELLOW='\033[1;33m'
B_BLUE='\033[1;34m'
B_PURPLE='\033[1;35m'
B_CYAN='\033[1;36m'
B_WHITE='\033[1;37m'

# Regular Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
NC='\033[0m' # No Color

# --- متغیرهای سراسری ---
INSTALL_DIR="/opt/wgdashboard"
BACKUP_SCRIPT_PATH="/usr/local/bin/wgd-backup.sh"

# --- بررسی دسترسی روت ---
if [ "$EUID" -ne 0 ]; then
  echo -e "${B_RED}❌ Error: Please run this script as root!${NC}"
  echo -e "${GRAY}   Try: sudo bash $0${NC}"
  exit 1
fi

# --- توابع گرافیکی و کمکی ---

# هدر اصلی برنامه
draw_header() {
    clear
    echo -e "${B_PURPLE}"
    echo " __          __  _____   _____            _     _ board "
    echo " \ \        / / / ____| |  __ \          | |   | |      "
    echo "  \ \  /\  / / | |  __  | |  | | __ _ ___| |__ | |      "
    echo "   \ \/  \/ /  | | |_ | | |  | |/ _\` / __| '_ \| |      "
    echo "    \  /\  /   | |__| | | |__| | (_| \__ \ | | |_|      "
    echo "     \/  \/     \_____| |_____/ \__,_|___/_| |_(_)      "
    echo -e "${NC}"
    echo -e "${B_CYAN}   🚀 Ultimate Management Tool for WireGuard Dashboard${NC}"
    echo -e "${GRAY}   ===================================================${NC}"
    echo ""
}

# خط جداکننده
draw_line() {
    echo -e "${GRAY}-------------------------------------------------------${NC}"
}

# پیام موفقیت
msg_success() {
    echo -e "${B_GREEN}✔ SUCCESS:${NC} $1"
}

# پیام اطلاعات
msg_info() {
    echo -e "${B_BLUE}ℹ INFO:${NC} $1"
}

# پیام هشدار
msg_warn() {
    echo -e "${B_YELLOW}⚠ WARNING:${NC} $1"
}

# دریافت ورودی زیبا
ask_input() {
    local prompt="$1"
    local default="$2"
    if [ -n "$default" ]; then
        echo -ne "${B_PURPLE}➤ ${prompt} ${GRAY}[Default: ${default}]${NC}: "
    else
        echo -ne "${B_PURPLE}➤ ${prompt}${NC}: "
    fi
}

# مکث برای خواندن
pause() {
    echo ""
    read -p "Press [Enter] to return to menu..."
}

# تابع انتظار برای قفل APT
wait_for_apt() {
  msg_info "Checking system package manager locks..."
  while fuser /var/lib/dpkg/lock >/dev/null 2>&1 || fuser /var/lib/apt/lists/lock >/dev/null 2>&1 || fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
    echo -ne "."
    sleep 2
  done
  echo ""
}

# --- توابع عملیاتی ---

install_dashboard() {
    draw_header
    echo -e "${B_GREEN}🛠️  INSTALLATION WIZARD${NC}"
    draw_line
    echo -e "${GRAY}This process will install Docker, configure the firewall,${NC}"
    echo -e "${GRAY}and set up the WGDashboard container.${NC}"
    echo ""

    # Sysctl
    msg_info "Enabling IP Forwarding..."
    if ! grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf; then
        echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    fi
    sysctl -w net.ipv4.ip_forward=1 > /dev/null
    sysctl -p > /dev/null

    # Docker Check
    if ! command -v docker &> /dev/null; then
        msg_warn "Docker not found. Installing now..."
        wait_for_apt
        apt-get update -qq
        apt-get install -y -qq ca-certificates curl gnupg lsb-release > /dev/null
        mkdir -p /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
          $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
        wait_for_apt
        apt-get update -qq
        apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin > /dev/null
        msg_success "Docker installed successfully."
    else
        msg_success "Docker is already installed."
    fi

    echo ""
    echo -e "${B_CYAN}📝 Configuration Setup${NC}"
    
    # Auto IP
    AUTO_IP=$(curl -s https://api.ipify.org || echo "127.0.0.1")
    ask_input "Enter Public IP" "$AUTO_IP"
    read PUBLIC_IP
    PUBLIC_IP=${PUBLIC_IP:-$AUTO_IP}

    ask_input "Dashboard Username" "admin"
    read WGD_USER
    WGD_USER=${WGD_USER:-admin}

    ask_input "Dashboard Password" ""
    read -s WGD_PASS
    echo "" 
    if [ -z "$WGD_PASS" ]; then 
        echo -e "${B_RED}❌ Password cannot be empty!${NC}"
        pause
        return
    fi

    ask_input "Dashboard Port" "10086"
    read WGD_PORT
    WGD_PORT=${WGD_PORT:-10086}

    ask_input "WireGuard UDP Port" "51820"
    read WG_PORT
    WG_PORT=${WG_PORT:-51820}

    # Setup Directory
    msg_info "Creating directories..."
    mkdir -p "$INSTALL_DIR"
    cd "$INSTALL_DIR"

    # Create Compose
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

    # Firewall
    msg_info "Configuring Firewall (UFW)..."
    if command -v ufw &> /dev/null && ufw status | grep -q "Status: active"; then
        ufw allow $WGD_PORT/tcp > /dev/null
        ufw allow $WG_PORT/udp > /dev/null
        ufw reload > /dev/null
        msg_success "Ports $WGD_PORT (TCP) and $WG_PORT (UDP) opened."
    else
        msg_warn "UFW is inactive or missing. Skipping firewall."
    fi

    # Start
    msg_info "Starting Container..."
    docker compose up -d
    
    echo ""
    draw_line
    msg_success "INSTALLATION COMPLETE!"
    echo -e "${B_WHITE}   🌍 URL:${NC}  http://${PUBLIC_IP}:${WGD_PORT}"
    echo -e "${B_WHITE}   👤 User:${NC} ${WGD_USER}"
    echo -e "${B_WHITE}   🔑 Pass:${NC} (Hidden)"
    draw_line
    pause
}

update_dashboard() {
    draw_header
    echo -e "${B_BLUE}🔄 UPDATE WIZARD${NC}"
    draw_line
    echo -e "${GRAY}This will pull the latest version of WGDashboard.${NC}"
    echo -e "${GRAY}Your configurations and users will remain SAFE.${NC}"
    echo ""

    if [ ! -d "$INSTALL_DIR" ]; then
        echo -e "${B_RED}❌ Dashboard is not installed in $INSTALL_DIR${NC}"
        pause
        return
    fi
    
    cd "$INSTALL_DIR"
    msg_info "Pulling latest images..."
    docker compose pull
    
    msg_info "Restarting with new version..."
    docker compose up -d
    
    msg_info "Cleaning up old images..."
    docker image prune -f > /dev/null
    
    msg_success "Update finished successfully!"
    pause
}

install_backup_bot() {
    draw_header
    echo -e "${B_YELLOW}🤖 TELEGRAM AUTO-BACKUP${NC}"
    draw_line
    echo -e "${GRAY}This sets up a bot to zip your configs and send them to Telegram.${NC}"
    echo ""

    # Check Volumes
    if ! docker volume ls -q | grep -q wgdashboard_conf; then
        echo -e "${B_RED}❌ Error: WGDashboard volumes not found.${NC}"
        echo -e "${GRAY}   Please install the dashboard first (Option 1).${NC}"
        pause
        return
    fi

    # Install deps
    msg_info "Installing dependencies (zip, curl, cron)..."
    apt-get update -qq >/dev/null
    apt-get install -y -qq zip curl cron >/dev/null

    echo ""
    echo -e "${B_CYAN}📱 Telegram Bot Details${NC}"
    ask_input "Enter Bot Token (from @BotFather)" ""
    read TG_TOKEN
    ask_input "Enter Chat ID (from @userinfobot)" ""
    read TG_CHATID

    if [[ -z "$TG_TOKEN" || -z "$TG_CHATID" ]]; then
        echo -e "${B_RED}❌ Invalid input. Token and ID are required.${NC}"
        pause
        return
    fi

    # Create Script
    cat <<EOF > "$BACKUP_SCRIPT_PATH"
#!/bin/bash
TOKEN="$TG_TOKEN"
CHAT_ID="$TG_CHATID"
SERVER_IP="\$(curl -s ifconfig.me)"
DATE="\$(date +'%Y-%m-%d_%H-%M')"
BACKUP_DIR="/tmp/wgd_backup_\$DATE"
ZIP_FILE="/tmp/wgd_backup_\$DATE.zip"

mkdir -p "\$BACKUP_DIR"
# Copy Volumes
cp -r /var/lib/docker/volumes/wgdashboard_conf/_data "\$BACKUP_DIR/wireguard_config"
cp -r /var/lib/docker/volumes/wgdashboard_data/_data "\$BACKUP_DIR/dashboard_data"

cd /tmp
zip -r "\$ZIP_FILE" "wgd_backup_\$DATE" >/dev/null 2>&1

CAPTION="📦 *WGDashboard Backup*%0A📅 Date: \$DATE%0A🖥️ IP: \$SERVER_IP"
curl -s -F document=@"\$ZIP_FILE" "https://api.telegram.org/bot\$TOKEN/sendDocument?chat_id=\$CHAT_ID&caption=\$CAPTION&parse_mode=Markdown" >/dev/null

rm -rf "\$BACKUP_DIR" "\$ZIP_FILE"
EOF

    chmod +x "$BACKUP_SCRIPT_PATH"
    msg_success "Backup script created."

    # Cron Menu
    echo ""
    echo -e "${B_CYAN}⏰ Backup Frequency Setup${NC}"
    echo -e "   ${B_WHITE}1)${NC} ${CYAN}Minute-based${NC}  ${GRAY}(e.g., every 30 mins)${NC}"
    echo -e "   ${B_WHITE}2)${NC} ${CYAN}Hourly-based${NC}  ${GRAY}(e.g., every 6 hours)${NC}"
    echo -e "   ${B_WHITE}3)${NC} ${CYAN}Daily-based${NC}   ${GRAY}(e.g., once a day)${NC}"
    echo ""
    ask_input "Select Frequency [1-3]" "3"
    read FREQ
    
    CRON_CMD=""
    case $FREQ in
        1) 
            ask_input "Enter interval in minutes" "30"
            read M
            CRON_CMD="*/$M * * * *" 
            ;;
        2) 
            ask_input "Enter interval in hours" "6"
            read H
            CRON_CMD="0 */$H * * * *" 
            ;;
        3) 
            ask_input "Enter hour of day (0-23)" "3"
            read D
            CRON_CMD="0 $D * * *" 
            ;;
        *) 
            msg_warn "Invalid choice. Defaulting to Daily at 03:00 AM"
            CRON_CMD="0 3 * * *" 
            ;;
    esac

    # Update Crontab
    (crontab -l 2>/dev/null | grep -v "$BACKUP_SCRIPT_PATH") | crontab -
    (crontab -l 2>/dev/null; echo "$CRON_CMD $BACKUP_SCRIPT_PATH") | crontab -
    
    msg_success "Auto-Backup scheduled!"
    msg_info "Sending a test backup now..."
    bash "$BACKUP_SCRIPT_PATH"
    pause
}

uninstall_all() {
    draw_header
    echo -e "${B_RED}💀 UNINSTALLATION ZONE${NC}"
    draw_line
    echo -e "${B_RED}WARNING: This will delete:${NC}"
    echo -e "  - The Dashboard Container"
    echo -e "  - The Backup Bot & Scripts"
    echo -e "  - (Optional) All VPN Users & Configs"
    echo ""
    ask_input "Type 'yes' to confirm deletion" ""
    read CONFIRM
    
    if [ "$CONFIRM" == "yes" ]; then
        msg_info "Stopping containers..."
        if [ -d "$INSTALL_DIR" ]; then
            cd "$INSTALL_DIR"
            docker compose down >/dev/null 2>&1
        fi
        
        msg_info "Removing installation files..."
        rm -rf "$INSTALL_DIR"
        rm -f "$BACKUP_SCRIPT_PATH"
        
        msg_info "Cleaning up Cron jobs..."
        (crontab -l 2>/dev/null | grep -v "$BACKUP_SCRIPT_PATH") | crontab -
        
        echo ""
        ask_input "Delete Database & VPN Configs? (y/n)" "n"
        read DEL_VOL
        if [[ "$DEL_VOL" =~ ^[Yy]$ ]]; then
            docker volume rm wgdashboard_aconf wgdashboard_conf wgdashboard_data 2>/dev/null
            msg_success "Volumes removed."
        else
            msg_info "Volumes (data) kept safe."
        fi
        
        msg_success "Uninstalled successfully."
    else
        msg_warn "Uninstall cancelled."
    fi
    pause
}

view_logs() {
    draw_header
    echo -e "${B_BLUE}📄 LIVE LOGS${NC}"
    draw_line
    echo -e "${GRAY}Press ${B_RED}Ctrl+C${GRAY} to exit logs and return to terminal.${NC}"
    echo ""
    sleep 2
    if [ -d "$INSTALL_DIR" ]; then
        cd "$INSTALL_DIR"
        docker compose logs -f --tail=50
    else
        echo -e "${B_RED}❌ Not installed.${NC}"
        pause
    fi
}

# --- حلقه اصلی منو ---
while true; do
    draw_header
    
    # منو با توضیحات
    echo -e "  ${B_GREEN}1.${NC} ${B_WHITE}Install Dashboard${NC}"
    echo -e "     ${GRAY}↳ Install Docker, Setup Panel & Firewall${NC}"
    
    echo -e "  ${B_GREEN}2.${NC} ${B_WHITE}Update Dashboard${NC}"
    echo -e "     ${GRAY}↳ Pull latest version (Data is safe)${NC}"
    
    echo -e "  ${B_GREEN}3.${NC} ${B_WHITE}Setup Backup Bot${NC} ${B_YELLOW}🤖${NC}"
    echo -e "     ${GRAY}↳ Auto-send Configs/DB to Telegram (Cron)${NC}"
    
    echo -e "  ${B_GREEN}4.${NC} ${B_WHITE}View Logs${NC}"
    echo -e "     ${GRAY}↳ Debug issues & view container logs${NC}"
    
    echo -e "  ${B_RED}0.${NC} ${B_RED}Uninstall Everything${NC}"
    echo -e "     ${GRAY}↳ Remove Panel, Bot & Data${NC}"
    
    draw_line
    echo -e "  ${B_CYAN}9.${NC} ${B_CYAN}Exit Menu${NC}"
    echo ""
    
    ask_input "Select Option" ""
    read OPTION

    case $OPTION in
        1) install_dashboard ;;
        2) update_dashboard ;;
        3) install_backup_bot ;;
        4) view_logs ;;
        0) uninstall_all ;;
        9) echo -e "${B_PURPLE}Bye! 👋${NC}"; exit 0 ;;
        *) echo -e "${B_RED}❌ Invalid option.${NC}"; sleep 1 ;;
    esac
done
