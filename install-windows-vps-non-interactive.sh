#!/bin/bash
# ==================================================
# install-windows-rdp-auto.sh
# Versi NON-INTERAKTIF - semua konfigurasi via flags.
# Aman dijalankan via: SSH exec, nohup, atau curl | bash -s --
# Hanya untuk Ubuntu 22.04
# ==================================================
set -euo pipefail

# ---------- Default values ----------
WIN_VERSION="11"
DISK_SIZE="64G"
WIN_USER="Docker"
WIN_PASS="admin"
RDP_PORT="3389"
WEB_PORT="8006"
WEB_MODE="1"          # 1=web aktif terus, 2=nonaktif, 3=auto-disable setelah install
FORCE_KVM="no"        # yes = lanjut walau /dev/kvm tidak ada
FORCE_DISK="no"       # yes = lanjut walau melebihi batas disk yang disarankan
SKIP_UPGRADE="no"     # yes = skip apt upgrade (lebih cepat)
INSTALL_DIR="$HOME/windows-rdp"

usage() {
    cat <<'USAGE'
Pemakaian:
  sudo bash install-windows-rdp-auto.sh [opsi]

Opsi:
  --version <kode>     Versi Windows (default: 11)
                       Umum: 11, 11l, 10, 10l, 8e, 7u, xp, 2025, 2022, 2019
  --disk <ukuran>      Ukuran disk Windows, format NNG (default: 64G)
  --user <username>    Username Windows (default: Docker)
  --pass <password>    Password Windows (default: admin)
                       Tidak boleh mengandung spasi, kutip, backslash, atau $
  --rdp-port <port>    Port RDP di host (default: 3389)
  --web-port <port>    Port web viewer di host (default: 8006)
  --web-mode <1|2|3>   1 = web aktif terus (default)
                       2 = web nonaktif total
                       3 = web aktif saat install, otomatis mati setelah RDP siap
  --dir <path>         Folder instalasi (default: ~/windows-rdp)
  --force-kvm          Lanjut walau KVM tidak terdeteksi (TIDAK disarankan)
  --force-disk         Lanjut walau ukuran disk melebihi batas yang disarankan
  --skip-upgrade       Skip 'apt upgrade' agar lebih cepat
  --help               Tampilkan bantuan ini

Contoh:
  sudo bash install-windows-rdp-auto.sh --version 10 --disk 80G \
    --user Admin --pass Rahasia123 --rdp-port 3390 --web-mode 3
USAGE
    exit 0
}

fail() { echo "[ERROR] $1" >&2; exit "${2:-1}"; }

# ---------- Parse arguments ----------
while [ $# -gt 0 ]; do
    case "$1" in
        --version)      WIN_VERSION="${2:-}"; shift 2 ;;
        --disk)         DISK_SIZE="${2:-}"; shift 2 ;;
        --user)         WIN_USER="${2:-}"; shift 2 ;;
        --pass)         WIN_PASS="${2:-}"; shift 2 ;;
        --rdp-port)     RDP_PORT="${2:-}"; shift 2 ;;
        --web-port)     WEB_PORT="${2:-}"; shift 2 ;;
        --web-mode)     WEB_MODE="${2:-}"; shift 2 ;;
        --dir)          INSTALL_DIR="${2:-}"; shift 2 ;;
        --force-kvm)    FORCE_KVM="yes"; shift ;;
        --force-disk)   FORCE_DISK="yes"; shift ;;
        --skip-upgrade) SKIP_UPGRADE="yes"; shift ;;
        --help|-h)      usage ;;
        *)              fail "Opsi tidak dikenal: $1 (lihat --help)" 2 ;;
    esac
done

echo "=================================================="
echo "  Windows RDP Auto-Installer (Non-Interaktif)     "
echo "=================================================="

# ---------- [STEP 1/8] Validasi OS: hanya Ubuntu 22.04 ----------
echo "[STEP 1/8] Cek OS..."
[ -r /etc/os-release ] || fail "/etc/os-release tidak ditemukan, OS tidak bisa dideteksi." 10
. /etc/os-release
if [ "${ID:-}" != "ubuntu" ] || [[ "${VERSION_ID:-}" != 22.* ]]; then
    fail "Script ini hanya mendukung Ubuntu 22.04. Terdeteksi: ${PRETTY_NAME:-tidak diketahui}" 10
fi
echo "[OK] OS: $PRETTY_NAME"

# Deteksi root / sudo
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    command -v sudo >/dev/null 2>&1 || fail "Bukan root dan sudo tidak tersedia." 11
    SUDO="sudo -n"
    $SUDO true 2>/dev/null || fail "sudo butuh password (non-interaktif). Jalankan sebagai root." 11
