🚀 PutzOfficial Pterodactyl Installer

PutzOfficial Pterodactyl Installer adalah installer Bash modular yang dibuat untuk membantu proses instalasi, konfigurasi, pemeriksaan, dan penghapusan Pterodactyl Panel serta Pterodactyl Wings pada VPS Linux.

Installer ini dirancang dengan sistem modular sehingga setiap komponen dapat dikelola melalui file Bash terpisah.

«Developer: PutzOfficial
Version: 1.1.1
Platform: Linux VPS
Shell: Bash
License: MIT
Status: Open Source»

---

✨ Features

Installer menyediakan beberapa fitur utama:

1. Install Pterodactyl Panel

Menginstal komponen utama Pterodactyl Panel, termasuk dependency yang diperlukan.

Komponen yang dapat digunakan oleh Panel antara lain:

- PHP
- PHP-FPM
- MariaDB
- Redis
- Nginx
- Composer
- Pterodactyl Panel
- Queue Worker
- Scheduler
- SSL / Let's Encrypt
- systemd

---

2. Install Docker

Installer menyediakan modul khusus untuk Docker Engine.

Docker diperlukan oleh Wings untuk menjalankan server dalam container.

Fitur:

- Docker Engine
- Docker CLI
- Container runtime
- Docker service
- systemd integration

---

3. Install Pterodactyl Wings

Wings merupakan daemon/node yang digunakan Pterodactyl untuk mengelola server yang berjalan pada node.

Fitur installer:

- Download Wings
- Install binary Wings
- Membuat konfigurasi
- Membuat systemd service
- Menjalankan Wings
- Enable Wings saat boot

---

4. Full Installation

Fitur ini menjalankan instalasi secara berurutan:

Pterodactyl Panel
        ↓
Docker
        ↓
Pterodactyl Wings

Sehingga administrator tidak perlu menjalankan setiap installer secara manual.

---

5. Health Check

Health Check digunakan untuk memeriksa status komponen.

Contoh pemeriksaan:

Pterodactyl Panel
Nginx
PHP-FPM
MariaDB
Redis
Docker
Wings
systemd

---

6. Full Uninstall

Installer menyediakan fitur penghapusan Pterodactyl.

Komponen yang dapat dibersihkan:

- Pterodactyl Panel
- Panel configuration
- Pterodactyl database
- Pterodactyl database user
- Pterodactyl Queue Worker
- Pterodactyl Scheduler
- Wings
- Wings configuration
- Wings binary
- Docker
- Docker data
- Redis
- MariaDB
- Nginx
- Certbot
- Composer
- PHP
- PHP-FPM
- SSL configuration
- systemd service

«⚠️ PERINGATAN: Full Uninstall dapat menghapus service dan data sistem. Jangan menjalankannya pada VPS yang digunakan aplikasi lain tanpa memahami dampaknya.»

---

7. Uninstall Wings

Tersedia modul khusus untuk menghapus Wings tanpa harus menghapus seluruh Pterodactyl Panel.

Contohnya:

bash lib/uninstall_wings.sh

Fitur ini dapat membersihkan:

- Wings service
- Wings binary
- Wings configuration
- Wings logs
- Wings systemd configuration

Docker dapat dipertahankan apabila pengguna masih membutuhkannya.

---

🖥️ Supported System

Target utama:

Ubuntu Linux
amd64 / x86_64

Disarankan menggunakan VPS baru atau VPS yang memang disiapkan khusus untuk Pterodactyl.

Sebelum instalasi, pastikan:

- Akses root tersedia
- Internet aktif
- VPS memiliki resource yang cukup
- Domain/subdomain sudah diarahkan ke server
- Port yang dibutuhkan tersedia
- Tidak ada konfigurasi Nginx/PHP yang bentrok

---

📦 Requirements

Minimal:

Root access
Bash
curl
systemd
APT
Internet connection

Contoh mengecek root:

whoami

Hasil yang diharapkan:

root

---

📥 Installation

Method 1 — Clone Repository

Clone repository:

git clone https://github.com/USERNAME/putz-installer.git

Masuk ke directory:

cd putz-installer

Berikan permission:

chmod +x install.sh

Jalankan:

./install.sh

---

⚡ Quick Installation

Jika installer sudah dipublikasikan melalui server bootstrap PutzOfficial, installer dapat dipanggil menggunakan:

