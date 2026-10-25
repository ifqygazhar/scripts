mkdir -p ~/.local/bin ~/.boxd-profiles ~/.ssh
touch ~/.ssh/config
grep -q "Include ~/.boxd-profiles/" ~/.ssh/config 2>/dev/null || sed -i '1s;^;Include ~/.boxd-profiles/*/.ssh/config\n\n;' ~/.ssh/config

cat << 'EOF' > ~/.local/bin/boxd-tui
#!/usr/bin/env bash

PROFILES_DIR="$HOME/.boxd-profiles"
mkdir -p "$PROFILES_DIR"

# Fallback jika gum belum terinstal
if ! command -v gum &> /dev/null; then
    echo "⚠️  Paket 'gum' belum terinstal. Menginstal via dnf..."
    sudo dnf install -y gum
fi

# Fungsi menjalankan boxd di dalam isolasi profil
run_boxd() {
    local profile="$1"
    shift
    local prof_path="$PROFILES_DIR/$profile"
    mkdir -p "$prof_path/.config" "$prof_path/.ssh"
    HOME="$prof_path" XDG_CONFIG_HOME="$prof_path/.config" boxd "$@"
}

# Ambil daftar host .boxd dari ssh config milik profil
get_machines() {
    local profile="$1"
    local ssh_cfg="$PROFILES_DIR/$profile/.ssh/config"
    if [[ -f "$ssh_cfg" ]]; then
        awk '/^Host / {for(i=2;i<=NF;i++) if ($i ~ /\.boxd$/) {sub(/\.boxd$/, "", $i); print $i}}' "$ssh_cfg"
    fi
}

