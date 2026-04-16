<p align="center">
  <img src="https://img.shields.io/badge/Platform-Ubuntu%20%7C%20Debian-blue?style=for-the-badge&logo=linux&logoColor=white" alt="Platform">
  <img src="https://img.shields.io/badge/Language-Bash-green?style=for-the-badge&logo=gnubash&logoColor=white" alt="Language">
  <img src="https://img.shields.io/badge/Version-2.0.0-orange?style=for-the-badge" alt="Version">
  <img src="https://img.shields.io/badge/License-MIT-yellow?style=for-the-badge" alt="License">
</p>

<h1 align="center">MTProxy Installer & Manager</h1>

<p align="center">
  <strong>A professional, production-ready multi-instance Telegram MTProxy management tool.</strong>
  <br>
  Deploy, manage, and monitor multiple MTProxy services from a single interactive CLI.
</p>

> **⚠️ DISCLAIMER:** This project is provided **strictly for educational and research purposes only**. It is intended to help users learn about networking, proxy infrastructure, and system administration. **Do not use this tool for any illegal, unauthorized, or unethical activities.** Users are solely responsible for ensuring their usage complies with all applicable local, national, and international laws and regulations. The authors assume no liability for misuse of this software.

<p align="center">
  <a href="#-quick-start">Quick Start</a> •
  <a href="#-features">Features</a> •
  <a href="#-usage">Usage</a> •
  <a href="#%EF%B8%8F-architecture">Architecture</a> •
  <a href="#-cli-reference">CLI Reference</a> •
  <a href="#-faq">FAQ</a>
</p>

---

## 🚀 Quick Start

**One-line install** — run directly from GitHub:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/a9ii/MTProto-MTProxyInstaller/main/mtproxy-installer.sh)
```

Or download and run locally:

```bash
curl -fsSL -o mtproxy-installer.sh https://raw.githubusercontent.com/a9ii/MTProto-MTProxyInstaller/main/mtproxy-installer.sh
chmod +x mtproxy-installer.sh
sudo ./mtproxy-installer.sh
```

> **Requirements:** Ubuntu 18.04+ or Debian 10+ · Root access · `x86_64`, `aarch64`, or `armv7l`

---

## ✨ Features

### Multi-Instance Management
Create and manage **unlimited MTProxy services**, each with its own port, secret, domain, and optional promotion TAG — all from a single interactive menu.

### Professional Interactive UI
- **Whiptail / Dialog** interface with automatic **colored text fallback**
- Structured menus, validation prompts, and color-coded status messages
- Clean banner, separators, and formatted output tables

### Complete Lifecycle Management

| Capability | Description |
|:-----------|:------------|
| **Install / Update** | Clone, build, and configure MTProxy core — idempotent and safe to re-run |
| **Create Service** | Guided wizard with full input validation for every parameter |
| **Manage Service** | Start, stop, restart, enable/disable boot, view logs and stats |
| **List Services** | Formatted overview of all instances with status, ports, and links |
| **Connection Links** | Auto-generated `tg://` and `https://t.me/` links with optional Fake TLS |
| **Repair** | Auto-diagnose and fix binaries, configs, permissions, systemd, and UFW |
| **Delete / Uninstall** | Safe single-service removal or full uninstall with backup options |

### Built for Production

- `set -Eeuo pipefail` with proper `trap` handling
- Automatic `dpkg` / `apt` repair on dependency failures
- Pre-flight system validation (OS, arch, systemd, internet, DNS, URL reachability)
- Structured logging to `/var/log/mtproxy/installer.log`
- Port conflict detection across all instances
- Domain DNS resolution warnings
- ShellCheck-friendly code style

---

## 📖 Usage

### Interactive Mode

Run without arguments to enter the full interactive menu:

```bash
sudo ./mtproxy-installer.sh
```

```
+------------------------------------------+
|  MTProxy Installer & Manager v2.0.0   |
|  Telegram MTProxy Multi-Instance Tool    |
+------------------------------------------+

  1   Install / Update MTProxy Core
  2   Create New MTProxy Service
  3   List Existing Services
  4   Manage Existing Service
  5   Show Connection Links
  6   View Service Status / Logs / Stats
  7   Repair Installation
  8   Delete Service
  9   Full Uninstall
  0   Exit
```

### Service Creation Wizard

When creating a new service, the wizard will prompt for:

| Parameter | Description | Default |
|:----------|:------------|:--------|
| Service name | Unique identifier (e.g. `mtproxy-main`) | `mtproxy-main` |
| External port | Public-facing port | `443` |
| Domain | Domain or IP for connection links | — |
| Promotion TAG | Optional Telegram ad TAG (32 hex) | None |
| Secret | Custom or auto-generated (32 hex) | Auto-generated |
| Fake TLS | Enable `dd` prefix in links | No |
| Workers | CPU worker processes | CPU count |
| Stats port | Internal health-check port | `8888`+ |
| UFW rule | Open port in firewall | Yes |

### Service Management Submenu

Select any existing service to access:

