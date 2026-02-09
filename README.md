# Smart Portal 🚀

**Smart Portal** is a professional-grade Captive Portal and Traffic Management appliance designed for Raspberry Pi (4 & 5). It transforms a standard Raspberry Pi into a powerful home router with enterprise-level features like voucher-based guest access, dynamic bandwidth throttling, and parental controls.

![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Platform](https://img.shields.io/badge/platform-Raspberry%20Pi-red.svg)
![Status](https://img.shields.io/badge/status-Production-green.svg)

## 🌟 Features

* **🔐 Captive Portal:** Intercepts all new connections and forces a login page (like a hotel or airport).
* **🎟️ Guest Vouchers:** Generate unique 1-time codes for guests (e.g., 4-hour access).
* **⚡ Dynamic Speed Limits:** Assign specific bandwidth limits (e.g., 5Mbps, 10Mbps, Unlimited) to specific users or devices instantly.
* **👶 Parental Controls:** Enforce "Bedtime" schedules. Devices are automatically kicked off the network outside allowed hours.
* **📱 Device Management:** Whitelist devices (Consoles, TVs, Phones) permanently so they don't need to log in repeatedly.
* **📊 Admin Dashboard:** Real-time view of connected users, active vouchers, and pending approvals.
* **🛡️ Security:** Uses standard Linux firewalls (`iptables`) and Traffic Control (`tc`) for robust enforcement.

## 🛠️ Tech Stack

* **Hardware:** Raspberry Pi 4 or 5
* **OS:** Raspberry Pi OS / Debian Bookworm or Trixie
* **Backend:** Node.js (Express), PostgreSQL (via Docker)
* **Networking:** Hostapd (AP Mode), Dnsmasq (DHCP/DNS), Iptables (Firewall)
* **Frontend:** EJS Templating, Bootstrap 5

## 📦 Installation

### Prerequisites
* A Raspberry Pi 4 or 5.
* A fresh install of Raspberry Pi OS Lite (64-bit recommended).
* Ethernet connection for the "Internet Source."

### Quick Start
1.  **Clone the Repository:**
    ```bash
    cd /opt
    sudo git clone [https://github.com/jjuhric/smart-portal.git](https://github.com/jjuhric/smart-portal.git)
    cd smart-portal
    ```

2.  **Configure Secrets:**
    Copy the example environment file and edit your passwords.
    ```bash
    cp .env.example .env
    nano .env
    ```
    *Set your `DB_PASS`, `SESSION_SECRET`, and `ADMIN_PASS` here.*

3.  **Run the Installer:**
    ```bash
    sudo bash install.sh
    ```
    *This script will install all dependencies (Docker, Node, etc.), configure the Wi-Fi Access Point, and initialize the database.*

4.  **Reboot:**
    ```bash
    sudo reboot
    ```

## 🖥️ Usage

### Connecting
1.  Connect to the Wi-Fi network: **Smart Home Wifi**
2.  A login popup should appear automatically. If not, visit: `http://home.local`

### Admin Login
* **URL:** `http://home.local`
* **Default User:** *(As configured in your .env)*
* **Default Pass:** *(As configured in your .env)*

Once logged in, navigating to `/admin` gives you full control over the network.

## 📂 Project Structure

```text
/opt/smart-portal/
├── config/             # Network configuration (hostapd, dnsmasq)
├── database/           # Database initialization scripts
├── src/                # Application Source Code
│   ├── server.js       # Main Express App
│   ├── firewall.js     # Iptables & TC Logic
│   └── startup.sh      # Boot sequence
├── views/              # Frontend Templates (EJS)
└── install.sh          # Main Installation Script