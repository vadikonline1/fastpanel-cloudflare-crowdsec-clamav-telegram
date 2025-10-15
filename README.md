# 🛡️ Hosting Automation & Security Suite

A comprehensive automation and security solution for web hosting environments featuring real-time monitoring, malware detection, and security protection.

## 🌟 Features

- **🔒 Security Protection**
  - CrowdSec intrusion detection system
  - Cloudflare firewall integration
  - Real-time threat blocking

- **🦠 Malware Protection** 
  - ClamAV real-time file monitoring
  - Scheduled daily security scans
  - Automatic quarantine of infected files

- **📁 File Monitoring**
  - Real-time file change detection
  - Immediate Telegram notifications
  - Intelligent exclusion of temporary files

- **📊 Reporting**
  - Daily security reports
  - Telegram notifications
  - Comprehensive logging

## 🚀 Quick Start

### Prerequisites
- Ubuntu/Debian system
- Root access
- Telegram bot (for notifications)

### Manual Quick Setup (4 commands)

```bash
# 1. Clone the repository
sudo git clone https://github.com/vadikonline1/fastpanel-cloudflare-crowdsec-clamav-telegram.git /etc/automation-web-hosting

# 2. Make all scripts executable
sudo chmod +x /etc/automation-web-hosting/*.sh

# 3. Navigate to directory and run installation
cd /etc/automation-web-hosting
sudo ./install-full-stack.sh

```

**Note: Edit the environment file and fill in the variables with real data:**
```bash
sudo nano /etc/automation-web-hosting/hosting_env.env
```

## 📋 Complete Installation

### Step 1: Clone Repository

```bash
sudo mkdir -p /etc/automation-web-hosting
cd /etc/automation-web-hosting
sudo git clone https://github.com/vadikonline1/fastpanel-cloudflare-crowdsec-clamav-telegram.git .
```

### Step 2: Make Scripts Executable

```bash
sudo chmod +x /etc/automation-web-hosting/*.sh
```

### Step 3: Configure Environment

```bash
cd /etc/automation-web-hosting
sudo nano hosting_env.env
```

**Required Configuration:**
```bash
# Telegram Configuration
TELEGRAM_BOT_TOKEN="your_bot_token_here"
TELEGRAM_CHAT_ID="your_chat_id_here"

# Cloudflare Configuration  
CF_API_TOKEN="your_cloudflare_token"
CF_ACCOUNT_ID="your_account_id"

# FastPanel
FASTPANEL_PASSWORD="secure_password"
```

### Step 4: Run Installation

```bash
cd /etc/automation-web-hosting
sudo ./install-full-stack.sh
```

### Step 5: Verify Installation

```bash
# Check service status
sudo systemctl status file-monitor.service
sudo systemctl status clamav-monitor.service
sudo systemctl status crowdsec-cloudflare-worker-bouncer

# Check logs
sudo tail -f /var/log/automation-hosting/file-monitor.log
```

## ⚙️ Configuration

### Environment Variables

All configuration is managed in `hosting_env.env`:

```bash
# Paths
BOUNCER_DIR="/etc/automation-web-hosting"
LOG_DIR="/var/log/automation-hosting"

# Monitoring Paths
MONITOR_PATHS="/var/www /etc/nginx /etc/apache2"
CLAMAV_MONITOR_PATHS="/var/www/uploads /tmp /var/www/tmp"

# Schedule
DAILY_SCAN_TIME="00:00"

# Security Features
ENABLE_FILE_MONITORING="true"
ENABLE_CLAMAV_MONITORING="true" 
ENABLE_DAILY_SCANS="true"
```

### Telegram Bot Setup

