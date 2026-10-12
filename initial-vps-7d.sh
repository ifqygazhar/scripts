#!/usr/bin/env bash

set -e

# Pastikan script dijalankan sebagai root
if [ "$EUID" -ne 0 ]; then
  echo "[-] Harap jalankan skrip ini sebagai root atau dengan sudo."
  exit 1
fi

echo "=========================================="
echo "    OPTIMASI UBUNTU 24.04 LTS (HEADLESS)  "
echo "=========================================="

# ----------------------------------------------------
# 1. UPDATE SISTEM
# ----------------------------------------------------
echo "[+] Memperbarui daftar paket sistem..."
apt update && apt upgrade -y

# ----------------------------------------------------
# 2. KONFIGURASI SWAP MEMORY (4 GB)
# ----------------------------------------------------
SWAP_PATH="/swapfile"
SWAP_SIZE="4G"

if [ -f "$SWAP_PATH" ]; then
    echo "[!] Swap file sudah ada di $SWAP_PATH, melewati pembuatan swap."
else
    echo "[+] Membuat Swap file sebesar $SWAP_SIZE..."
    fallocate -l "$SWAP_SIZE" "$SWAP_PATH" || dd if=/dev/zero of="$SWAP_PATH" bs=1M count=4096 status=progress
    chmod 600 "$SWAP_PATH"
    mkswap "$SWAP_PATH"
    swapon "$SWAP_PATH"
    
    # Simpan permanen ke fstab
    if ! grep -q "$SWAP_PATH" /etc/fstab; then
        echo "$SWAP_PATH none swap sw 0 0" >> /etc/fstab
    fi

    # Atur swappiness (nilai 20 ideal agar tidak terlalu agresif memakai disk SSD)
    sysctl vm.swappiness=20
    sysctl vm.vfs_cache_pressure=50
    sed -i '/vm.swappiness/d' /etc/sysctl.conf
    sed -i '/vm.vfs_cache_pressure/d' /etc/sysctl.conf
    echo "vm.swappiness=20" >> /etc/sysctl.conf
    echo "vm.vfs_cache_pressure=50" >> /etc/sysctl.conf
    echo "[+] Swap 4 GB berhasil dibuat dan diaktifkan."
fi

# ----------------------------------------------------
# 3. DEBLOAT & OPTIMASI RESOURCE
# ----------------------------------------------------
echo "[+] Menghapus layanan dan paket latar belakang yang memakan RAM..."

# Nonaktifkan dan hapus multipathd & unattended-upgrades jika tidak diperlukan
systemctl stop multipathd.service 2>/dev/null || true
systemctl disable multipathd.service 2>/dev/null || true

# Hapus snapd (Opsional tapi menghemat 150-300 MB RAM secara signifikan di server kecil)
read -p "Apakah Anda ingin menghapus Snapd untuk menghemat RAM ekstra? (y/N): " remove_snap
if [[ "$remove_snap" =~ ^[Yy]$ ]]; then
    echo "[+] Menghapus Snapd..."
    apt purge snapd -y || true
    rm -rf /root/snap /home/*/snap /var/cache/snapd/
fi

# Bersihkan paket apt yang tidak terpakai
echo "[+] Membersihkan cache dan paket yang tidak terpakai..."
apt autoremove --purge -y
apt clean

# ----------------------------------------------------
# 4. INSTALASI DEPENDENSI PENDUKUNG BROWSER
# ----------------------------------------------------
echo "[+] Memastikan dependensi dasar dan Git terpasang..."
apt install -y git curl wget unzip htop ca-certificates

# ----------------------------------------------------
# 5. GENERATE SSH KEY UNTUK GITHUB
# ----------------------------------------------------
echo "------------------------------------------"
read -p "Masukkan email Anda untuk akun GitHub: " github_email

# Tentukan direktori user asli jika dijalankan lewat sudo
TARGET_USER="${SUDO_USER:-$USER}"
USER_HOME=$(eval echo "~$TARGET_USER")
SSH_DIR="$USER_HOME/.ssh"
KEY_PATH="$SSH_DIR/id_ed25519"

mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"

if [ -f "$KEY_PATH" ]; then
    echo "[!] SSH Key sudah ada di $KEY_PATH."
else
    echo "[+] Membuat SSH key baru (ed25519)..."
    ssh-keygen -t ed25519 -C "$github_email" -f "$KEY_PATH" -N ""
    chown -R "$TARGET_USER:$TARGET_USER" "$SSH_DIR"
    echo "[+] SSH key berhasil dibuat."
fi

# ----------------------------------------------------
# SELESAI & VERIFIKASI
# ----------------------------------------------------
echo "=========================================="
echo "[✓] Optimasi selesai!"
echo "=========================================="
echo "Status Memori & Swap:"
free -h
echo "------------------------------------------"
echo "Salin Public Key berikut ke GitHub Settings -> SSH and GPG keys:"
echo ""
cat "${KEY_PATH}.pub"
echo ""
echo "=========================================="