fi

# ---------- [STEP 2/8] Validasi input ----------
echo "[STEP 2/8] Validasi input..."

# Format disk
[[ "$DISK_SIZE" =~ ^[0-9]+G$ ]] || fail "Format --disk salah: '$DISK_SIZE'. Contoh benar: 64G" 20
DISK_NUM=${DISK_SIZE%G}

# Password: karakter yang bisa merusak YAML/shell
case "$WIN_PASS" in
    *\"*|*\'*|*\\*|*\$*|*\ *|*$'\t'*)
        fail "Password tidak boleh mengandung spasi, kutip, backslash, atau \$." 21 ;;
esac
[ -n "$WIN_USER" ] || fail "Username tidak boleh kosong." 21

# Port
for p in "$RDP_PORT" "$WEB_PORT"; do
    [[ "$p" =~ ^[0-9]+$ ]] && [ "$p" -ge 1 ] && [ "$p" -le 65535 ] \
        || fail "Port tidak valid: '$p' (harus 1-65535)." 22
done
[ "$RDP_PORT" != "$WEB_PORT" ] || fail "Port RDP dan port web tidak boleh sama." 22
ss -tuln | grep -q ":${RDP_PORT} " && fail "Port RDP $RDP_PORT sudah dipakai aplikasi lain." 22
if [ "$WEB_MODE" != "2" ]; then
    ss -tuln | grep -q ":${WEB_PORT} " && fail "Port web $WEB_PORT sudah dipakai aplikasi lain." 22
fi

# Web mode
[[ "$WEB_MODE" =~ ^[123]$ ]] || fail "--web-mode harus 1, 2, atau 3." 23
echo "[OK] Semua input valid."

# ---------- [STEP 3/8] Deteksi disk ----------
echo "[STEP 3/8] Cek kapasitas disk..."
DISK_TOTAL_GB=$(df -BG --output=size / | tail -1 | tr -dc '0-9')
DISK_AVAIL_GB=$(df -BG --output=avail / | tail -1 | tr -dc '0-9')
if [ "$DISK_AVAIL_GB" -gt 15 ]; then
    DISK_SUGGEST=$(( DISK_AVAIL_GB - 10 ))
else
    DISK_SUGGEST=0
fi
echo "[INFO] Total disk: ${DISK_TOTAL_GB}GB | Tersedia: ${DISK_AVAIL_GB}GB | Maks disarankan: ${DISK_SUGGEST}GB"

[ "$DISK_SUGGEST" -gt 0 ] || fail "Sisa disk terlalu kecil (${DISK_AVAIL_GB}GB). Minimal butuh ~20GB kosong." 30
if [ "$DISK_NUM" -gt "$DISK_AVAIL_GB" ]; then
    fail "Alokasi ${DISK_SIZE} melebihi sisa disk (${DISK_AVAIL_GB}GB)." 30
fi
if [ "$DISK_NUM" -gt "$DISK_SUGGEST" ]; then
    if [ "$FORCE_DISK" = "yes" ]; then
        echo "[WARNING] ${DISK_SIZE} melebihi batas disarankan (${DISK_SUGGEST}G), lanjut karena --force-disk."
    else
        fail "${DISK_SIZE} melebihi batas disarankan (${DISK_SUGGEST}G). Gunakan --force-disk untuk memaksa." 31
    fi
fi
echo "[OK] Alokasi disk ${DISK_SIZE} aman."

# ---------- [STEP 4/8] Update sistem & dependensi ----------
echo "[STEP 4/8] Install dependensi..."
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a   # cegah dialog needrestart di Ubuntu 22
$SUDO apt-get update -y
if [ "$SKIP_UPGRADE" != "yes" ]; then
    $SUDO apt-get upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
fi
$SUDO apt-get install -y curl cpu-checker

# ---------- [STEP 5/8] Cek KVM ----------
echo "[STEP 5/8] Cek KVM..."
if [ -e /dev/kvm ]; then
    echo "[OK] /dev/kvm ditemukan. Akselerasi KVM aktif."
else
    if [ "$FORCE_KVM" = "yes" ]; then
        echo "[WARNING] /dev/kvm tidak ada, lanjut karena --force-kvm. Windows bisa SANGAT lambat."
    else
        fail "/dev/kvm tidak ditemukan. VPS harus mendukung KVM/nested virtualization. Gunakan --force-kvm untuk memaksa." 50
    fi
fi

