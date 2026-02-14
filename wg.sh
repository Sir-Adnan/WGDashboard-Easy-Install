#!/bin/bash

# FIX: استفاده از تابع برای مدیریت قفل APT (مورد ۶)
wait_for_apt() {
  while fuser /var/lib/dpkg/lock >/dev/null 2>&1 || fuser /var/lib/apt/lists/lock >/dev/null 2>&1 || fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
    echo "Waiting for other package managers to finish..."
    sleep 3
  done
}

# FIX: اصلاح پایداری تنظیمات sysctl (مورد ۲)
# فقط اگر خط مربوطه وجود نداشت آن را اضافه می‌کند
echo "Enabling IP Forwarding..."
if ! grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf; then
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
fi
sysctl -w net.ipv4.ip_forward=1
sysctl -p

# رنگ‌ها برای نمایش بهتر خروجی
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== WGDashboard Auto-Installer for Ubuntu ===${NC}"

# بررسی دسترسی روت
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Please run as root (use sudo)${NC}"
  exit
fi

# 1. نصب داکر و داکر کامپوز
echo -e "${GREEN}Step 1: Checking Docker installation...${NC}"

# FIX: بررسی دقیق‌تر نصب بودن پلاگین docker compose (مورد ۳)
if ! docker compose version &> /dev/null; then
    echo "Docker Compose not found. Installing Docker..."
    
    # انتظار برای آزادسازی قفل APT
    wait_for_apt
    
    apt-get update
    apt-get install -y ca-certificates curl gnupg lsb-release
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    wait_for_apt
    apt-get update
    wait_for_apt
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
else
    echo "Docker and Docker Compose are already installed."
fi

# 2. دریافت تنظیمات از کاربر
echo -e "${GREEN}Step 2: Configuration${NC}"

# تشخیص IP عمومی سرور
echo "Detecting Public IP..."
AUTO_IP=$(curl -s https://api.ipify.org || curl -s https://ifconfig.me || curl -s https://icanhazip.com || echo "127.0.0.1")

# FIX: اعتبارسنجی دقیق IP با Regex (مورد ۴)
# اگر خروجی فرمت IPv4 استاندارد نباشد (مثل IPv6 یا ارور HTML)، مقدار پیش‌فرض خالی می‌شود
if [[ ! $AUTO_IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    AUTO_IP=""
fi

read -p "Enter Public IP (Default: $AUTO_IP): " PUBLIC_IP
PUBLIC_IP=${PUBLIC_IP:-$AUTO_IP}

read -p "Enter Dashboard Username (Default: admin): " WGD_USER
WGD_USER=${WGD_USER:-admin}

read -p "Enter Dashboard Password (Input hidden): " -s WGD_PASS
echo
if [ -z "$WGD_PASS" ]; then
    echo -e "${RED}Password cannot be empty!${NC}"
    exit 1
fi

read -p "Enter Dashboard Port (Default: 10086): " WGD_PORT
WGD_PORT=${WGD_PORT:-10086}

read -p "Enter WireGuard UDP Port (Default: 51820): " WG_PORT
WG_PORT=${WG_PORT:-51820}

# تنظیم منطقه زمانی
if [ -f /etc/timezone ]; then
    TIMEZONE=$(cat /etc/timezone)
else
    TIMEZONE="UTC"
fi

# 3. ایجاد دایرکتوری و فایل Docker Compose
echo -e "${GREEN}Step 3: Setting up WGDashboard directory and files...${NC}"
INSTALL_DIR="/opt/wgdashboard"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# ساخت فایل compose.yaml
cat <<EOF > compose.yaml
services:
  wgdashboard:
    image: ghcr.io/wgdashboard/wgdashboard:latest
    container_name: wgdashboard
    restart: unless-stopped
    # FIX: حفظ درخواست کاربر برای Host Network
    network_mode: host
    environment:
      - TZ=${TIMEZONE}
      - public_ip=${PUBLIC_IP}
      - username=${WGD_USER}
      - password=${WGD_PASS}
      # FIX: رفع باگ بحرانی عدم تطابق پورت‌ها (مورد ۱)
      # استفاده از متغیر ورودی کاربر به جای مقدار ثابت 10086
      - wgd_port=${WGD_PORT}
      - wg_port=${WG_PORT}
      - global_dns=1.1.1.1
    volumes:
      # FIX: حفظ والیوم درخواستی amnezia
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

echo "compose.yaml created successfully at $INSTALL_DIR"

# 4. تنظیم فایروال (اختیاری)
echo -e "${GREEN}Step 4: Checking Firewall (UFW)...${NC}"
if command -v ufw &> /dev/null && ufw status | grep -q "Status: active"; then
    echo "Opening port $WGD_PORT (TCP) and $WG_PORT (UDP)..."
    ufw allow $WGD_PORT/tcp
    ufw allow $WG_PORT/udp
    ufw reload
else
    echo "UFW is not active or not installed. Skipping firewall configuration."
fi

# 5. اجرای کانتینر
echo -e "${GREEN}Step 5: Starting WGDashboard...${NC}"
docker compose up -d

# 6. نمایش اطلاعات نهایی
echo -e "${BLUE}===============================================${NC}"
echo -e "${GREEN}Installation Complete!${NC}"
echo -e "Dashboard URL:   http://${PUBLIC_IP}:${WGD_PORT}"
echo -e "Username:        ${WGD_USER}"
echo -e "Password:        (hidden)"
echo -e "WireGuard Port:  ${WG_PORT}/udp"
echo -e "${BLUE}===============================================${NC}"
