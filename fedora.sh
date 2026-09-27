#!/usr/bin/env bash
# ============================================================
#  Fedora KDE — All-in-One Setup (gaming + komunikasi + dev)
#  Aman dijalankan berulang kali: jika koneksi putus, jalankan
#  lagi dan proses melanjutkan dari yang belum selesai.
#    bash fedora-setup.sh
# ============================================================
set -uo pipefail

retry() { local n=0; until "$@"; do n=$((n+1)); [ $n -ge 5 ] && return 1; echo "   ...gagal, coba lagi ($n/5) dalam 10 detik"; sleep 10; done; }
dnf_in() { retry sudo dnf install -y --skip-unavailable "$@" 2>/dev/null || retry sudo dnf install -y --skip-broken "$@"; }
fp_in()  { retry flatpak install -y --noninteractive flathub "$@"; }

echo "==> [1/8] Update sistem + RPM Fusion + Flathub"
retry sudo dnf upgrade --refresh -y
FV=$(rpm -E %fedora)
dnf_in "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FV}.noarch.rpm" \
       "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FV}.noarch.rpm"
sudo dnf config-manager setopt rpmfusion-nonfree-steam.enabled=1 2>/dev/null \
  || sudo dnf config-manager --enable rpmfusion-nonfree-steam 2>/dev/null || true
retry flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
# Repo resmi VS Code (Microsoft)
if [ ! -f /etc/yum.repos.d/vscode.repo ]; then
  sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
  printf '[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\nautorefresh=1\ntype=rpm-md\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc\n' | sudo tee /etc/yum.repos.d/vscode.repo >/dev/null
fi
# Repo resmi Brave Browser
if [ ! -f /etc/yum.repos.d/brave-browser.repo ]; then
  sudo dnf config-manager addrepo --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo 2>/dev/null \
    || sudo dnf config-manager --add-repo https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo || true
fi

echo "==> [2/8] Driver grafis"
dnf_in mesa-vulkan-drivers.i686 mesa-va-drivers.i686 mesa-dri-drivers.i686
if lspci | grep -qi nvidia; then
  echo "   NVIDIA terdeteksi -> memasang akmod-nvidia (tunggu ±10 menit sebelum reboot)"
  dnf_in akmod-nvidia xorg-x11-drv-nvidia-cuda
fi

echo "==> [3/8] Paket DNF: OBS, Waydroid, Steam, Lutris, Wine, GameMode, MangoHud, PHP, Java, Go, Node.js, Podman, MariaDB, PostgreSQL, Brave, VS Code, Neovim, utilitas"
dnf_in obs-studio waydroid \
       steam lutris wine winetricks gamemode mangohud \
       php php-cli php-common php-mbstring php-xml php-curl php-zip php-json php-mysqlnd php-pgsql \
       java-21-openjdk-devel golang \
       brave-browser code neovim nodejs npm \
       python3 python3-pip python3-virtualenv \
       podman podman-compose podman-docker \
       mariadb mariadb-server \
       postgresql postgresql-server postgresql-contrib \
       git wget curl unzip zip tar xz

echo "==> [4/8] Flatpak: Vesktop, ZapZap (WhatsApp), Zoom, ProtonUp-Qt, Heroic, Spotify"
fp_in dev.vencord.Vesktop com.rtosta.zapzap us.zoom.Zoom \
      net.davidotek.pupgui2 com.heroicgameslauncher.hgl com.spotify.Client

echo "==> [5/8] SDKMAN, Bun, FVM"
export SDKMAN_DIR="$HOME/.sdkman"
[ -d "$SDKMAN_DIR" ] || retry bash -c 'curl -s https://get.sdkman.io | bash'
[ -d "$HOME/.bun" ]  || retry bash -c 'curl -fsSL https://bun.sh/install | bash'
command -v fvm >/dev/null 2>&1 || [ -x "$HOME/.fvm_flutter/bin/fvm" ] \
  || retry bash -c 'curl -fsSL https://fvm.app/install.sh | bash'
export PATH="$HOME/.fvm_flutter/bin:$PATH"
FLUTTER_VER="3.41.6"
if [ ! -d "$HOME/fvm/versions/$FLUTTER_VER" ]; then
  retry fvm install "$FLUTTER_VER"
fi
fvm global "$FLUTTER_VER" || true

echo "==> Zed editor"
[ -x "$HOME/.local/bin/zed" ] || retry bash -c 'curl -f https://zed.dev/install.sh | sh'

echo "==> AI agent CLI: Claude Code, Antigravity CLI, GitHub Copilot CLI, Pi"
# npm global tanpa sudo -> ~/.npm-global
npm config set prefix "$HOME/.npm-global"
export PATH="$HOME/.npm-global/bin:$HOME/.local/bin:$PATH"
# Claude Code (native installer, tanpa Node.js)
[ -x "$HOME/.local/bin/claude" ] || retry bash -c 'curl -fsSL https://claude.ai/install.sh | bash'
# Antigravity CLI (Google) -> perintah: agy
[ -x "$HOME/.local/bin/agy" ] || retry bash -c 'curl -fsSL https://antigravity.google/cli/install.sh | bash'
# GitHub Copilot CLI
command -v copilot >/dev/null 2>&1 || retry npm install -g @github/copilot
# Pi coding agent (scope baru @earendil-works; fallback ke @mariozechner jika belum tersedia)
command -v pi >/dev/null 2>&1 \
  || retry npm install -g @earendil-works/pi-coding-agent \
  || retry npm install -g @mariozechner/pi-coding-agent

