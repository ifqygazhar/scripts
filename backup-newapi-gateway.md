# Panduan Backup Otomatis New API ke Google Drive (Ubuntu Server)

Dokumentasi ini menjelaskan konfigurasi backup otomatis untuk database SQLite dan direktori data New API di VPS Ubuntu, yang kemudian dikompresi dan diunggah ke Google Drive menggunakan Rclone serta dijadwalkan via Cronjob.

---

## Prasyarat
- Server Ubuntu dengan Docker berjalan.
- Akses terminal dengan hak akses `root` atau `sudo`.
- Akun Google Drive aktif.

---

## 1. Instalasi Rclone
Jalankan perintah berikut di terminal VPS untuk memasang Rclone:

```bash
sudo apt update && sudo apt install -y rclone
```

---

## 2. Otorisasi Rclone ke Google Drive

Karena VPS berbasis CLI (*headless*), proses otorisasi Google dilakukan menggunakan SSH Port Forwarding dari komputer/laptop lokal.

### Langkah A: Buka SSH Tunnel di Laptop/PC Lokal
Jalankan perintah ini di terminal laptop (PowerShell / Terminal macOS/Linux):

```bash
ssh -L 53682:127.0.0.1:53682 <USER>@<IP_VPS>
```

### Langkah B: Jalankan Konfigurasi Rclone di VPS
Di dalam sesi SSH tersebut, jalankan:

```bash
rclone config
```

Ikuti panduan input interaktif berikut:
1. Ketik `n` (New remote).
2. **Name**: `gdrive` (atau nama remote pilihan).
3. **Storage**: Pilih nomor / ketik `drive` (Google Drive).
4. **client_id** & **client_secret**: Tekan `Enter` (kosongkan).
5. **scope**: Pilih `1` (Full access).
6. **root_folder_id** & **service_account_file**: Tekan `Enter` (kosongkan).
7. **Edit advanced config?**: Ketik `n`.
8. **Use auto config?**: Ketik `y`.
9. Buka browser di laptop, akses: `http://127.0.0.1:53682/auth` lalu login dan beri izin akses Google Drive.
10. Setelah sukses di browser, kembali ke terminal:
    - **Configure this as a Shared Drive?**: Ketik `n`.
    - **Keep this remote?**: Ketik `y`.
    - Ketik `q` untuk keluar dari menu config.

### Langkah C: Verifikasi Koneksi
```bash
# Tes pembuatan folder backup di Google Drive
rclone mkdir gdrive:Backup_NewAPI

# Verifikasi folder
rclone lsd gdrive:
```

---

## 3. Pembuatan Script Backup Bash

Buat file executable script backup:

```bash
sudo nano /usr/local/bin/backup-newapi.sh
```

Tempel kode berikut:

```bash
#!/bin/bash

# ================= KONFIGURASI =================
CONTAINER_NAME="<NAMA_CONTAINER_DOCKER>" # Contoh: new-api
BACKUP_DIR="/root/backups/newapi"
GDRIVE_REMOTE="<NAMA_REMOTE_RCLONE>:Backup_NewAPI" # Contoh: gdrive:Backup_NewAPI
RETENTION_DAYS_LOCAL=7
RETENTION_DAYS_GDRIVE=30
# ===============================================

DATE=$(date +%Y%m%d_%H%M%S)

# 1. Buat direktori lokal jika belum ada
mkdir -p "$BACKUP_DIR"

# 2. Salin data dari container Docker
docker cp "$CONTAINER_NAME":/data "$BACKUP_DIR/data_$DATE"

# 3. Kompresi data ke tar.gz
cd "$BACKUP_DIR" || exit 1
tar -czvf "backup_$DATE.tar.gz" "data_$DATE"
rm -rf "data_$DATE"

# 4. Upload ke Google Drive
rclone copy "$BACKUP_DIR/backup_$DATE.tar.gz" "$GDRIVE_REMOTE"

# 5. Rotasi file: Hapus backup lama di Google Drive (>30 hari)
rclone delete --min-age "${RETENTION_DAYS_GDRIVE}d" "$GDRIVE_REMOTE"

# 6. Rotasi file: Hapus backup lama di VPS lokal (>7 hari)
find "$BACKUP_DIR" -type f -name "*.tar.gz" -mtime +"$RETENTION_DAYS_LOCAL" -exec rm {} \;
```

Beri izin eksekusi pada file script:

```bash
sudo chmod +x /usr/local/bin/backup-newapi.sh
```

---

## 4. Uji Coba Eksekusi Manual

Jalankan script untuk memastikan alur backup dan upload berjalan normal:

```bash
/usr/local/bin/backup-newapi.sh
```

Periksa apakah file arsip berhasil masuk ke Google Drive:

```bash
rclone ls gdrive:Backup_NewAPI
```

---

## 5. Otomasi Menggunakan Cronjob

Buka editor cron:

```bash
crontab -e
```

Tambahkan baris berikut di baris paling bawah untuk menjalankan backup otomatis setiap hari pukul **02.00 AM**:

```cron
0 2 * * * nice -n 19 /usr/local/bin/backup-newapi.sh >/dev/null 2>&1
```

> **Catatan:** Perintah `nice -n 19` memberikan prioritas CPU terendah pada proses backup agar tidak mengganggu performa API saat proses kompresi berjalan.

---

## 6. Prosedur Restore (Pemulihan Data)

Jika server mengalami kerusakan atau saat migrasi ke instance baru:

1. Unduh file backup dari Google Drive:
   ```bash
   rclone copy gdrive:Backup_NewAPI/<NAMA_FILE_BACKUP>.tar.gz /root/
   ```
2. Ekstrak arsip:
   ```bash
   tar -xzvf <NAMA_FILE_BACKUP>.tar.gz
   ```
3. Salin kembali folder `/data` ke dalam container Docker:
   ```bash
   docker cp ./data_<TIMESTAMP>/. <NAMA_CONTAINER_DOCKER>:/data/
   ```
4. Restart container:
   ```bash
   docker restart <NAMA_CONTAINER_DOCKER>
   ```