1. Create a bot with [@BotFather](https://t.me/BotFather)
2. Get your bot token
3. Start conversation with your bot
4. Get your chat ID using:
```bash
curl -s "https://api.telegram.org/bot<YOUR_BOT_TOKEN>/getUpdates"
```

## 🎯 Usage

### Manual Scans

```bash
# Run immediate ClamAV scan
sudo /etc/automation-web-hosting/clamav-daily.sh

# Check system status
sudo systemctl status file-monitor.service
sudo systemctl status clamav-monitor.service

# View recent security events
sudo tail -f /var/log/automation-hosting/file-monitor.log
```

### Service Management

```bash
# Start all services
sudo systemctl start file-monitor.service
sudo systemctl start clamav-monitor.service

# Stop services
sudo systemctl stop file-monitor.service

# Enable auto-start
sudo systemctl enable file-monitor.service
sudo systemctl enable clamav-monitor.service
```

### Monitoring Commands

```bash
# Check CrowdSec status
sudo cscli metrics

# View security decisions
sudo cscli decisions list

# Check ClamAV database
sudo freshclam

# Test Telegram notifications
sudo /etc/automation-web-hosting/telegram_notify.sh "Test message"
```

## 📁 File Structure

```
/etc/automation-web-hosting/
├── install-full-stack.sh          # Main installation script
├── hosting_env.env                # Configuration file
├── telegram_notify.sh             # Telegram notifications
├── setup_directories.sh           # Directory setup
├── setup_fastpanel.sh             # FastPanel installation
├── setup_crowdsec.sh              # CrowdSec setup
├── setup_cloudflare_bouncer.sh    # Cloudflare integration
├── setup_clamav.sh                # ClamAV configuration
├── clamav-onchange.sh             # Real-time monitoring
├── clamav-daily.sh                # Daily scans
└── logs/                          # Log directory
```

## 🔧 Troubleshooting

### Common Issues

**Telegram notifications not working:**
```bash
# Test Telegram configuration
sudo /etc/automation-web-hosting/telegram_notify.sh "Test message"

# Check token and chat ID
sudo grep "TELEGRAM" /etc/automation-web-hosting/hosting_env.env
```

**File monitor not starting:**
```bash
# Check service status
sudo systemctl status file-monitor.service
sudo journalctl -u file-monitor.service -f

# Verify inotify installation
sudo apt-get install inotify-tools
```

**ClamAV scan failures:**
```bash
# Update virus database
sudo freshclam

# Check ClamAV service
sudo systemctl status clamav-daemon

# Test manual scan
sudo clamscan --infected /var/www
```

### Log Files

- `/var/log/automation-hosting/file-monitor.log` - File changes
- `/var/log/automation-hosting/clamav-realtime.log` - Real-time scans
- `/var/log/automation-hosting/clamav-daily.log` - Daily scans
- `/var/log/automation-hosting/daily-report-*.log` - Daily reports

## 🛠️ Maintenance

### Update Procedures

```bash
# Update ClamAV database
sudo freshclam

# Update CrowdSec collections
sudo cscli hub update

# Restart all services
sudo systemctl restart file-monitor.service clamav-monitor.service
```

### Backup Configuration

```bash
# Backup entire configuration
sudo tar -czf hosting-automation-backup-$(date +%Y%m%d).tar.gz /etc/automation-web-hosting

# Restore configuration
sudo tar -xzf hosting-automation-backup-YYYYMMDD.tar.gz -C /
```

## 📊 Monitoring & Alerts

### What Gets Monitored

- **File Changes**: Creation, modification, deletion in web directories
- **Malware**: Real-time scanning of uploaded files
- **Security Events**: CrowdSec intrusion detection
- **System Health**: Service status and resource usage

### Alert Examples

🟢 **File Created**: `📄 File CREATE - /var/www/uploads/image.jpg`

🟠 **File Modified**: `✏️ File MODIFY - /etc/nginx/nginx.conf` 

🚨 **Malware Detected**: `🦠 THREAT: PHP.ShellBot - /var/www/tmp/shell.php`

📊 **Daily Report**: `✅ Daily scan: 15,342 files - 0 threats`

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🆘 Support

- 📧 Email: support@yourdomain.com
- 💬 Telegram: [@YourSupportBot](https://t.me/vadikonline1)
- 🐛 Issues: [GitHub Issues](https://github.com/vadikonline1/fastpanel-cloudflare-crowdsec-clamav-telegram/issues)

## 🔄 Changelog

### v1.0.0
- Initial release
- Real-time file monitoring
- ClamAV integration
- Telegram notifications
- CrowdSec protection

---

## ⚠️ Important Notes

**Note: Editează fișierul de mediu și completează variabilele cu date reale:**
```bash
sudo nano /etc/automation-web-hosting/hosting_env.env
```

Completează următoarele variabile obligatorii:
- `TELEGRAM_BOT_TOKEN` - Token-ul botului Telegram
- `TELEGRAM_CHAT_ID` - ID-ul chat-ului Telegram
- `CF_API_TOKEN` - Token-ul API Cloudflare
- `CF_ACCOUNT_ID` - ID-ul contului Cloudflare
- `FASTPANEL_PASSWORD` - Parola pentru FastPanel

Fără aceste variabile configurate corect, sistemul nu va funcționa proper!

---

**Warning**: Always test in a staging environment before deploying to production. Ensure you have proper backups before installation.
