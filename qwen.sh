#!/bin/bash

# ==========================================
# QWENCLOUD GENERATOR - TUI SETUP SCRIPT V2
# ==========================================

# Pastikan whiptail terinstal untuk TUI
if ! command -v whiptail &> /dev/null; then
    sudo apt-get update
    sudo apt-get install -y whiptail
fi

DIR_NAME="qwencloud-generator"

# Fungsi untuk menginstal dependensi dasar (Fix Error 127)
install_deps() {
    whiptail --title "Instalasi" --infobox "Mengupdate sistem dan menginstal dependensi... Mohon tunggu." 8 60
    sudo apt update && sudo apt upgrade -y
    sudo apt install -y python3 python3-pip python3-venv git xvfb jq nano

    if [ ! -d "$DIR_NAME" ]; then
        git clone https://github.com/Vanszs/qwencloud-generator.git
    fi

    cd $DIR_NAME

    # Setup Virtual Environment
    if [ ! -d "venv" ]; then
        python3 -m venv venv
    fi
    source venv/bin/activate

    # Install Python Requirements & Playwright (Diperbarui agar kebal Error 127)
    pip install -r requirements.txt
    python3 -m playwright install chromium
    python3 -m playwright install-deps

    whiptail --title "Sukses" --msgbox "Semua dependensi & komponen grafis Ubuntu berhasil diinstal!" 8 45
}

# Fungsi untuk setup Proxy (Fix Connection Reset)
setup_proxy() {
    cd $DIR_NAME
    PROXY=$(whiptail --title "Setup Proxy" --inputbox "Masukkan detail proxy Anda (Format: username:password@host:port)\n\nScript akan otomatis menambahkan http:// agar tidak terjadi error." 11 70 3>&1 1>&2 2>&3)
    
    if [ ! -z "$PROXY" ]; then
        # Cek apakah pengguna sudah memasukkan http:// atau socks5://
        if [[ ! "$PROXY" == http://* ]] && [[ ! "$PROXY" == socks5://* ]]; then
            PROXY="http://$PROXY"
        fi
        
        echo "$PROXY" > proxy.txt
        whiptail --title "Sukses" --msgbox "Proxy berhasil disimpan dengan format yang benar:\n\n$PROXY" 10 60
    fi
}

# Fungsi untuk setup Email List (Fix Double @gmail.com)
setup_email() {
    cd $DIR_NAME
    source venv/bin/activate
    EMAIL=$(whiptail --title "Generate Email List" --inputbox "Masukkan username Gmail utama Anda:" 8 60 3>&1 1>&2 2>&3)
    
    if [ ! -z "$EMAIL" ]; then
        # Membuang @gmail.com jika pengguna tidak sengaja mengetiknya
        CLEAN_EMAIL=${EMAIL%@gmail.com}
        
        python3 generate_email_list.py "$CLEAN_EMAIL" -o email_list.txt
        whiptail --title "Sukses" --msgbox "Daftar email untuk '$CLEAN_EMAIL' berhasil dibuat!" 8 45
    fi
}

# Fungsi untuk setup OAuth
setup_oauth() {
    cd $DIR_NAME
    source venv/bin/activate
    
    whiptail --title "Setup OAuth (1/3)" --msgbox "Anda akan diarahkan ke editor teks untuk menyimpan kredensial.\n\nBuka file client_secret.json dari PC Anda, copy isinya, dan paste ke dalam editor yang akan terbuka. Setelah selesai, tekan Ctrl+X, lalu Y, lalu Enter." 12 70
    nano client_secret.json

    EMAIL_AUTH=$(whiptail --title "Setup OAuth (2/3)" --inputbox "Masukkan alamat EMAIL LENGKAP Anda (misal: nama@gmail.com):" 8 60 3>&1 1>&2 2>&3)
    
    if [ ! -z "$EMAIL_AUTH" ]; then
        URL=$(python3 -c "
from gmail_auth import _default_client
client = _default_client()
print(f'https://accounts.google.com/o/oauth2/auth?client_id={client[\"client_id\"]}&redirect_uri=http%3A//localhost%3A8085/callback&scope=https%3A//www.googleapis.com/auth/gmail.readonly&response_type=code&access_type=offline&prompt=consent&login_hint=$EMAIL_AUTH')
" 2>/dev/null)

        whiptail --title "Buka Link Ini di Browser!" --msgbox "Copy link di bawah ini dan buka di browser PC Anda:\n\n$URL\n\nSetelah login, copy KODE yang ada di URL (setelah 'code=')." 15 80

        CODE=$(whiptail --title "Setup OAuth (3/3)" --inputbox "Paste KODE yang Anda dapatkan dari URL browser tadi:" 8 60 3>&1 1>&2 2>&3)

        if [ ! -z "$CODE" ]; then
            python3 -c "
from gmail_auth import exchange_code
try:
    exchange_code('$EMAIL_AUTH', '$CODE')
    print('Token saved!')
except Exception as e:
    print(f'Error: {e}')
" > oauth_result.txt
            
            RESULT=$(cat oauth_result.txt)
            whiptail --title "Status OAuth" --msgbox "$RESULT" 8 45
        fi
    fi
}

# Fungsi untuk menjalankan Bot
run_bot() {
    cd $DIR_NAME
    source venv/bin/activate
    
    TARGET=$(whiptail --title "Jalankan Bot" --inputbox "Berapa banyak API Key yang ingin di-harvest?" 8 60 "50" 3>&1 1>&2 2>&3)
    THREADS=$(whiptail --title "Jalankan Bot" --inputbox "Berapa banyak thread (browser bersamaan)?\nSaran: 12-15 untuk VPS Anda." 10 60 "12" 3>&1 1>&2 2>&3)
    
    if (whiptail --title "Jalankan Bot" --yesno "Jalankan dalam mode Invisible (Xvfb/Headless) agar tidak crash di VPS?" 8 60); then
        MODE="--headless"
    else
        MODE=""
    fi

    clear
    echo "============================================="
    echo "MEMULAI BOT QWENCLOUD GENERATOR"
    echo "Target: $TARGET | Threads: $THREADS | Mode: $MODE"
    echo "Tekan Ctrl+C untuk menghentikan bot."
    echo "============================================="
    sleep 3
    
    python3 run.py $TARGET $MODE -t $THREADS
    
    echo ""
    read -p "Tekan Enter untuk kembali ke menu utama..."
}

# ==========================================
# MAIN MENU LOOP
# ==========================================
while true; do
    CHOICE=$(whiptail --title "QwenCloud Bot Manager" --menu "Pilih menu navigasi di bawah ini:" 18 60 7 \
        "1" "Install Dependensi & Perbaiki Komponen (PENTING)" \
        "2" "Setup File Proxy" \
        "3" "Generate Email List" \
        "4" "Setup Gmail OAuth (Login Google)" \
        "5" "Jalankan Bot Harvest API!" \
        "6" "Keluar" 3>&1 1>&2 2>&3)

    case $CHOICE in
        1) install_deps ;;
        2) setup_proxy ;;
        3) setup_email ;;
        4) setup_oauth ;;
        5) run_bot ;;
        6) clear; exit 0 ;;
        *) clear; exit 0 ;;
    esac
done
