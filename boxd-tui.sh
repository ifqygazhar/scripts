#!/usr/bin/env bash
# ==============================================================================
# 📦 All-in-One Installer & Script: boxd-tui (Multiprofile Manager for Fedora)
# Cara pakai: Copy-paste seluruh isi file ini langsung ke terminal, atau
#             jalankan: bash setup-bx.sh
# ==============================================================================

echo "===================================================="
echo "🚀 Memulai Instalasi boxd-tui (Multiprofile Manager)"
echo "===================================================="

# 1. Cek dan install 'gum' jika belum ada
if ! command -v gum &> /dev/null; then
    if command -v dnf &> /dev/null; then
        echo "[1/3] Menginstal paket 'gum' via dnf..."
        sudo dnf install -y gum
    else
        echo "⚠️  Paket 'gum' belum terinstal. Silakan instal dari: https://github.com/charmbracelet/gum"
    fi
else
    echo "[1/3] ✓ Paket 'gum' sudah terinstal."
fi

# 2. Buat file executable ~/.local/bin/boxd-tui
mkdir -p "$HOME/.local/bin" "$HOME/.boxd-profiles"
echo "[2/3] Memasang aplikasi ke ~/.local/bin/boxd-tui..."

cat << 'EOF' > "$HOME/.local/bin/boxd-tui"
#!/usr/bin/env bash

PROFILES_DIR="$HOME/.boxd-profiles"
ACTIVE_FILE="$PROFILES_DIR/.active_profile"
mkdir -p "$PROFILES_DIR"

if ! command -v gum &> /dev/null; then
    echo "Paket 'gum' belum terinstal. Jalankan: sudo dnf install -y gum"
    exit 1
fi

if ! command -v boxd &> /dev/null; then
    echo "Aplikasi 'boxd' CLI belum terinstal di sistem ini."
    exit 1
fi

# Simpan sesi aktif sistem ke dalam folder profil
save_current_to_profile() {
    local prof="$1"
    [[ -z "$prof" ]] && return
    local pdir="$PROFILES_DIR/$prof"
    mkdir -p "$pdir/.config" "$pdir/.local/share" "$pdir/.ssh"

    [[ -d "$HOME/.config/boxd" ]] && rm -rf "$pdir/.config/boxd" && cp -r "$HOME/.config/boxd" "$pdir/.config/" 2>/dev/null
    [[ -d "$HOME/.local/share/boxd" ]] && rm -rf "$pdir/.local/share/boxd" && cp -r "$HOME/.local/share/boxd" "$pdir/.local/share/" 2>/dev/null
    [[ -d "$HOME/.boxd" ]] && rm -rf "$pdir/.boxd" && cp -r "$HOME/.boxd" "$pdir/" 2>/dev/null
    [[ -f "$HOME/.ssh/config" ]] && cp "$HOME/.ssh/config" "$pdir/.ssh/config" 2>/dev/null
}

# Muat sesi dari folder profil ke sistem utama
load_profile_to_system() {
    local prof="$1"
    local pdir="$PROFILES_DIR/$prof"
    mkdir -p "$pdir/.config" "$pdir/.local/share" "$pdir/.ssh"

    rm -rf "$HOME/.config/boxd" "$HOME/.local/share/boxd" "$HOME/.boxd" 2>/dev/null
    [[ -d "$pdir/.config/boxd" ]] && cp -r "$pdir/.config/boxd" "$HOME/.config/" 2>/dev/null
    [[ -d "$pdir/.local/share/boxd" ]] && cp -r "$pdir/.local/share/boxd" "$HOME/.local/share/" 2>/dev/null
    [[ -d "$pdir/.boxd" ]] && cp -r "$pdir/.boxd" "$HOME/" 2>/dev/null
    [[ -f "$pdir/.ssh/config" ]] && cp "$pdir/.ssh/config" "$HOME/.ssh/config" 2>/dev/null

    echo "$prof" > "$ACTIVE_FILE"
}

# Ambil daftar nama mesin aktif secara otomatis
get_active_machines() {
    boxd list 2>/dev/null | awk 'NR>1 && $1 != "" && $1 !~ /^No/ && $1 !~ /^█/ {print $1}'
}

# Inisialisasi awal jika belum ada profil
if [[ ! -f "$ACTIVE_FILE" ]]; then
    echo "default" > "$ACTIVE_FILE"
    save_current_to_profile "default"
fi