echo "==> Camoufox (anti-detect Firefox untuk Playwright) di venv Python"
if [ ! -x "$HOME/.venvs/camoufox/bin/python" ]; then
  mkdir -p "$HOME/.venvs" && python3 -m venv "$HOME/.venvs/camoufox"
fi
retry "$HOME/.venvs/camoufox/bin/pip" install -U "camoufox[geoip]"
retry "$HOME/.venvs/camoufox/bin/python" -m camoufox fetch

echo "==> [6/8] Dart SDK (standalone)"
mkdir -p ~/.local/opt ~/.local/bin
if [ ! -d "$HOME/.local/opt/dart-sdk" ]; then
  retry wget -c "https://storage.googleapis.com/dart-archive/channels/stable/release/latest/sdk/dartsdk-linux-x64-release.zip" -O /tmp/dartsdk.zip
  unzip -q -o /tmp/dartsdk.zip -d ~/.local/opt/ && rm -f /tmp/dartsdk.zip
fi

echo "==> [7/8] Android SDK headless (cmdline-tools, tanpa Android Studio)"
export ANDROID_HOME="$HOME/Android/Sdk"
mkdir -p "$ANDROID_HOME/cmdline-tools"
if [ ! -d "$ANDROID_HOME/cmdline-tools/latest" ]; then
  # Ambil nama file terbaru dari halaman resmi; fallback ke build yang diketahui
  CLT=$(curl -fsSL https://developer.android.com/studio 2>/dev/null | grep -oE 'commandlinetools-linux-[0-9]+_latest\.zip' | head -1)
  [ -n "$CLT" ] || CLT="commandlinetools-linux-13114758_latest.zip"
  retry wget -c "https://dl.google.com/android/repository/${CLT}" -O /tmp/cmdline-tools.zip
  rm -rf /tmp/clt && mkdir -p /tmp/clt
  unzip -q -o /tmp/cmdline-tools.zip -d /tmp/clt
  mv /tmp/clt/cmdline-tools "$ANDROID_HOME/cmdline-tools/latest"
  rm -rf /tmp/cmdline-tools.zip /tmp/clt
fi
export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"
yes | sdkmanager --licenses >/dev/null 2>&1 || true
retry sdkmanager "platform-tools" "platforms;android-36" "build-tools;36.0.0" "platforms;android-35" "build-tools;35.0.0"

echo "==> [8/8] Environment variables ke ~/.bashrc + service Waydroid"
if ! grep -q "ANDROID_HOME" ~/.bashrc; then
cat << 'EOF' >> ~/.bashrc

# --- Dev Environment (Flutter/FVM, Android, Dart, Bun, SDKMAN) ---
export ANDROID_HOME="$HOME/Android/Sdk"
export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"
export PATH="$HOME/.local/opt/dart-sdk/bin:$HOME/.pub-cache/bin:$PATH"
export PATH="$HOME/.fvm_flutter/bin:$HOME/fvm/default/bin:$PATH"
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"
export PATH="$HOME/.local/bin:$HOME/.npm-global/bin:$PATH"
export GOPATH="$HOME/go"
export PATH="$GOPATH/bin:$PATH"
export SDKMAN_DIR="$HOME/.sdkman"
[[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] && source "$HOME/.sdkman/bin/sdkman-init.sh"
EOF
fi
sudo systemctl enable --now waydroid-container 2>/dev/null || true

echo "==> Database & Podman: inisialisasi + aktifkan service"
# MariaDB
sudo systemctl enable --now mariadb || true
# PostgreSQL (initdb hanya sekali, dilewati jika data dir sudah ada)
[ -f /var/lib/pgsql/data/PG_VERSION ] || sudo postgresql-setup --initdb || true
sudo systemctl enable --now postgresql || true
# Podman rootless: socket user agar docker-compose/Dev tools yang butuh DOCKER_HOST bisa jalan
systemctl --user enable --now podman.socket 2>/dev/null || true
grep -q "DOCKER_HOST" ~/.bashrc || echo 'export DOCKER_HOST="unix://$XDG_RUNTIME_DIR/podman/podman.sock"' >> ~/.bashrc

echo
echo "=== SELESAI ==="
echo "Langkah berikutnya:"
echo "  source ~/.bashrc"
echo "  flutter doctor                     # Flutter 3.41.6 sudah aktif via fvm global"
echo "  go version                         # cek Go"
echo "  claude / agy / copilot / pi        # login masing-masing AI CLI saat pertama kali dijalankan"
echo "  code / zed / nvim                  # text editor"
echo "  source ~/.venvs/camoufox/bin/activate  # lalu pakai: from camoufox.sync_api import Camoufox"
echo "  sudo waydroid init -s GAPPS        # atau tanpa -s GAPPS untuk AOSP polos"
echo "  sudo mysql_secure_installation     # set password root MariaDB"
echo "  sudo -u postgres psql -c \"ALTER USER postgres PASSWORD 'gantipassword';\"   # password PostgreSQL"
echo "  podman run --rm hello-world        # tes Podman rootless"
echo "  Steam > Settings > Compatibility > aktifkan Steam Play untuk semua judul"
lspci | grep -qi nvidia && echo "  NVIDIA: tunggu ±10 menit lalu reboot agar modul kernel selesai dibuild"
