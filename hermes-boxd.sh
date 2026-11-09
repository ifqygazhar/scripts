cat << 'EOF' > setup-hermes.sh
#!/usr/bin/env bash
set -e

echo "===================================================="
echo "🚀 Memulai Auto-Install & Konfigurasi Hermes (boxd)"
echo "===================================================="

# 1. Perbaiki masalah Git SSH -> HTTPS bawaan boxd
echo "[1/6] Memeriksa dan menghapus aturan redirect HTTPS Git..."
git config --global --unset url.https://github.com/.insteadof 2>/dev/null || true
git config --system --unset url.https://github.com/.insteadof 2>/dev/null || true

# 2. Pastikan PATH Hermes terdaftar di sesi ini dan permanen di ~/.bashrc
echo "[2/6] Mengatur environment PATH untuk Hermes..."
export PATH="$HOME/.local/bin:$HOME/.hermes/bin:$PATH"
PATH_LINE='export PATH="$HOME/.local/bin:$HOME/.hermes/bin:$PATH"'
grep -qxF "$PATH_LINE" ~/.bashrc || echo "$PATH_LINE" >> ~/.bashrc

# 3. Install Hermes jika belum terinstal
if ! command -v hermes &> /dev/null; then
    echo "[3/6] Hermes belum ditemukan. Mengunduh dan menginstal Hermes..."
    # Gunakan || true agar error user-scope gateway bawaan install.sh tidak menghentikan set -e
    curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash || true
    export PATH="$HOME/.local/bin:$HOME/.hermes/bin:$PATH"
else
    echo "[3/6] ✓ Hermes sudah terinstal di: $(which hermes)"
fi

# Pastikan biner hermes benar-benar sudah terpasang sebelum lanjut
if ! command -v hermes &> /dev/null; then
    echo "✗ Gagal mengunduh biner hermes."
    exit 1
fi

# 4. Matikan telemetry
echo "[4/6] Menonaktifkan shared telemetry..."
hermes setup telemetry off 2>/dev/null || true

# 5. Aktifkan systemd user manager untuk root
echo "[5/6] Menyalakan user@0.service untuk mendukung Cron & Kanban worker..."
loginctl enable-linger root 2>/dev/null || true
systemctl start user@0.service 2>/dev/null || true

# 6. Install & jalankan Hermes Gateway sebagai System Service
echo "[6/6] Menginstal dan menjalankan hermes-gateway (system-scope)..."
printf "y\ny\n" | hermes gateway install --system --run-as-user root

echo "===================================================="
echo "✅ Selesai! Status Hermes Gateway saat ini:"
echo "===================================================="
hermes gateway status --system || systemctl status hermes-gateway --no-pager
EOF