while true; do
    ACTIVE_PROF=$(cat "$ACTIVE_FILE" 2>/dev/null || echo "default")
    save_current_to_profile "$ACTIVE_PROF"

    clear
    gum style \
        --foreground 212 --border-foreground 57 --border rounded \
        --align center --width 60 --margin "1 0" --padding "1 2" \
        "📦 BOXD MULTIPROFILE MANAGER TUI" \
        "👤 Profil Aktif : [ $ACTIVE_PROF ]" \
        "📂 Lokasi Lokal : $(pwd)"

    ACTION=$(gum choose --header "Pilih Aksi untuk [$ACTIVE_PROF]:" \
        "🔄 Ganti / Kelola Profil Akun (Multiprofile)" \
        "🏢 Pindah Organisasi di Akun Ini (boxd auth switch)" \
        "📋 Lihat Daftar Mesin (boxd list)" \
        "🖥️  Masuk / Connect ke Mesin (boxd connect)" \
        "📥 Download File/Folder dari VPS (boxd machine cp)" \
        "📤 Upload File/Folder ke VPS (boxd machine cp)" \
        "🔑 Login Ulang di Profil Ini (boxd auth login)" \
        "🚪 Logout dari Profil Ini (boxd auth logout)" \
        "❌ Keluar")

    case "$ACTION" in
        "🔄 Ganti / Kelola Profil Akun (Multiprofile)")
            mapfile -t PROFILES < <(find "$PROFILES_DIR" -mindepth 1 -maxdepth 1 -type d -printf "%f\n" | sort)
            SUB_MENU=()
            for p in "${PROFILES[@]}"; do
                if [[ "$p" == "$ACTIVE_PROF" ]]; then
                    SUB_MENU+=("✅ Pakai Profil: $p (Aktif)")
                else
                    SUB_MENU+=("👤 Pakai Profil: $p")
                fi
            done
            SUB_MENU+=(
                "➕ Buat Profil Akun Baru"
                "✏️  Beri Nama Ulang Profil Aktif ($ACTIVE_PROF)"
                "🗑️  Hapus Profil"
                "⬅️  Kembali"
            )

            P_CHOICE=$(gum choose --header "Pilih Profil Akun:" "${SUB_MENU[@]}")
            case "$P_CHOICE" in
                "👤 Pakai Profil: "*)
                    TARGET_PROF="${P_CHOICE#👤 Pakai Profil: }"
                    save_current_to_profile "$ACTIVE_PROF"
                    load_profile_to_system "$TARGET_PROF"
                    gum style --foreground 46 "✓ Berhasil beralih ke profil: $TARGET_PROF"
                    sleep 1
                    ;;
                "➕ Buat Profil Akun Baru")
                    NEW_P=$(gum input --placeholder "Nama profil baru (contoh: akun2, kantor)")
                    if [[ -n "$NEW_P" ]]; then
                        NEW_P=$(echo "$NEW_P" | tr -d ' ')
                        save_current_to_profile "$ACTIVE_PROF"
                        mkdir -p "$PROFILES_DIR/$NEW_P"
                        load_profile_to_system "$NEW_P"
                        if gum confirm "Profil '$NEW_P' aktif. Langsung login via browser sekarang?"; then
                            boxd auth login
                            save_current_to_profile "$NEW_P"
                        fi
                    fi
                    ;;
                "✏️  Beri Nama Ulang Profil Aktif ($ACTIVE_PROF)")
                    RENAME_P=$(gum input --placeholder "Nama baru untuk '$ACTIVE_PROF'" --value "$ACTIVE_PROF")
                    if [[ -n "$RENAME_P" && "$RENAME_P" != "$ACTIVE_PROF" ]]; then
                        RENAME_P=$(echo "$RENAME_P" | tr -d ' ')
                        mv "$PROFILES_DIR/$ACTIVE_PROF" "$PROFILES_DIR/$RENAME_P"
                        echo "$RENAME_P" > "$ACTIVE_FILE"
                    fi
                    ;;
                "🗑️  Hapus Profil")
                    DEL_P=$(gum choose --header "Pilih profil yang ingin dihapus:" "${PROFILES[@]}" "Batal")
                    if [[ "$DEL_P" != "Batal" && -n "$DEL_P" ]]; then
                        if [[ "$DEL_P" == "$ACTIVE_PROF" ]]; then
                            gum style --foreground 196 "Tidak bisa menghapus profil yang sedang aktif."
                            sleep 1.5
                        elif gum confirm "Yakin ingin menghapus profil '$DEL_P'?"; then
                            rm -rf "${PROFILES_DIR:?}/$DEL_P"
                        fi
                    fi
                    ;;
            esac
            ;;

        "🏢 Pindah Organisasi di Akun Ini (boxd auth switch)")
            echo ""
            boxd auth switch
            save_current_to_profile "$ACTIVE_PROF"
            echo ""
            read -r -p "Tekan Enter untuk kembali..."
            ;;

        "📋 Lihat Daftar Mesin (boxd list)")
            echo ""
            boxd list
            echo ""
            read -r -p "Tekan Enter untuk kembali..."
            ;;

        "🖥️  Masuk / Connect ke Mesin (boxd connect)")
            mapfile -t M_LIST < <(get_active_machines)
            if [[ ${#M_LIST[@]} -gt 0 ]]; then
                M_LIST+=("✍️  Ketik nama mesin manual...")
                M_NAME=$(gum choose --header "Pilih mesin untuk connect:" "${M_LIST[@]}")
                [[ "$M_NAME" == "✍️  Ketik nama mesin manual..." ]] && M_NAME=$(gum input --placeholder "Nama mesin")
            else
                M_NAME=$(gum input --placeholder "Nama mesin (contoh: weak-tide)")
            fi
            if [[ -n "$M_NAME" ]]; then
                boxd connect "$M_NAME"
            fi
            ;;

        "📥 Download File/Folder dari VPS (boxd machine cp)")
            mapfile -t M_LIST < <(get_active_machines)
            if [[ ${#M_LIST[@]} -gt 0 ]]; then
                M_LIST+=("✍️  Ketik nama mesin manual...")
                M_NAME=$(gum choose --header "Pilih mesin sumber:" "${M_LIST[@]}")
                [[ "$M_NAME" == "✍️  Ketik nama mesin manual..." ]] && M_NAME=$(gum input --placeholder "Nama mesin")
            else
                M_NAME=$(gum input --placeholder "Nama mesin")
            fi
            REMOTE_PATH=$(gum input --placeholder "Path di VPS (contoh: /home/boxd/file.txt)" --value "/home/boxd/")
            LOCAL_PATH=$(gum input --placeholder "Tujuan di Lokal (default: ./ folder saat ini)" --value "./")
            if [[ -n "$M_NAME" && -n "$REMOTE_PATH" ]]; then
                if gum confirm "Copy satu folder penuh secara rekursif (-r)?"; then
                    boxd machine cp -r "${M_NAME}:${REMOTE_PATH}" "${LOCAL_PATH:-./}"
                else
                    boxd machine cp "${M_NAME}:${REMOTE_PATH}" "${LOCAL_PATH:-./}"
                fi
                echo ""
                read -r -p "✅ Selesai. Tekan Enter untuk kembali..."
            fi
            ;;

        "📤 Upload File/Folder ke VPS (boxd machine cp)")
            mapfile -t M_LIST < <(get_active_machines)
            if [[ ${#M_LIST[@]} -gt 0 ]]; then
                M_LIST+=("✍️  Ketik nama mesin manual...")
                M_NAME=$(gum choose --header "Pilih mesin tujuan:" "${M_LIST[@]}")
                [[ "$M_NAME" == "✍️  Ketik nama mesin manual..." ]] && M_NAME=$(gum input --placeholder "Nama mesin")
            else
                M_NAME=$(gum input --placeholder "Nama mesin")
            fi
            LOCAL_PATH=$(gum input --placeholder "Path file/folder lokal (contoh: ./file.txt)" --value "./")
            REMOTE_PATH=$(gum input --placeholder "Tujuan di VPS (contoh: /home/boxd/)" --value "/home/boxd/")
            if [[ -n "$M_NAME" && -n "$LOCAL_PATH" ]]; then
                if gum confirm "Copy satu folder penuh secara rekursif (-r)?"; then
                    boxd machine cp -r "$LOCAL_PATH" "${M_NAME}:${REMOTE_PATH}"
                else
                    boxd machine cp "$LOCAL_PATH" "${M_NAME}:${REMOTE_PATH}"
                fi
                echo ""
                read -r -p "✅ Selesai. Tekan Enter untuk kembali..."
            fi
            ;;

        "🔑 Login Ulang di Profil Ini (boxd auth login)")
            boxd auth login
            save_current_to_profile "$ACTIVE_PROF"
            echo ""
            read -r -p "Tekan Enter untuk kembali..."
            ;;

        "🚪 Logout dari Profil Ini (boxd auth logout)")
            if gum confirm "Yakin ingin logout dari profil [$ACTIVE_PROF]?"; then
                boxd auth logout
                save_current_to_profile "$ACTIVE_PROF"
                echo ""
                read -r -p "Tekan Enter untuk kembali..."
            fi
            ;;

        "❌ Keluar"|"")
            clear
            exit 0
            ;;
    esac
done
EOF

chmod +x "$HOME/.local/bin/boxd-tui"

# 3. Daftarkan PATH & alias 'bx' ke ~/.zshrc dan ~/.bashrc
echo "[3/3] Mengatur alias 'bx' di ~/.zshrc dan ~/.bashrc..."
for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
    if [[ -f "$rc" ]]; then
        grep -q 'export PATH="$HOME/.local/bin:$PATH"' "$rc" || echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$rc"
        grep -q "alias bx='boxd-tui'" "$rc" || echo "alias bx='boxd-tui'" >> "$rc"
    fi
done

export PATH="$HOME/.local/bin:$PATH"
alias bx='boxd-tui'

echo "===================================================="
echo "✅ Selesai dipasang. Ketik perintah: bx"
echo "===================================================="