while true; do
    clear
    gum style \
        --foreground 212 --border-foreground 57 --border rounded \
        --align center --width 55 --margin "1 0" --padding "1 2" \
        "📦 BOXD MULTI-ACCOUNT TUI (FEDORA)" \
        "Kelola Akun, SSH, & Transfer File dengan Cepat"

    # Ambil daftar profil akun yang sudah ada
    mapfile -t PROFILES < <(find "$PROFILES_DIR" -mindepth 1 -maxdepth 1 -type d -printf "%f\n" | sort)

    MENU_ITEMS=()
    for p in "${PROFILES[@]}"; do
        MENU_ITEMS+=("👤 Gunakan Profil: $p")
    done
    MENU_ITEMS+=(
        "➕ Tambah / Buat Profil Akun Baru"
        "🗑️  Hapus Profil Akun"
        "❌ Keluar"
    )

    CHOICE=$(gum choose --header "Pilih Profil Akun atau Aksi:" "${MENU_ITEMS[@]}")

    case "$CHOICE" in
        "➕ Tambah / Buat Profil Akun Baru")
            NEW_PROF=$(gum input --placeholder "Masukkan nama profil (contoh: akun1, kerja, pribadi)")
            if [[ -n "$NEW_PROF" ]]; then
                NEW_PROF=$(echo "$NEW_PROF" | tr -d ' ')
                mkdir -p "$PROFILES_DIR/$NEW_PROF/.config" "$PROFILES_DIR/$NEW_PROF/.ssh"
                gum style --foreground 46 "✓ Profil '$NEW_PROF' berhasil dibuat!"
                if gum confirm "Langsung login ke boxd untuk profil '$NEW_PROF' sekarang?"; then
                    run_boxd "$NEW_PROF" auth login || run_boxd "$NEW_PROF" login
                fi
            fi
            ;;

        "🗑️  Hapus Profil Akun")
            if [[ ${#PROFILES[@]} -eq 0 ]]; then
                gum style --foreground 196 "Belum ada profil untuk dihapus."
                sleep 1.5
                continue
            fi
            DEL_PROF=$(gum choose --header "Pilih profil yang ingin dihapus:" "${PROFILES[@]}" "Batal")
            if [[ "$DEL_PROF" != "Batal" && -n "$DEL_PROF" ]]; then
                if gum confirm "Yakin ingin menghapus profil '$DEL_PROF' beserta sesi loginnya?"; then
                    rm -rf "${PROFILES_DIR:?}/$DEL_PROF"
                    gum style --foreground 46 "✓ Profil '$DEL_PROF' dihapus."
                    sleep 1
                fi
            fi
            ;;

        "❌ Keluar"|"")
            clear
            exit 0
            ;;

        "👤 Gunakan Profil: "*)
            ACTIVE_PROF="${CHOICE#👤 Gunakan Profil: }"
            while true; do
                clear
                gum style \
                    --foreground 86 --border-foreground 86 --border normal \
                    --width 55 --padding "0 2" \
                    "👤 Profil Aktif : $ACTIVE_PROF"

                ACTION=$(gum choose --header "Pilih aksi untuk [$ACTIVE_PROF]:" \
                    "🖥️  SSH ke Mesin (Interactive)" \
                    "📥 Download File/Folder dari VPS (CP ke Lokal)" \
                    "📤 Upload File/Folder ke VPS (CP ke VPS)" \
                    "📋 Lihat Daftar Mesin (boxd machine list)" \
                    "🔑 Login / Re-auth Akun Ini" \
                    "⌨️  Jalankan Perintah Custom boxd..." \
                    "⬅️  Kembali ke Menu Profil")

                case "$ACTION" in
                    "🖥️  SSH ke Mesin (Interactive)")
                        mapfile -t MACHINES < <(get_machines "$ACTIVE_PROF")
                        if [[ ${#MACHINES[@]} -gt 0 ]]; then
                            MACHINES+=("✍️  Ketik nama mesin manual...")
                            M_NAME=$(gum choose --header "Pilih mesin dari daftar:" "${MACHINES[@]}")
                            if [[ "$M_NAME" == "✍️  Ketik nama mesin manual..." ]]; then
                                M_NAME=$(gum input --placeholder "Nama mesin (contoh: weak-tide)")
                            fi
                        else
                            M_NAME=$(gum input --placeholder "Nama mesin (contoh: weak-tide)")
                        fi

                        if [[ -n "$M_NAME" ]]; then
                            SSH_CFG="$PROFILES_DIR/$ACTIVE_PROF/.ssh/config"
                            echo "Menghubungkan ke $M_NAME.boxd..."
                            if [[ -f "$SSH_CFG" ]]; then
                                ssh -F "$SSH_CFG" "${M_NAME%.boxd}.boxd"
                            else
                                run_boxd "$ACTIVE_PROF" machine ssh "${M_NAME%.boxd}"
                            fi
                        fi
                        ;;

                    "📥 Download File/Folder dari VPS (CP ke Lokal)")
                        mapfile -t MACHINES < <(get_machines "$ACTIVE_PROF")
                        if [[ ${#MACHINES[@]} -gt 0 ]]; then
                            M_NAME=$(gum choose --header "Pilih mesin sumber:" "${MACHINES[@]}")
                        else
                            M_NAME=$(gum input --placeholder "Nama mesin (contoh: weak-tide)")
                        fi
                        REMOTE_PATH=$(gum input --placeholder "Path di VPS (contoh: /home/boxd/cbdg-testing/file.txt)" --value "/home/boxd/")
                        LOCAL_PATH=$(gum input --placeholder "Tujuan di Lokal (default: ./)" --value "./")

                        if [[ -n "$M_NAME" && -n "$REMOTE_PATH" ]]; then
                            if gum confirm "Copy secara rekursif (-r) untuk seluruh folder?"; then
                                run_boxd "$ACTIVE_PROF" machine cp -r "${M_NAME%.boxd}:$REMOTE_PATH" "${LOCAL_PATH:-./}"
                            else
                                run_boxd "$ACTIVE_PROF" machine cp "${M_NAME%.boxd}:$REMOTE_PATH" "${LOCAL_PATH:-./}"
                            fi
                            echo ""
                            gum style --foreground 46 "✅ Selesai! Tekan Enter untuk kembali."
                            read -r
                        fi
                        ;;

                    "📤 Upload File/Folder ke VPS (CP ke VPS)")
                        mapfile -t MACHINES < <(get_machines "$ACTIVE_PROF")
                        if [[ ${#MACHINES[@]} -gt 0 ]]; then
                            M_NAME=$(gum choose --header "Pilih mesin tujuan:" "${MACHINES[@]}")
                        else
                            M_NAME=$(gum input --placeholder "Nama mesin (contoh: weak-tide)")
                        fi
                        LOCAL_PATH=$(gum input --placeholder "Path file/folder lokal (contoh: ./script.sh)" --value "./")
                        REMOTE_PATH=$(gum input --placeholder "Tujuan di VPS (contoh: /home/boxd/)" --value "/home/boxd/")

                        if [[ -n "$M_NAME" && -n "$LOCAL_PATH" ]]; then
                            if gum confirm "Copy secara rekursif (-r) untuk seluruh folder?"; then
                                run_boxd "$ACTIVE_PROF" machine cp -r "$LOCAL_PATH" "${M_NAME%.boxd}:$REMOTE_PATH"
                            else
                                run_boxd "$ACTIVE_PROF" machine cp "$LOCAL_PATH" "${M_NAME%.boxd}:$REMOTE_PATH"
                            fi
                            echo ""
                            gum style --foreground 46 "✅ Selesai! Tekan Enter untuk kembali."
                            read -r
                        fi
                        ;;

                    "📋 Lihat Daftar Mesin (boxd machine list)")
                        echo ""
                        run_boxd "$ACTIVE_PROF" machine list || run_boxd "$ACTIVE_PROF" list
                        echo ""
                        gum style --foreground 240 "Tekan Enter untuk kembali..."
                        read -r
                        ;;

                    "🔑 Login / Re-auth Akun Ini")
                        run_boxd "$ACTIVE_PROF" auth login || run_boxd "$ACTIVE_PROF" login
                        echo ""
                        gum style --foreground 46 "Tekan Enter untuk kembali..."
                        read -r
                        ;;

                    "⌨️  Jalankan Perintah Custom boxd...")
                        CUSTOM_ARGS=$(gum input --placeholder "Ketik argumen setelah 'boxd' (contoh: machine stop weak-tide)")
                        if [[ -n "$CUSTOM_ARGS" ]]; then
                            # shellcheck disable=SC2086
                            run_boxd "$ACTIVE_PROF" $CUSTOM_ARGS
                            echo ""
                            gum style --foreground 240 "Tekan Enter untuk kembali..."
                            read -r
                        fi
                        ;;

                    "⬅️  Kembali ke Menu Profil"|"")
                        break
                        ;;
                esac
            done
            ;;
    esac
done
EOF

chmod +x ~/.local/bin/boxd-tui
grep -q 'export PATH="$HOME/.local/bin:$PATH"' ~/.zshrc || echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
grep -q "alias bx='boxd-tui'" ~/.zshrc || echo "alias bx='boxd-tui'" >> ~/.zshrc
source ~/.zshrc