# ---------- [STEP 6/8] Install Docker ----------
echo "[STEP 6/8] Install Docker..."
if command -v docker >/dev/null 2>&1; then
    echo "[OK] Docker sudah terinstall, skip."
else
    curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
    $SUDO sh /tmp/get-docker.sh
    rm -f /tmp/get-docker.sh
fi
$SUDO systemctl enable --now docker

# ---------- [STEP 7/8] Konfigurasi & jalankan container ----------
echo "[STEP 7/8] Menyiapkan container Windows..."
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

if [ -d "./storage" ] && [ -n "$(ls -A ./storage 2>/dev/null)" ]; then
    echo "[WARNING] Folder storage lama ditemukan di ${INSTALL_DIR}/storage."
    echo "[WARNING] Username/password baru TIDAK akan diterapkan (Windows sudah pernah terinstall)."
fi

PORTS_YAML="      - \"${RDP_PORT}:3389/tcp\"
      - \"${RDP_PORT}:3389/udp\""
if [ "$WEB_MODE" != "2" ]; then
    PORTS_YAML="      - \"${WEB_PORT}:8006\"
${PORTS_YAML}"
fi

cat > docker-compose.yml <<EOF
services:
  windows:
    image: dockurr/windows
    container_name: windows
    environment:
      VERSION: "${WIN_VERSION}"
      DISK_SIZE: "${DISK_SIZE}"
      USERNAME: "${WIN_USER}"
      PASSWORD: "${WIN_PASS}"
    devices:
      - /dev/kvm
      - /dev/net/tun
    cap_add:
      - NET_ADMIN
    ports:
${PORTS_YAML}
    volumes:
      - ./storage:/storage
    restart: always
    stop_grace_period: 2m
EOF

$SUDO docker compose up -d

# ---------- [STEP 8/8] Watcher untuk web-mode 3 ----------
if [ "$WEB_MODE" = "3" ]; then
    echo "[STEP 8/8] Menyiapkan auto-disable akses web..."
    cat > auto-disable-web.sh <<'WEOF'
#!/bin/bash
cd "$(dirname "$0")"
echo "$(date) - [WATCHER] Menunggu instalasi Windows selesai (deteksi service RDP)..."
OK=0
# Cek tiap 30 detik, maksimal ~6 jam
for i in $(seq 1 720); do
    if docker exec windows bash -c 'timeout 3 bash -c "</dev/tcp/20.20.20.21/3389"' 2>/dev/null; then
        OK=$((OK+1))
    else
        OK=0
    fi
    if [ "$OK" -ge 3 ]; then
        echo "$(date) - [WATCHER] RDP terdeteksi aktif. Windows sudah siap."
        break
    fi
    sleep 30
done
if [ "$OK" -lt 3 ]; then
    echo "$(date) - [WATCHER] TIMEOUT: RDP tidak terdeteksi dalam 6 jam. Akses web TIDAK dimatikan."
    exit 1
fi
sleep 60
echo "$(date) - [WATCHER] Menonaktifkan akses web browser..."
sed -i '/:8006"/d' docker-compose.yml
docker compose up -d
echo "$(date) - [WATCHER] SELESAI. Akses web sudah dimatikan, gunakan RDP."
WEOF
    chmod +x auto-disable-web.sh
    $SUDO nohup ./auto-disable-web.sh > auto-disable-web.log 2>&1 &
    echo "[OK] Watcher jalan di background. Log: ${INSTALL_DIR}/auto-disable-web.log"
else
    echo "[STEP 8/8] Tidak ada watcher (web-mode ${WEB_MODE})."
fi

# ---------- Ringkasan (machine-readable) ----------
PUBLIC_IP=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || echo "UNKNOWN")
echo "=================================================="
echo "                 PROSES SELESAI!                  "
echo "=================================================="
echo "Windows '${WIN_VERSION}' (disk ${DISK_SIZE}) sedang diinstall otomatis oleh container."
echo "Proses install Windows sendiri butuh 10-30 menit tergantung kecepatan VPS."
echo ""
echo "===== RESULT ====="
echo "RESULT_STATUS=started"
echo "RESULT_IP=${PUBLIC_IP}"
echo "RESULT_RDP_PORT=${RDP_PORT}"
echo "RESULT_RDP_USER=${WIN_USER}"
echo "RESULT_WEB_MODE=${WEB_MODE}"
if [ "$WEB_MODE" != "2" ]; then
    echo "RESULT_WEB_URL=http://${PUBLIC_IP}:${WEB_PORT}"
fi
echo "RESULT_INSTALL_DIR=${INSTALL_DIR}"
echo "=================="
