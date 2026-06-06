# ??? O365 Enterprise & ADFS Auth Checker
<p align="center">
  <a href="#-one-click-installation-debianubuntu">
    <img src="https://img.shields.io/badge/⚡%20One--Click%20Install-Debian%20%7C%20Ubuntu-E95420?style=for-the-badge&logo=ubuntu&logoColor=white"/>
  </a>
  <a href="server.py">
    <img src="https://img.shields.io/badge/📦%20Single%20File-server.py-6C63FF?style=for-the-badge"/>
  </a>
  <a href="LICENSE">
    <img src="https://img.shields.io/badge/📝%20MIT-License-00C853?style=for-the-badge"/>
  </a>
</p>

| ⚡ Feature | 📋 Description |
|---|---|
| 🗂️ Single File | Entire app in one `server.py` |
| 📤 Chunked Uploads | Resume 5GB+ uploads seamlessly |
| 📁 Folder Drag & Drop | Recreates nested folder trees |
| 🎬 Media Preview | Streams video, audio, renders Markdown |
| 🔐 Let's Encrypt SSL | Built-in HTTPS, zero config |
| 👁️ Public Mode | Guest read-only without browser prompts |
| 🌙 Glassmorphic UI | Dark mode, mobile-friendly |

<p align="center">
  <img src="https://capsule-render.vercel.app/api?type=waving&color=gradient&customColorList=12,20,24&height=200&section=header&text=FileStation&fontSize=60&fontColor=ffffff&animation=twinkling&fontAlignY=35&desc=Lightning-fast%20Python%20web%20file%20manager&descAlignY=55&descSize=18"/>
</p>

A high-speed, cross-platform, asynchronous authentication checker for Microsoft 365 and Enterprise ADFS accounts. Built natively on Python and Playwright, this tool utilizes headless browser contexts to accurately mimic human logins, bypass standard behavioral blocks, and dynamically route federated university/corporate portals.

## ? Key Features

* **True Async Architecture:** Uses `asyncio` and Playwright contexts instead of heavy WebDriver instances. Checks multiple accounts concurrently using a single background Chromium process, reducing CPU/RAM usage by 80%.
* **Dynamic ADFS Routing:** Automatically detects federated domains and dynamically redirects to the correct university or corporate ADFS portal.
* **Smart Polling Engine:** Accurately classifies hits into `[VALID]`, `[ADFS_VALID]`, `[2FA]`, `[GEOLOCK]`, `[UPDATE_PWD]`, and `[LOCKED]`.
* **Cross-Platform Auto-Tuning:** Automatically detects if it is running on Windows or Linux (Debian/Ubuntu) and applies the correct native memory optimizations, console APIs, and sandboxing rules.
* **Live Telegram Dashboard:** Real-time checking statistics updated on a single pinned Telegram message.
* **Silent File Sync:** Automatically uploads and silently updates your `.txt` result files in Telegram every 60 seconds acting as an off-site backup.
* **Proxy Support:** Fully supports SOCKS5/HTTP proxies with IPAuth and UserAuth.

---

## ?? Installation & Setup

### 1. Prerequisites

Ensure you have Python 3.8 or higher installed on your system.

```bash
python --version

```

### 2. Install Dependencies

Clone the repository (or download the script) and install the required Python libraries.

```bash
pip install playwright colorama requests urllib3

```

### 3. Install Playwright Browsers

You must download the Playwright browser binaries for the script to run headless Chromium.

```bash
playwright install chromium

```

---

## ?? Configuration Files

Before running the script, ensure you have the following text files in the same directory as the script. The script will look for these automatically:

* `creds.txt` - Your email and password combinations. *(Format: `email:password`)*
* `proxies.txt` - Your proxy list. *(Format: `ip:port` or `ip:port:user:pass`)*

If you wish to use the **Telegram Live Dashboard**, the script will automatically generate a `tg_config.txt` file on its first run. You will need to paste your credentials there:

```text
BOT_TOKEN=1234567890:ABCdefGhIJKlmNoPQRstuVWXyz
CHAT_ID=123456789

```

---

## ?? Usage

Run the script from your terminal or command prompt:

```bash
python checker.py

```

Upon launching, the Interactive Setup will prompt you for:

1. **Concurrent Workers:** The number of accounts to check simultaneously (Default is 5. Recommended: 5-15 depending on proxy strength).
2. **Telegram Toggle:** `y` to enable the live dashboard and backups, `n` to run purely locally.

### ?? Output Structure

All processed accounts are automatically sorted and saved into a `Results/` directory generated in the same folder:

* `valid.txt` (Standard standard O365 hits)
* `adfs_valid.txt` (Enterprise/University federated hits)
* `2fa.txt` (Valid credentials, but requires MFA/Authenticator)
* `geolock.txt` (Account is restricted to a specific country/region)
* `update_pwd.txt` (Account requires a mandatory password reset)
* `locked.txt` (Account is temporarily locked or suspended)

---

## ?? Disclaimer

**For Educational and Authorized Testing Use Only.** This script is provided "as is" for security researchers and system administrators to audit their own enterprise infrastructure. The developer assumes no liability and is not responsible for any misuse or damage caused by this program. Do not use this tool against infrastructure you do not own or have explicit permission to test.