```
  1   Start Service
  2   Stop Service
  3   Restart Service
  4   Enable at Boot
  5   Disable at Boot
  6   Show Status
  7   View Logs
  8   Show Configuration
  9   Show Connection Links
  10  Delete This Service
  0   <-- Back
```

---

## 🏗️ Architecture

### Directory Layout

```
/opt/MTProxy/                    # Core binary and proxy files
├── objs/bin/mtproto-proxy       # Compiled binary
├── proxy-secret                 # Telegram proxy secret
└── proxy-multi.conf             # Telegram proxy config

/etc/mtproxy/instances/          # Per-instance configuration
├── mtproxy-main.conf
├── mtproxy-eu.conf
└── mtproxy-us.conf

/etc/systemd/system/
└── mtproxy@.service             # Systemd template unit

/var/log/mtproxy/
└── installer.log                # Installer activity log
```

### Systemd Template Design

Uses a single **systemd template unit** (`mtproxy@.service`) with per-instance `EnvironmentFile`:

```ini
# /etc/systemd/system/mtproxy@.service
[Service]
EnvironmentFile=/etc/mtproxy/instances/%i.conf
ExecStart=/bin/bash -c '/opt/MTProxy/objs/bin/mtproto-proxy \
  -u mtproxy -p ${STATS_PORT} -H ${PORT} -S ${SECRET} \
  ${TAG:+-P ${TAG}} --aes-pwd /opt/MTProxy/proxy-secret \
  /opt/MTProxy/proxy-multi.conf -M ${WORKERS:-1} --http-stats'
```

This means `systemctl start mtproxy@myservice` automatically loads `/etc/mtproxy/instances/myservice.conf`.

---

## 📋 CLI Reference

| Command | Description |
|:--------|:------------|
| `./mtproxy-installer.sh` | Launch interactive menu |
| `./mtproxy-installer.sh --install` | Install or update MTProxy core |
| `./mtproxy-installer.sh --create` | Create a new service |
| `./mtproxy-installer.sh --list` | List all existing services |
| `./mtproxy-installer.sh --links` | Show connection links |
| `./mtproxy-installer.sh --status` | View service status and stats |
| `./mtproxy-installer.sh --repair` | Run repair diagnostics |
| `./mtproxy-installer.sh --uninstall` | Full uninstall |
| `./mtproxy-installer.sh --help` | Show help |

---

## 🔗 Connection Links

For each service, the script generates ready-to-share links:

**Standard:**
```
tg://proxy?server=example.com&port=443&secret=a4d9c2e8b1f6037ea5c8d4b29f1e6a0c
https://t.me/proxy?server=example.com&port=443&secret=a4d9c2e8b1f6037ea5c8d4b29f1e6a0c
```

**Fake TLS (if enabled):**
```
tg://proxy?server=example.com&port=443&secret=dda4d9c2e8b1f6037ea5c8d4b29f1e6a0c
```

---

## ❓ FAQ

<details>
<summary><strong>Can I run multiple instances on the same server?</strong></summary>

Yes. Each service gets its own port, secret, configuration file, and systemd unit. Create as many as you need through the interactive menu.
</details>

<details>
<summary><strong>What happens if the build fails?</strong></summary>

The script will display the last 5 lines of build output and exit cleanly. Use the **Repair** option to attempt automatic recovery, or check that `build-essential`, `libssl-dev`, and `zlib1g-dev` are properly installed.
</details>

<details>
<summary><strong>Is it safe to re-run the installer?</strong></summary>

Yes. The install/update flow is fully idempotent — it pulls updates if a repo exists, skips already-installed packages, and preserves existing service configurations.
</details>

<details>
<summary><strong>What is the Promotion TAG?</strong></summary>

It's a 32-character hex string from [@MTProxybot](https://t.me/MTProxybot) on Telegram. It enables sponsored channels on your proxy. It's entirely optional.
</details>

<details>
<summary><strong>What is Fake TLS / dd secret?</strong></summary>

Prefixing the secret with `dd` enables Fake TLS mode, which makes MTProxy traffic look like regular HTTPS to network filters. This can help bypass censorship.
</details>

---

## 🛡️ Security Notes

- The script must be run as **root** (required for systemd, UFW, and system user creation)
- SSH port `22/tcp` is always preserved in UFW rules
- The `mtproxy` system user runs with `nologin` shell and no home directory
- Secrets are stored in config files with root-only permissions

---

## ⚠️ Disclaimer

This project is developed and shared **exclusively for educational and research purposes**. It is meant to serve as a learning resource for understanding proxy technologies, Linux system administration, systemd service management, and Bash scripting.

**By using this software, you agree that:**

- You will **not** use it for any illegal, unauthorized, or unethical activities
- You will comply with all applicable laws and regulations in your jurisdiction
- You understand that the authors bear **no responsibility** for how this tool is used
- You acknowledge that circumventing network restrictions may be illegal in some regions

If you are unsure whether your intended use is lawful, **consult a legal professional** before proceeding.

---

## 📄 License

This project is licensed under the [MIT License](LICENSE).

---

<p align="center">
  <sub>Built for educational purposes — use responsibly</sub>
</p>