bash <(curl -sL https://pterodactyl.putzoffc.biz.id/install)

«Pastikan endpoint "/install" mengarah ke bootstrap/installer yang benar dan selalu gunakan HTTPS.»

---

📂 Project Structure

Struktur project:

putz-installer/
│
├── install.sh
├── uninstall.sh
├── uninstall_wings.sh
│
├── lib/
│   ├── common.sh
│   ├── panel.sh
│   ├── docker.sh
│   ├── wings.sh
│   └── uninstall.sh
│
├── logs/
│
├── README.md
├── LICENSE.md
└── .gitignore

---

🧩 Module System

Installer menggunakan sistem modular.

"install.sh"

File utama installer.

Tugas:

- Menampilkan menu
- Memeriksa system
- Menjalankan Panel installer
- Menjalankan Docker installer
- Menjalankan Wings installer
- Menjalankan Health Check
- Menjalankan Uninstaller

---

"lib/common.sh"

Berisi fungsi umum yang digunakan modul lain.

Contoh:

banner
info
warn
error
log
require_root
check_os
check_arch
system_info
health_check
init_log

---

"lib/panel.sh"

Modul instalasi Pterodactyl Panel.

---

"lib/docker.sh"

Modul instalasi Docker.

---

"lib/wings.sh"

Modul instalasi Pterodactyl Wings.

---

"uninstall.sh"

Uninstaller utama untuk membersihkan instalasi Pterodactyl.

---

"uninstall_wings.sh"

Uninstaller khusus Wings.

---

🧭 Main Menu

Contoh menu:

╭────────────────────────────────────────────────────╮
│                  MAIN MENU                         │
├────────────────────────────────────────────────────┤
│                                                    │
│   01   Install Panel                               │
│   02   Install Docker                              │
│   03   Install Wings                               │
│   04   Full Installation                           │
│   05   Health Check                                │
│   06   Uninstall Panel                             │
│   07   Exit                                        │
│                                                    │
╰────────────────────────────────────────────────────╯

---

🔧 Full Installation

Pilih:

04

Installer menjalankan:

[1/3] Pterodactyl Panel
[2/3] Docker
[3/3] Wings

Setelah selesai, lakukan pengecekan:

systemctl status wings

dan:

systemctl status nginx

---

🪽 Wings

Untuk melihat status:

systemctl status wings

Menjalankan:

systemctl start wings

Menghentikan:

systemctl stop wings

Restart:

systemctl restart wings

Enable saat boot:

systemctl enable wings

Melihat log:

journalctl -u wings -f

---

🐳 Docker

Cek Docker:

docker --version

Cek service:

systemctl status docker

Restart:

systemctl restart docker

Melihat container:

docker ps

---

🌐 Nginx

Cek konfigurasi:

nginx -t

Restart:

systemctl restart nginx

Status:

systemctl status nginx

---

🐘 PHP

Cek versi:

php -v

Contoh mengecek PHP-FPM:

systemctl status php8.3-fpm

«Versi PHP dapat berbeda tergantung versi Pterodactyl dan sistem yang digunakan.»

---

🗄️ MariaDB

Cek:

systemctl status mariadb

Login:

mysql

---

🔴 Redis

Cek:

systemctl status redis-server

---

🔐 SSL

Jika menggunakan Let's Encrypt:

certbot certificates

Renew:

certbot renew

---

🧹 Uninstall Panel

Jalankan:

./uninstall.sh

atau:

bash uninstall.sh

Installer akan meminta konfirmasi sebelum melakukan penghapusan.

Contoh:

Type:
REMOVE EVERYTHING

Kemudian:

Type:
YES

Kedua konfirmasi diperlukan untuk mengurangi risiko penghapusan tidak sengaja.

---

🪽 Uninstall Wings Only

Jika hanya ingin menghapus Wings:

./uninstall_wings.sh

atau:

bash uninstall_wings.sh

Tujuannya adalah membersihkan komponen Wings tanpa melakukan full uninstall terhadap Panel.

---

⚠️ Data & Destructive Operations

Beberapa operasi installer bersifat destructive.

Khusus Full Uninstall, data berikut dapat dihapus:

/var/www/pterodactyl
/etc/pterodactyl
/var/lib/pterodactyl
/var/lib/docker
/etc/docker
/etc/letsencrypt

Database Pterodactyl juga dapat dihapus.

Jangan menjalankan Full Uninstall jika VPS masih menjalankan aplikasi lain yang bergantung pada:

Nginx
PHP
MariaDB
Redis
Docker
Certbot

---

🔍 Troubleshooting

Installer meminta root

Jika muncul:

Installer harus dijalankan sebagai root.

gunakan:

sudo -i

kemudian jalankan kembali installer.

---

Permission denied

Berikan permission:

chmod +x install.sh

Kemudian:

./install.sh

---

Nginx gagal start

Periksa:

nginx -t

Kemudian:

systemctl status nginx

Log:

journalctl -u nginx -n 100 --no-pager

---

Wings gagal start

Periksa:

systemctl status wings

Kemudian:

journalctl -u wings -n 100 --no-pager

---

Docker tidak berjalan

Coba:

systemctl restart docker

Kemudian:

docker info

---

Panel 500 Server Error

Periksa log Laravel:

cd /var/www/pterodactyl
tail -n 100 storage/logs/laravel.log

Kemudian cek permission:

chown -R www-data:www-data /var/www/pterodactyl

«Jangan menggunakan user "nginx" atau "apache" pada Ubuntu jika user tersebut memang tidak ada. User service harus mengikuti web server yang benar-benar terpasang.»

---

📋 Health Check

Gunakan menu:

05 - Health Check

Atau lakukan pemeriksaan manual:

systemctl --failed

Cek service:

systemctl status nginx
systemctl status mariadb
systemctl status redis-server
systemctl status docker
systemctl status wings

---

🔒 Security Recommendations

Setelah VPS selesai dikonfigurasi:

1. Gunakan SSH key

Hindari penggunaan password SSH jika memungkinkan.

2. Gunakan firewall

Contoh:

ufw status

Pastikan hanya port yang memang dibutuhkan yang dibuka.

3. Gunakan HTTPS

Panel sebaiknya menggunakan HTTPS.

4. Jangan membagikan credential

Jangan memasukkan:

root password
database password
API token
SSH private key
Panel API key
Cloudflare API token

ke repository publik.

5. Backup

Sebelum menjalankan operasi destructive:

Backup database
Backup Panel
Backup configuration
Backup Wings configuration

---

☁️ Cloudflare

Installer dapat digunakan bersama Cloudflare, tetapi DNS dan konfigurasi proxy tetap perlu disesuaikan dengan arsitektur VPS.

Contoh:

panel.example.com
node.example.com

Pastikan konfigurasi DNS mengarah ke endpoint yang benar.

Untuk Cloudflare Tunnel/NAT VPS, pastikan tunnel dan origin service sudah berjalan sebelum menguji domain.

---

🔗 Installer Endpoint

Jika menggunakan bootstrap server PutzOfficial:

https://pterodactyl.putzoffc.biz.id/install

Contoh penggunaan:

bash <(curl -sL https://pterodactyl.putzoffc.biz.id/install)

Endpoint tersebut sebaiknya hanya mengirim script installer yang memang kamu kontrol.

---

📝 Logging

Installer menggunakan sistem logging untuk membantu troubleshooting.

Jika installer menyediakan "LOG_FILE", lokasi log dapat ditampilkan menggunakan:

echo "$LOG_FILE"

atau menggunakan fitur:

show_log_location

---

🔄 Updating

Jika repository diperbarui:

cd putz-installer
git pull

Kemudian:

chmod +x install.sh

Jalankan kembali:

./install.sh

---

🛠️ Development

Repository dibuat dengan konsep modular.

Jika ingin menambahkan fitur baru:

lib/
├── backup.sh
├── update.sh
├── theme.sh
├── firewall.sh
└── monitoring.sh

Kemudian integrasikan modul tersebut ke:

install.sh

---

🎨 Future Features

Rencana pengembangan:

- [ ] Pterodactyl Panel Installer
- [ ] Docker Installer
- [ ] Wings Installer
- [ ] Wings Uninstaller
- [ ] Full Uninstaller
- [ ] Health Check
- [ ] Backup System
- [ ] Restore System
- [ ] Panel Update
- [ ] Wings Update
- [ ] Firewall Manager
- [ ] Cloudflare Helper
- [ ] SSL Manager
- [ ] Theme Installer
- [ ] Automatic Node Configuration
- [ ] Monitoring
- [ ] Telegram Notification
- [ ] Interactive Configuration Wizard

---

📢 Support

Jika mengalami masalah, siapkan informasi:

cat /etc/os-release
uname -m

dan log:

journalctl -u wings -n 100 --no-pager

atau:

tail -n 100 /var/www/pterodactyl/storage/logs/laravel.log

Jangan kirim password, token, private key, atau credential.

---

👨‍💻 Developer

PutzOfficial

GitHub:

"https://github.com/rafswijdan80-cell"

Telegram:

"https://t.me/putzpay"

Channel:

"https://t.me/PutzPayOfficial"

Website:

"Tidak ada"

Installer:

"https://pterodactyl.putzoffc.biz.id/install"

«Ganti "USERNAME" dan "CHANNEL_USERNAME" dengan URL milik kamu sebelum repository dipublikasikan.»

---

📜 License

Project PutzOfficial Pterodactyl Installer menggunakan MIT License.

Lihat:

LICENSE.md

Pterodactyl merupakan proyek open-source terpisah dan memiliki lisensinya sendiri. Informasi lisensi Pterodactyl dapat dilihat pada repository resminya.

---

❤️ Credits

Dibuat dan dikembangkan oleh:

PutzOfficial

Dengan memanfaatkan berbagai proyek open-source dan teknologi yang tersedia di ekosistem Linux.

Terima kasih kepada:

- Pterodactyl
- Pterodactyl Wings
- Docker
- Nginx
- PHP
- MariaDB
- Redis
- Composer
- Let's Encrypt
- Ubuntu
- systemd

---

⚠️ Disclaimer

Installer ini disediakan "AS IS".

Administrator bertanggung jawab atas:

- VPS
- Data
- Backup
- Domain
- Credential
- Firewall
- Konfigurasi jaringan
- Penggunaan fitur uninstall

Selalu lakukan backup sebelum menjalankan operasi yang menghapus komponen sistem.

PutzOfficial tidak bertanggung jawab atas kehilangan data, downtime, kesalahan konfigurasi, atau kerusakan sistem akibat penggunaan installer ini.

---

⭐ Support the Project

Jika project ini membantu:

⭐ Star repository
🍴 Fork repository
🐛 Report bugs
💡 Submit suggestions
📢 Share project

---

© 2026 PutzOfficial — All Rights Reserved for the PutzOfficial Installer branding and original installer code.
