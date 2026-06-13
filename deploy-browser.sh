#!/bin/bash

# Pastikan script dijalankan sebagai root
if [ "$EUID" -ne 0 ]; then
  echo "❌ Tolong jalankan script ini sebagai root (gunakan: sudo ./deploy-browser.sh)"
  exit
fi

echo "================================================"
echo "   🚀 VPS BROWSER DEPLOYMENT AUTOMATION 🚀"
echo "               (Versi Update)                   "
echo "================================================"

# 1. Cek & Install Docker
if ! command -v docker &> /dev/null; then
    echo "[INFO] Docker belum terinstall. Menginstall Docker sekarang..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    rm get-docker.sh
    echo "[INFO] Docker berhasil diinstall."
else
    echo "[INFO] Docker sudah terinstall."
fi

echo "------------------------------------------------"
# 2. Pilih Browser
echo "Pilih Browser yang ingin di-deploy:"
echo "1) Chromium (Rekomendasi)"
echo "2) Firefox"
read -p "Masukkan pilihan (1/2): " BROWSER_CHOICE

if [ "$BROWSER_CHOICE" == "1" ]; then
    IMAGE="lscr.io/linuxserver/chromium:latest"
    CONTAINER_NAME="vps-chromium"
    echo "[INFO] Anda memilih Chromium."
elif [ "$BROWSER_CHOICE" == "2" ]; then
    IMAGE="lscr.io/linuxserver/firefox:latest"
    CONTAINER_NAME="vps-firefox"
    echo "[INFO] Anda memilih Firefox."
else
    echo "❌ Pilihan tidak valid. Keluar."
    exit 1
fi

echo "------------------------------------------------"
# 3. Setup Limitasi Resource
read -p "Masukkan Limit RAM (Contoh: 4g, 8g, 12g) [Default: 8g]: " RAM_LIMIT
RAM_LIMIT=${RAM_LIMIT:-8g}

read -p "Masukkan Limit CPU Core (Contoh: 2, 4, 6) [Default: 4]: " CPU_LIMIT
CPU_LIMIT=${CPU_LIMIT:-4}

SHM_SIZE="2g"

echo "------------------------------------------------"
# 4. Custom Port
read -p "Masukkan Port HTTP yang ingin digunakan [Default: 3000]: " HTTP_PORT
HTTP_PORT=${HTTP_PORT:-3000}

read -p "Masukkan Port HTTPS yang ingin digunakan [Default: 3001]: " HTTPS_PORT
HTTPS_PORT=${HTTPS_PORT:-3001}

echo "------------------------------------------------"
# 5. Otomasi Firewall
echo "[INFO] Mengatur Firewall secara otomatis..."
if command -v ufw >/dev/null 2>&1; then
    echo "[INFO] UFW (Ubuntu/Debian) terdeteksi. Membuka port $HTTP_PORT dan $HTTPS_PORT..."
    ufw allow $HTTP_PORT/tcp >/dev/null 2>&1
    ufw allow $HTTPS_PORT/tcp >/dev/null 2>&1
    ufw reload >/dev/null 2>&1
elif command -v firewall-cmd >/dev/null 2>&1; then
    echo "[INFO] Firewalld (CentOS/AlmaLinux) terdeteksi. Membuka port $HTTP_PORT dan $HTTPS_PORT..."
    firewall-cmd --permanent --add-port=$HTTP_PORT/tcp >/dev/null 2>&1
    firewall-cmd --permanent --add-port=$HTTPS_PORT/tcp >/dev/null 2>&1
    firewall-cmd --reload >/dev/null 2>&1
else
    echo "[WARNING] Sistem firewall (UFW/Firewalld) tidak ditemukan. Melanjutkan tanpa setting firewall OS."
fi

echo "------------------------------------------------"
# 6. Deploy Container
echo "[INFO] Menghapus container lama (jika ada)..."
docker stop $CONTAINER_NAME 2>/dev/null
docker rm $CONTAINER_NAME 2>/dev/null

echo "[INFO] Mendeploy $CONTAINER_NAME..."
echo "- RAM Limit : $RAM_LIMIT"
echo "- CPU Limit : $CPU_LIMIT"
echo "- HTTP Port : $HTTP_PORT"
echo "- HTTPS Port: $HTTPS_PORT"

docker run -d \
  --name=$CONTAINER_NAME \
  --security-opt seccomp=unconfined \
  -e PUID=1000 \
  -e PGID=1000 \
  -e TZ=Asia/Jakarta \
  -p $HTTP_PORT:3000 \
  -p $HTTPS_PORT:3001 \
  --memory=$RAM_LIMIT \
  --cpus=$CPU_LIMIT \
  --shm-size=$SHM_SIZE \
  --restart unless-stopped \
  $IMAGE

IP_VPS=$(curl -s ifconfig.me)

echo "================================================"
echo " ✅ DEPLOYMENT SELESAI! ✅"
echo "================================================"
echo "🌐 Cara Mengakses:"
echo "Buka browser di laptop Anda dan kunjungi:"
echo "-> HTTP  : http://$IP_VPS:$HTTP_PORT"
echo "-> HTTPS : https://$IP_VPS:$HTTPS_PORT"
echo "================================================"
