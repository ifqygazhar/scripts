#!/bin/bash

# ==========================================
# QWENCLOUD GENERATOR - TUI SETUP SCRIPT
# ==========================================

# Pastikan whiptail terinstal untuk TUI
if ! command -v whiptail &> /dev/null; then
    sudo apt-get update
    sudo apt-get install -y whiptail
fi

DIR_NAME="qwencloud-generator"

# Fungsi untuk menginstal dependensi dasar
install_deps() {
    whiptail --title "Instalasi" --infobox "Mengupdate sistem dan menginstal dependensi... Mohon tunggu." 8 60
    sudo apt update && sudo apt upgrade -y
    sudo apt install -y python3 python3-pip python3-venv git xvfb jq nano

    if [ ! -d "$DIR_NAME" ]; then
        git clone https://github.com/Vanszs/qwencloud-generator.git
    fi

    cd $DIR_NAME

    # Setup Virtual Environment (Penting untuk Ubuntu terbaru)
    if [ ! -d "venv" ]; then
        python3 -m venv venv
    fi
    source venv/bin/activate

    # Install Python Requirements & Playwright
    pip install -r requirements.txt
    playwright install chromium
    sudo playwright install-deps

    whiptail --title "Sukses" --msgbox "Semua dependensi berhasil diinstal!" 8 45
}

# Fungsi untuk setup Proxy
setup_proxy() {
    cd $DIR_NAME
    PROXY=$(whiptail --title "Setup Proxy" --inputbox "Masukkan detail proxy Anda (Format: username:password@host:port)\nKosongkan jika ingin menggunakan IP VPS." 10 60 3>&1 1>&2 2>&3)
    
    if [ ! -z "$PROXY" ]; then
        echo "$PROXY" > proxy.txt
        whiptail --title "Sukses" --msgbox "Proxy berhasil disimpan ke proxy.txt" 8 45
    fi
}

# Fungsi untuk setup Email List
setup_email() {
    cd $DIR_NAME
    source venv/bin/activate
    EMAIL=$(whiptail --title "Generate Email List" --inputbox "Masukkan username Gmail utama Anda (tanpa @gmail.com):" 8 60 3>&1 1>&2 2>&3)
    
    if [ ! -z "$EMAIL" ]; then
        python3 generate_email_list.py "$EMAIL" -o email_list.txt
        whiptail --title "Sukses" --msgbox "Daftar email (dot-variants) berhasil dibuat!" 8 45
    fi
}

# Fungsi untuk setup OAuth
setup_oauth() {
    cd $DIR_NAME
    source venv/bin/activate
    
    whiptail --title "Setup OAuth (1/3)" --msgbox "Anda akan diarahkan ke editor teks untuk menyimpan kredensial.\n\nBuka file client_secret_xxx.json dari PC Anda, copy isinya, dan paste ke dalam editor yang akan terbuka. Setelah selesai, tekan Ctrl+X, lalu Y, lalu Enter." 12 70
    nano client_secret.json

    EMAIL_AUTH=$(whiptail --title "Setup OAuth (2/3)" --inputbox "Masukkan alamat EMAIL LENGKAP Anda (misal: nama@gmail.com):" 8 60 3>&1 1>&2 2>&3)
    
    if [ ! -z "$EMAIL_AUTH" ]; then
        # Generate URL menggunakan Python
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
    
    TARGET=$(whiptail --title "Jalankan Bot" --inputbox "Berapa banyak API Key yang ingin di-harvest?" 8 60 "5" 3>&1 1>&2 2>&3)
    THREADS=$(whiptail --title "Jalankan Bot" --inputbox "Berapa banyak thread (browser bersamaan)?\nSaran: 2-5 untuk VPS 2GB." 10 60 "2" 3>&1 1>&2 2>&3)
    
    if (whiptail --title "Jalankan Bot" --yesno "Jalankan dalam mode Invisible (Xvfb/Headless)?\nPilih YES untuk VPS." 8 60); then
        MODE="--headless"
    else
        MODE=""
    fi

    # Bersihkan layar sebelum menjalankan bot
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
        "1" "Install Dependensi & Clone Repo (Wajib Pertama)" \
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
