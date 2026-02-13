#!/bin/bash

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

# 1. نصب داکر و داکر کامپوز اگر نصب نباشند
echo -e "${GREEN}Step 1: Checking Docker installation...${NC}"
if ! command -v docker &> /dev/null; then
    echo "Docker not found. Installing Docker..."
    apt-get update
    apt-get install -y ca-certificates curl gnupg lsb-release
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
else
    echo "Docker is already installed."
fi

# 2. دریافت تنظیمات از کاربر
echo -e "${GREEN}Step 2: Configuration${NC}"

# تشخیص IP عمومی سرور به صورت خودکار با چند روش پشتیبان
echo "Detecting Public IP..."
AUTO_IP=$(curl -s https://api.ipify.org || curl -s https://ifconfig.me || curl -s https://icanhazip.com || echo "127.0.0.1")

# اعتبارسنجی IP (حذف خطاها یا رشته‌های طولانی غیر IP)
if [[ "$AUTO_IP" == *"error"* ]] || [[ ${#AUTO_IP} -gt 15 ]]; then
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

# ساخت فایل compose.yaml طبق مستندات ارائه شده
# نکته: فاصله‌ها در فایل یمل بسیار مهم هستند
cat <<EOF > compose.yaml
services:
  wgdashboard:
    image: ghcr.io/wgdashboard/wgdashboard:latest
    container_name: wgdashboard
    restart: unless-stopped
    ports:
      - ${WGD_PORT}:10086/tcp
      - ${WG_PORT}:${WG_PORT}/udp
    environment:
      - TZ=${TIMEZONE}
      - public_ip=${PUBLIC_IP}
      - username=${WGD_USER}
      - password=${WGD_PASS}
      - wgd_port=10086
      - global_dns=1.1.1.1
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
