#!/usr/bin/env bash
# ============================================================================
#  MTProxy Installer & Manager v2.0
#  Professional Multi-Instance Telegram MTProxy Management Tool
#  For Ubuntu / Debian systems
# ============================================================================
set -Eeuo pipefail

# --- Global Constants -------------------------------------------------------
readonly SCRIPT_VERSION="2.0.2"
readonly MTPROXY_BASE="/opt/MTProxy"
readonly MTPROXY_BIN="${MTPROXY_BASE}/objs/bin/mtproto-proxy"
readonly MTPROXY_REPO="https://github.com/TelegramMessenger/MTProxy.git"
readonly PROXY_SECRET_URL="https://core.telegram.org/getProxySecret"
readonly PROXY_CONFIG_URL="https://core.telegram.org/getProxyConfig"
readonly INSTANCES_DIR="/etc/mtproxy/instances"
readonly LOG_DIR="/var/log/mtproxy"
readonly LOG_FILE="${LOG_DIR}/installer.log"
readonly SERVICE_TEMPLATE="mtproxy@.service"
readonly SYSCTL_CONF="/etc/sysctl.d/99-mtproxy.conf"
readonly MTPROXY_USER="mtproxy"
readonly MIN_PORT=1
readonly MAX_PORT=65535
readonly SECRET_LEN=32

# --- Color Palette -----------------------------------------------------------
if [[ -t 1 ]]; then
  readonly C_RESET=$'\033[0m'
  readonly C_BOLD=$'\033[1m'
  readonly C_DIM=$'\033[2m'
  readonly C_RED=$'\033[38;5;196m'
  readonly C_GREEN=$'\033[38;5;82m'
  readonly C_YELLOW=$'\033[38;5;220m'
  readonly C_BLUE=$'\033[38;5;39m'
  readonly C_CYAN=$'\033[38;5;87m'
  readonly C_MAGENTA=$'\033[38;5;213m'
  readonly C_WHITE=$'\033[38;5;255m'
  readonly C_GRAY=$'\033[38;5;245m'
else
  readonly C_RESET='' C_BOLD='' C_DIM=''
  readonly C_RED='' C_GREEN='' C_YELLOW='' C_BLUE=''
  readonly C_CYAN='' C_MAGENTA='' C_WHITE='' C_GRAY=''
fi

# --- UI Helpers --------------------------------------------------------------
_term_width() { tput cols 2>/dev/null || echo 80; }

draw_line() {
  local w
  w=$(_term_width)
  printf '%b' "${C_BLUE}"
  printf '%*s' "$w" '' | tr ' ' '='
  printf '%b\n' "${C_RESET}"
}

draw_line_thin() {
  local w
  w=$(_term_width)
  printf '%b' "${C_GRAY}"
  printf '%*s' "$w" '' | tr ' ' '-'
  printf '%b\n' "${C_RESET}"
}

center_text() {
  local text="$1" color="${2:-$C_WHITE}"
  local w pad
  w=$(_term_width)
  pad=$(( (w - ${#text}) / 2 ))
  (( pad < 0 )) && pad=0
  printf '%*s%b%s%b\n' "$pad" '' "$color" "$text" "$C_RESET"
}

# --- Logging -----------------------------------------------------------------
_log_ts() { date '+%Y-%m-%d %H:%M:%S'; }

_log_file() {
  if [[ -d "$LOG_DIR" ]]; then
    echo "[$(_log_ts)] $*" >> "$LOG_FILE" 2>/dev/null || true
  fi
}

log_info() {
  printf '  %b[INFO]%b  %s\n' "${C_BLUE}" "${C_RESET}" "$*"
  _log_file "INFO  $*"
}

log_success() {
  printf '  %b[ OK ]%b  %s\n' "${C_GREEN}" "${C_RESET}" "$*"
  _log_file "OK    $*"
}

log_warn() {
  printf '  %b[WARN]%b  %s\n' "${C_YELLOW}" "${C_RESET}" "$*"
  _log_file "WARN  $*"
}

log_error() {
  printf '  %b[FAIL]%b  %s\n' "${C_RED}" "${C_RESET}" "$*"
  _log_file "ERROR $*"
}

log_step() {
  printf '\n  %b>> %s%b\n' "${C_CYAN}${C_BOLD}" "$*" "${C_RESET}"
  _log_file "STEP  $*"
}

log_detail() {
  printf '    %b - %s%b\n' "${C_GRAY}" "$*" "${C_RESET}"
}

die() {
  log_error "$*"
  exit 1
}

# --- Trap / Cleanup ----------------------------------------------------------
_cleanup() {
  local ec=$?
  if (( ec != 0 )); then
    echo ""
    log_error "Script exited with code ${ec}."
    log_info  "Check ${LOG_FILE} for details."
  fi
}
trap _cleanup EXIT

# --- Root / System Checks ----------------------------------------------------
ensure_root() {
  if (( EUID != 0 )); then
    die "This script must be run as root. Use: sudo $0"
  fi
}

check_os() {
  log_step "Checking operating system"
  if [[ ! -f /etc/os-release ]]; then
    die "Cannot detect OS. /etc/os-release not found."
  fi
  local os_id os_pretty
  os_id=$(grep -oP '^\s*ID\s*=\s*\K.*' /etc/os-release | tr -d '"' | head -1)
  os_pretty=$(grep -oP '^\s*PRETTY_NAME\s*=\s*\K.*' /etc/os-release | tr -d '"' | head -1)
  os_id="${os_id,,}"
  case "$os_id" in
    ubuntu|debian) log_success "Detected ${os_pretty:-$os_id}" ;;
    *) die "Unsupported OS: ${os_id}. Only Ubuntu/Debian are supported." ;;
  esac
}

check_arch() {
  log_step "Checking architecture"
  local arch
  arch=$(uname -m)
  case "$arch" in
    x86_64|aarch64|armv7l) log_success "Architecture: ${arch}" ;;
    *) die "Unsupported architecture: ${arch}" ;;
  esac
}

check_systemd() {
  log_step "Checking systemd"
  if ! command -v systemctl &>/dev/null; then
    die "systemd is required but not found."
  fi
  log_success "systemd is available"
}

check_apt() {
  log_step "Checking apt package manager"
  if ! command -v apt-get &>/dev/null; then
    die "apt-get not found. Only Debian/Ubuntu are supported."
  fi
  log_success "apt is available"
}

check_internet() {
  log_step "Checking internet connectivity"
  local targets=("8.8.8.8" "1.1.1.1")
  for t in "${targets[@]}"; do
    if ping -c1 -W3 "$t" &>/dev/null; then
      log_success "Internet is reachable"
      return 0
    fi
  done
  die "No internet connectivity detected."
}

check_dns() {
  log_step "Checking DNS resolution"
  if getent hosts github.com &>/dev/null; then
    log_success "DNS resolution is working"
  elif host github.com &>/dev/null 2>&1; then
    log_success "DNS resolution is working"
  elif nslookup github.com &>/dev/null 2>&1; then
    log_success "DNS resolution is working"
  else
    log_warn "DNS resolution may not be working. Will attempt to continue."
  fi
}

check_urls_reachable() {
  log_step "Checking required URLs"
  local urls=("https://github.com" "$PROXY_SECRET_URL" "$PROXY_CONFIG_URL")
  local all_ok=true
  for u in "${urls[@]}"; do
    if curl -fsSL --connect-timeout 10 --max-time 15 -o /dev/null "$u" 2>/dev/null; then
      log_detail "Reachable: ${u}"
    else
      log_warn "Cannot reach: ${u}"
      all_ok=false
    fi
  done
  if [[ "$all_ok" == "false" ]]; then
    log_warn "Some URLs are not reachable. Installation may fail."
  else
    log_success "All required URLs are reachable"
  fi
}

repair_apt() {
  log_step "Repairing package manager"
  dpkg --configure -a 2>/dev/null || true
  apt-get --fix-broken install -y 2>/dev/null || true
  apt-get update -y 2>/dev/null || true
  log_success "Package manager repair attempted"
}

install_dependencies() {
  log_step "Installing required packages"
  local pkgs=(git curl build-essential libssl-dev zlib1g-dev)
  local missing=()
  for p in "${pkgs[@]}"; do
    if ! dpkg -s "$p" &>/dev/null; then
      missing+=("$p")
    fi
  done
  if ! command -v whiptail &>/dev/null && ! command -v dialog &>/dev/null; then
    missing+=("whiptail")
  fi
  if ! command -v host &>/dev/null && ! command -v nslookup &>/dev/null; then
    if ! command -v getent &>/dev/null; then
      missing+=("dnsutils")
    fi
  fi
  if (( ${#missing[@]} == 0 )); then
    log_success "All dependencies are already installed"
    return 0
  fi
  log_info "Installing: ${missing[*]}"
  if ! apt-get update -y &>/dev/null; then
    log_warn "apt update failed, attempting repair..."
    repair_apt
  fi
  if ! apt-get install -y "${missing[@]}" &>/dev/null; then
    repair_apt
    apt-get install -y "${missing[@]}" || die "Failed to install: ${missing[*]}"
  fi
  log_success "Dependencies installed successfully"
}

run_system_checks() {
  echo ""
  draw_line
  center_text "SYSTEM VALIDATION" "${C_CYAN}${C_BOLD}"
  draw_line
  echo ""
  ensure_root
  check_os
  check_arch
  check_systemd
  check_apt
  check_internet
  check_dns
  check_urls_reachable
  install_dependencies
  mkdir -p "$INSTANCES_DIR" "$LOG_DIR"
  echo ""
  draw_line_thin
  log_success "All system checks passed"
  draw_line_thin
  echo ""
}

# --- Banner ------------------------------------------------------------------
show_banner() {
  clear 2>/dev/null || true
  echo ""
  draw_line
  echo ""
  center_text "+------------------------------------------+" "${C_CYAN}"
  center_text "|  MTProxy Installer & Manager v${SCRIPT_VERSION}   |" "${C_CYAN}${C_BOLD}"
  center_text "|  Telegram MTProxy Multi-Instance Tool    |" "${C_CYAN}"
  center_text "|              Github A9ii                 |" "${C_CYAN}"
  center_text "+------------------------------------------+" "${C_CYAN}"
  echo ""
  draw_line
  center_text "Professional Multi-Service Management" "${C_GRAY}"
  echo ""
}

# --- UI Mode Detection -------------------------------------------------------
HAS_WHIPTAIL=false
HAS_DIALOG=false

detect_ui() {
  command -v whiptail &>/dev/null && HAS_WHIPTAIL=true || true
  command -v dialog   &>/dev/null && HAS_DIALOG=true   || true
}

# --- Whiptail / Dialog / Fallback Menu ---------------------------------------
# $1=title $2=prompt $3..=tag/item pairs
ui_menu() {
  local title="$1" prompt="$2"
  shift 2
  local -a items=("$@")
  local choice

  if $HAS_WHIPTAIL; then
    choice=$(whiptail --title "$title" --menu "$prompt" 22 76 12 "${items[@]}" 3>&1 1>&2 2>&3) || return 1
    echo "$choice"
  elif $HAS_DIALOG; then
    choice=$(dialog --stdout --title "$title" --menu "$prompt" 22 76 12 "${items[@]}") || return 1
    echo "$choice"
  else
    _fallback_menu "$title" "$prompt" "${items[@]}"
  fi
}

_fallback_menu() {
  local title="$1" prompt="$2"
  shift 2
  local -a items=("$@")

  echo ""
  draw_line
  center_text "$title" "${C_CYAN}${C_BOLD}"
  draw_line
  echo ""
  printf '  %b%s%b\n\n' "${C_WHITE}" "$prompt" "${C_RESET}"

  local i=0 tag desc
  local -a tags=()
  while (( i < ${#items[@]} )); do
    tag="${items[$i]}"
    desc="${items[$((i+1))]}"
    tags+=("$tag")
    printf '    %b%-4s%b  %s\n' "${C_GREEN}${C_BOLD}" "$tag" "${C_RESET}" "$desc"
    (( i += 2 ))
  done

  echo ""
  draw_line_thin
  local choice
  while true; do
    printf '  %b>> Enter choice:%b ' "${C_YELLOW}" "${C_RESET}"
    read -r choice
    for t in "${tags[@]}"; do
      if [[ "$choice" == "$t" ]]; then
        echo "$choice"
        return 0
      fi
    done
    log_warn "Invalid choice: ${choice}"
  done
}

ui_yesno() {
  local title="$1" prompt="$2"
  if $HAS_WHIPTAIL; then
    whiptail --title "$title" --yesno "$prompt" 10 60 && return 0 || return 1
  elif $HAS_DIALOG; then
    dialog --stdout --title "$title" --yesno "$prompt" 10 60 && return 0 || return 1
  else
    local ans
    printf '\n  %b%s%b\n' "${C_YELLOW}" "$prompt" "${C_RESET}"
    printf '  %b(y/n):%b ' "${C_CYAN}" "${C_RESET}"
    read -r ans
    [[ "${ans,,}" == "y" || "${ans,,}" == "yes" ]]
  fi
}

ui_input() {
  local title="$1" prompt="$2" default="${3:-}"
  local result
  if $HAS_WHIPTAIL; then
    result=$(whiptail --title "$title" --inputbox "$prompt" 10 60 "$default" 3>&1 1>&2 2>&3) || return 1
    echo "$result"
  elif $HAS_DIALOG; then
    result=$(dialog --stdout --title "$title" --inputbox "$prompt" 10 60 "$default") || return 1
    echo "$result"
  else
    printf '\n  %b%s%b' "${C_CYAN}" "$prompt" "${C_RESET}"
    if [[ -n "$default" ]]; then
      printf ' %b[%s]%b' "${C_GRAY}" "$default" "${C_RESET}"
    fi
    printf ': '
    read -r result
    [[ -z "$result" ]] && result="$default"
    echo "$result"
  fi
}

ui_msgbox() {
  local title="$1" msg="$2"
  if $HAS_WHIPTAIL; then
    whiptail --title "$title" --msgbox "$msg" 15 70
  elif $HAS_DIALOG; then
    dialog --title "$title" --msgbox "$msg" 15 70
  else
    echo ""
    draw_line_thin
    center_text "$title" "${C_CYAN}${C_BOLD}"
    draw_line_thin
    echo ""
    printf '  %s\n' "$msg"
    echo ""
    printf '  %bPress Enter to continue...%b' "${C_GRAY}" "${C_RESET}"
    read -r
  fi
}

# --- Validation Helpers -------------------------------------------------------
validate_service_name() {
  local name="$1"
  if [[ -z "$name" ]]; then
    echo "Service name cannot be empty"; return 1
  fi
  if [[ ! "$name" =~ ^[a-zA-Z][a-zA-Z0-9_-]*$ ]]; then
    echo "Invalid name. Use letters, digits, hyphens, underscores. Must start with a letter."; return 1
  fi
  if (( ${#name} > 48 )); then
    echo "Name too long (max 48 chars)"; return 1
  fi
  if [[ -f "${INSTANCES_DIR}/${name}.conf" ]]; then
    echo "Service '${name}' already exists"; return 1
  fi
  echo "ok"
}

validate_port() {
  local port="$1"
  if [[ ! "$port" =~ ^[0-9]+$ ]]; then
    echo "Port must be a number"; return 0
  fi
  if (( port < MIN_PORT || port > MAX_PORT )); then
    echo "Port must be between ${MIN_PORT} and ${MAX_PORT}"; return 0
  fi
  echo "ok"
}

is_port_in_use() {
  local port="$1"
  ss -tlnp 2>/dev/null | grep -q ":${port} " && return 0
  return 1
}

is_port_used_by_instance() {
  local port="$1" skip="${2:-}"
  local f fname
  for f in "${INSTANCES_DIR}"/*.conf; do
    [[ -f "$f" ]] || continue
    fname=$(basename "$f" .conf)
    [[ "$fname" == "$skip" ]] && continue
    (
      # shellcheck disable=SC1090
      source "$f"
      if [[ "${PORT:-}" == "$port" || "${STATS_PORT:-}" == "$port" ]]; then
        exit 0
      fi
      exit 1
    ) && return 0
  done
  return 1
}

validate_hex() {
  local val="$1" expected_len="$2"
  if [[ ! "$val" =~ ^[0-9a-fA-F]+$ ]]; then
    echo "Must be valid hexadecimal"; return 0
  fi
  if (( ${#val} != expected_len )); then
    echo "Must be exactly ${expected_len} hex characters"; return 0
  fi
  echo "ok"
}

validate_domain() {
  local domain="$1"
  if [[ -z "$domain" ]]; then
    echo "Domain cannot be empty"; return 0
  fi
  if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9._-]*[a-zA-Z0-9])?$ ]]; then
    echo "Invalid domain format"; return 0
  fi
  echo "ok"
}

generate_secret() {
  openssl rand -hex 16
}

find_free_stats_port() {
  local port=8888
  while (( port < 9999 )); do
    if ! is_port_in_use "$port" && ! is_port_used_by_instance "$port"; then
      echo "$port"
      return 0
    fi
    (( port++ ))
  done
  echo "9500"
}

# --- Instance Config Helpers -------------------------------------------------
list_instances() {
  local -a instances=()
  local f
  for f in "${INSTANCES_DIR}"/*.conf; do
    [[ -f "$f" ]] || continue
    instances+=("$(basename "$f" .conf)")
  done
  if (( ${#instances[@]} > 0 )); then
    echo "${instances[*]}"
  fi
}

load_instance_config() {
  local name="$1"
  local conf="${INSTANCES_DIR}/${name}.conf"
  if [[ ! -f "$conf" ]]; then
    return 1
  fi
  # shellcheck disable=SC1090
  source "$conf"
}

get_service_unit_name() {
  local name="$1"
  echo "mtproxy@${name}.service"
}

get_service_status() {
  local name="$1"
  local unit
  unit=$(get_service_unit_name "$name")
  if systemctl is-active --quiet "$unit" 2>/dev/null; then
    echo "Running"
  elif systemctl is-failed --quiet "$unit" 2>/dev/null; then
    echo "Failed"
  else
    echo "Stopped"
  fi
}

is_service_enabled() {
  local name="$1"
  local unit
  unit=$(get_service_unit_name "$name")
  systemctl is-enabled --quiet "$unit" 2>/dev/null && return 0 || return 1
}

pause_prompt() {
  echo ""
  printf '  %bPress Enter to continue...%b' "${C_GRAY}" "${C_RESET}"
  read -r
}

# --- Install / Update MTProxy Core ------------------------------------------
install_core() {
  echo ""
  draw_line
  center_text "INSTALL / UPDATE MTPROXY CORE" "${C_CYAN}${C_BOLD}"
  draw_line
  echo ""

  # Create system user
  log_step "Creating system user"
  if id -u "$MTPROXY_USER" &>/dev/null; then
    log_success "User '${MTPROXY_USER}' already exists"
  else
    useradd -r -s /usr/sbin/nologin "$MTPROXY_USER"
    log_success "Created user '${MTPROXY_USER}'"
  fi

  # Clone or update repository
  log_step "Setting up MTProxy source"
  if [[ -d "${MTPROXY_BASE}/.git" ]]; then
    log_info "Existing repository found, updating..."
    if git -C "$MTPROXY_BASE" pull --ff-only 2>/dev/null; then
      log_success "Repository updated"
    else
      log_warn "Pull failed, attempting fresh clone..."
      local backup="/opt/MTProxy.bak.$(date +%s)"
      mv "$MTPROXY_BASE" "$backup"
      log_info "Backed up old directory to ${backup}"
      git clone "$MTPROXY_REPO" "$MTPROXY_BASE"
      log_success "Fresh clone completed"
    fi
  else
    if [[ -d "$MTPROXY_BASE" ]]; then
      rm -rf "$MTPROXY_BASE"
    fi
    git clone "$MTPROXY_REPO" "$MTPROXY_BASE"
    log_success "Repository cloned"
  fi

  # Build
  log_step "Building MTProxy"
  if ! make -C "$MTPROXY_BASE" -j"$(nproc)" 2>&1 | tail -5; then
    die "Build failed. Check build output above."
  fi
  if [[ ! -x "$MTPROXY_BIN" ]]; then
    die "Binary not found after build: ${MTPROXY_BIN}"
  fi
  log_success "Build completed successfully"

  # Download proxy files
  log_step "Downloading proxy configuration files"
  if curl -fsSL --connect-timeout 10 -o "${MTPROXY_BASE}/proxy-secret" "$PROXY_SECRET_URL"; then
    log_success "Downloaded proxy-secret"
  else
    die "Failed to download proxy-secret"
  fi
  if curl -fsSL --connect-timeout 10 -o "${MTPROXY_BASE}/proxy-multi.conf" "$PROXY_CONFIG_URL"; then
    log_success "Downloaded proxy-multi.conf"
  else
    die "Failed to download proxy-multi.conf"
  fi

  # Permissions
  log_step "Setting permissions"
  chown -R root:root "$MTPROXY_BASE"
  chmod 755 "$MTPROXY_BIN"
  log_success "Permissions set"

  # Sysctl
  log_step "Applying sysctl settings"
  cat > "$SYSCTL_CONF" <<'SYSCTL'
kernel.pid_max = 65535
net.ipv4.tcp_window_scaling = 1
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
SYSCTL
  sysctl --system &>/dev/null || true
  log_success "Sysctl settings applied"

  # Systemd template
  log_step "Installing systemd service template"
  install_service_template
  log_success "Service template installed"

  # Directories
  mkdir -p "$INSTANCES_DIR" "$LOG_DIR"

  echo ""
  draw_line_thin
  log_success "MTProxy core installation complete!"
  draw_line_thin
  echo ""
  pause_prompt
}

install_service_template() {
  cat > "/etc/systemd/system/${SERVICE_TEMPLATE}" <<'UNIT'
[Unit]
Description=Telegram MTProxy - %i
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
EnvironmentFile=/etc/mtproxy/instances/%i.conf
WorkingDirectory=/opt/MTProxy
ExecStart=/bin/bash -c '/opt/MTProxy/objs/bin/mtproto-proxy \
  -u mtproxy \
  -p ${STATS_PORT} \
  -H ${PORT} \
  -S ${SECRET} \
  ${TAG:+-P ${TAG}} \
  --aes-pwd /opt/MTProxy/proxy-secret \
  /opt/MTProxy/proxy-multi.conf \
  -M ${WORKERS:-1} \
  --http-stats'
Restart=always
RestartSec=5
LimitNOFILE=65536
StandardOutput=journal
StandardError=journal
SyslogIdentifier=mtproxy-%i

[Install]
WantedBy=multi-user.target
UNIT
  systemctl daemon-reload
}

# --- Create New Service ------------------------------------------------------
create_service() {
  echo ""
  draw_line
  center_text "CREATE NEW MTPROXY SERVICE" "${C_CYAN}${C_BOLD}"
  draw_line
  echo ""

  # Check core installation
  if [[ ! -x "$MTPROXY_BIN" ]]; then
    log_error "MTProxy core is not installed."
    if ui_yesno "Install Core" "MTProxy core is not installed. Install now?"; then
      install_core
    else
      return 0
    fi
  fi

  # Ensure template exists
  if [[ ! -f "/etc/systemd/system/${SERVICE_TEMPLATE}" ]]; then
    install_service_template
  fi

  local svc_name="" port="" domain="" secret="" tag="" stats_port=""
  local use_faketls="no"
  local workers="1" open_ufw="yes"

  # -- Service Name --
  while true; do
    svc_name=$(ui_input "Service Name" "Enter a unique service name (e.g. mtproxy-main)" "mtproxy-main") || return 0
    local v
    v=$(validate_service_name "$svc_name") || true
    if [[ "$v" == "ok" ]]; then break; fi
    ui_msgbox "Invalid Name" "$v"
  done

  # -- Port --
  while true; do
    port=$(ui_input "External Port" "Enter the external port for this service" "443") || return 0
    local v
    v=$(validate_port "$port")
    if [[ "$v" != "ok" ]]; then
      ui_msgbox "Invalid Port" "$v"; continue
    fi
    if is_port_used_by_instance "$port"; then
      ui_msgbox "Port Conflict" "Port ${port} is already used by another MTProxy instance."; continue
    fi
    if is_port_in_use "$port"; then
      if ! ui_yesno "Port In Use" "Port ${port} is currently in use by another process. Continue anyway?"; then
        continue
      fi
    fi
    break
  done

  # -- Domain --
  while true; do
    domain=$(ui_input "Domain" "Enter the domain or IP for connection links" "") || return 0
    local v
    v=$(validate_domain "$domain")
    if [[ "$v" == "ok" ]]; then break; fi
    ui_msgbox "Invalid Domain" "$v"
  done

  # DNS check for domain
  local server_ip=""
  server_ip=$(curl -4fsSL --connect-timeout 5 https://api.ipify.org 2>/dev/null) || true
  if [[ -n "$server_ip" ]]; then
    local domain_ip=""
    domain_ip=$(getent hosts "$domain" 2>/dev/null | awk '{print $1; exit}') || true
    if [[ -n "$domain_ip" && "$domain_ip" != "$server_ip" ]]; then
      log_warn "Domain '${domain}' resolves to ${domain_ip}, but this server is ${server_ip}"
      log_warn "Connection links may not work unless the domain points to this server."
    fi
  fi

  # -- TAG --
  tag=""
  if ui_yesno "Promotion TAG" "Do you want to use a Telegram Promotion TAG? (Select No if you don't have one)"; then
    while true; do
      tag=$(ui_input "TAG" "Enter your Promotion TAG (32 hex characters)" "") || return 0
      local v
      v=$(validate_hex "$tag" 32)
      if [[ "$v" == "ok" ]]; then break; fi
      ui_msgbox "Invalid TAG" "$v"
    done
  fi

  # -- Secret --
  if ui_yesno "Custom Secret" "Do you want to enter a custom Secret? (No = auto-generate)"; then
    while true; do
      secret=$(ui_input "Secret" "Enter your Secret (32 hex characters)" "") || return 0
      local v
      v=$(validate_hex "$secret" "$SECRET_LEN")
      if [[ "$v" == "ok" ]]; then break; fi
      ui_msgbox "Invalid Secret" "$v"
    done
  else
    secret=$(generate_secret)
    log_success "Auto-generated secret: ${secret}"
  fi

  # -- Fake TLS --
  if ui_yesno "Fake TLS" "Enable Fake TLS (dd prefix) in connection links?"; then
    use_faketls="yes"
  fi

  # -- Workers --
  local cpu_count
  cpu_count=$(nproc)
  workers=$(ui_input "Workers" "Number of worker processes (recommended: ${cpu_count})" "$cpu_count") || return 0
  if [[ ! "$workers" =~ ^[0-9]+$ ]] || (( workers < 1 )); then
    workers=1
  fi

  # -- Stats Port --
  local default_stats
  default_stats=$(find_free_stats_port)
  stats_port=$(ui_input "Stats Port" "Internal stats port (for health checks)" "$default_stats") || return 0
  if [[ ! "$stats_port" =~ ^[0-9]+$ ]]; then
    stats_port="$default_stats"
  fi
  if is_port_used_by_instance "$stats_port"; then
    log_warn "Stats port ${stats_port} conflicts, finding alternative..."
    stats_port=$(find_free_stats_port)
  fi

  # -- UFW --
  if command -v ufw &>/dev/null; then
    if ! ui_yesno "Firewall" "Open port ${port}/tcp in UFW?"; then
      open_ufw="no"
    fi
  else
    open_ufw="skip"
  fi

  # -- Confirm --
  local confirm_msg="Service: ${svc_name}
Port: ${port}
Domain: ${domain}
Secret: ${secret}
TAG: ${tag:-None}
Fake TLS: ${use_faketls}
Workers: ${workers}
Stats Port: ${stats_port}
UFW: ${open_ufw}"

  if ! ui_yesno "Confirm Creation" "$confirm_msg"; then
    log_info "Service creation cancelled."
    return 0
  fi

  # -- Write Config --
  log_step "Creating service configuration"
  cat > "${INSTANCES_DIR}/${svc_name}.conf" <<EOF
# MTProxy Instance Configuration: ${svc_name}
# Generated: $(date -Iseconds)
PORT=${port}
SECRET=${secret}
TAG=${tag}
DOMAIN=${domain}
STATS_PORT=${stats_port}
WORKERS=${workers}
FAKE_TLS=${use_faketls}
EOF
  log_success "Configuration saved: ${INSTANCES_DIR}/${svc_name}.conf"

  # -- UFW --
  if [[ "$open_ufw" == "yes" ]]; then
    log_step "Configuring firewall"
    ufw allow "${port}/tcp" &>/dev/null || true
    ufw allow 22/tcp &>/dev/null || true
    ufw --force enable &>/dev/null || true
    log_success "UFW rule added for port ${port}/tcp"
  fi

  # -- Enable & Start --
  log_step "Starting service"
  local unit
  unit=$(get_service_unit_name "$svc_name")
  systemctl daemon-reload
  systemctl enable "$unit" &>/dev/null || true
  systemctl restart "$unit" || true

  # Verify
  sleep 3
  local status
  status=$(get_service_status "$svc_name")
  if [[ "$status" == "Running" ]]; then
    log_success "Service '${svc_name}' is running!"
  else
    log_error "Service '${svc_name}' failed to start."
    log_info "Check: journalctl -u ${unit} --no-pager -n 30"
  fi

  # Stats test
  if curl -sf "localhost:${stats_port}/stats" &>/dev/null; then
    log_success "Stats endpoint responding on port ${stats_port}"
  else
    log_warn "Stats endpoint not yet responding (may need a moment)"
  fi

  # -- Summary --
  echo ""
  draw_line
  center_text "SERVICE CREATED SUCCESSFULLY" "${C_GREEN}${C_BOLD}"
  draw_line
  echo ""
  show_instance_summary "$svc_name"

  pause_prompt
}

# --- Connection Links --------------------------------------------------------
generate_links() {
  local domain="$1" port="$2" secret="$3" faketls="${4:-no}"
  echo ""
  printf '  %b+--- Connection Links -----------------------------------+%b\n' "${C_BLUE}" "${C_RESET}"
  printf '  %b|%b\n' "${C_BLUE}" "${C_RESET}"
  printf '  %b|%b  %bStandard Link:%b\n' "${C_BLUE}" "${C_RESET}" "${C_BOLD}" "${C_RESET}"
  printf '  %b|%b  tg://proxy?server=%s&port=%s&secret=%s\n' "${C_BLUE}" "${C_RESET}" "$domain" "$port" "$secret"
  printf '  %b|%b\n' "${C_BLUE}" "${C_RESET}"
  printf '  %b|%b  %bWeb Link:%b\n' "${C_BLUE}" "${C_RESET}" "${C_BOLD}" "${C_RESET}"
  printf '  %b|%b  https://t.me/proxy?server=%s&port=%s&secret=%s\n' "${C_BLUE}" "${C_RESET}" "$domain" "$port" "$secret"

  if [[ "$faketls" == "yes" ]]; then
    printf '  %b|%b\n' "${C_BLUE}" "${C_RESET}"
    printf '  %b|%b  %bFake TLS Link:%b\n' "${C_BLUE}" "${C_RESET}" "${C_BOLD}${C_MAGENTA}" "${C_RESET}"
    printf '  %b|%b  tg://proxy?server=%s&port=%s&secret=dd%s\n' "${C_BLUE}" "${C_RESET}" "$domain" "$port" "$secret"
    printf '  %b|%b  https://t.me/proxy?server=%s&port=%s&secret=dd%s\n' "${C_BLUE}" "${C_RESET}" "$domain" "$port" "$secret"
  fi
  printf '  %b|%b\n' "${C_BLUE}" "${C_RESET}"
  printf '  %b+--------------------------------------------------------+%b\n' "${C_BLUE}" "${C_RESET}"
}

show_instance_summary() {
  local name="$1"
  (
    local PORT="" SECRET="" TAG="" DOMAIN="" STATS_PORT="" WORKERS="" FAKE_TLS=""
    load_instance_config "$name" || { echo "  Config not found for ${name}"; exit 0; }
    local status
    status=$(get_service_status "$name")
    local enabled="No"
    is_service_enabled "$name" && enabled="Yes"

    local status_color="$C_RED"
    [[ "$status" == "Running" ]] && status_color="$C_GREEN"
    [[ "$status" == "Stopped" ]] && status_color="$C_YELLOW"

    printf '  %b+--- Service: %-40s ---+%b\n' "${C_CYAN}" "$name" "${C_RESET}"
    printf '  %b|%b  %-16s %b%-30s%b     %b|%b\n' "${C_CYAN}" "${C_RESET}" "Status:" "$status_color" "$status" "${C_RESET}" "${C_CYAN}" "${C_RESET}"
    printf '  %b|%b  %-16s %-30s     %b|%b\n' "${C_CYAN}" "${C_RESET}" "Port:" "$PORT" "${C_CYAN}" "${C_RESET}"
    printf '  %b|%b  %-16s %-30s     %b|%b\n' "${C_CYAN}" "${C_RESET}" "Domain:" "$DOMAIN" "${C_CYAN}" "${C_RESET}"
    printf '  %b|%b  %-16s %-30s     %b|%b\n' "${C_CYAN}" "${C_RESET}" "Secret:" "$SECRET" "${C_CYAN}" "${C_RESET}"
    printf '  %b|%b  %-16s %-30s     %b|%b\n' "${C_CYAN}" "${C_RESET}" "TAG:" "${TAG:-None}" "${C_CYAN}" "${C_RESET}"
    printf '  %b|%b  %-16s %-30s     %b|%b\n' "${C_CYAN}" "${C_RESET}" "Workers:" "${WORKERS:-1}" "${C_CYAN}" "${C_RESET}"
    printf '  %b|%b  %-16s %-30s     %b|%b\n' "${C_CYAN}" "${C_RESET}" "Stats Port:" "$STATS_PORT" "${C_CYAN}" "${C_RESET}"
    printf '  %b|%b  %-16s %-30s     %b|%b\n' "${C_CYAN}" "${C_RESET}" "Fake TLS:" "${FAKE_TLS:-no}" "${C_CYAN}" "${C_RESET}"
    printf '  %b|%b  %-16s %-30s     %b|%b\n' "${C_CYAN}" "${C_RESET}" "Boot Enabled:" "$enabled" "${C_CYAN}" "${C_RESET}"
    printf '  %b+--------------------------------------------------------+%b\n' "${C_CYAN}" "${C_RESET}"

    generate_links "$DOMAIN" "$PORT" "$SECRET" "${FAKE_TLS:-no}"
  )
}

# --- List Existing Services --------------------------------------------------
list_services() {
  echo ""
  draw_line
  center_text "EXISTING MTPROXY SERVICES" "${C_CYAN}${C_BOLD}"
  draw_line
  echo ""

  local instances
  instances=$(list_instances)
  if [[ -z "$instances" ]]; then
    log_info "No services found."
    pause_prompt
    return 0
  fi

  local name
  for name in $instances; do
    show_instance_summary "$name"
    echo ""
  done

  pause_prompt
}

# --- Select Instance ---------------------------------------------------------
select_instance() {
  local instances
  instances=$(list_instances)
  if [[ -z "$instances" ]]; then
    log_info "No services found."
    return 1
  fi

  local -a menu_items=()
  local name status
  for name in $instances; do
    status=$(get_service_status "$name")
    menu_items+=("$name" "[${status}]")
  done

  local choice
  choice=$(ui_menu "Select Service" "Choose a service to manage:" "${menu_items[@]}") || return 1
  echo "$choice"
}

# --- Manage Existing Service -------------------------------------------------
manage_service() {
  local name
  name=$(select_instance) || { pause_prompt; return 0; }

  while true; do
    local status unit
    status=$(get_service_status "$name")
    unit=$(get_service_unit_name "$name")

    local choice
    choice=$(ui_menu "Manage: ${name} [${status}]" "Select action:" \
      "1" "Start Service" \
      "2" "Stop Service" \
      "3" "Restart Service" \
      "4" "Enable at Boot" \
      "5" "Disable at Boot" \
      "6" "Show Status" \
      "7" "View Logs" \
      "8" "Show Configuration" \
      "9" "Show Connection Links" \
      "10" "Delete This Service" \
      "0" "<-- Back to Main Menu" \
    ) || return 0

    case "$choice" in
      1)
        systemctl start "$unit" && log_success "Started ${name}" || log_error "Failed to start ${name}"
        sleep 1 ;;
      2)
        systemctl stop "$unit" && log_success "Stopped ${name}" || log_error "Failed to stop ${name}"
        sleep 1 ;;
      3)
        systemctl restart "$unit" && log_success "Restarted ${name}" || log_error "Failed to restart ${name}"
        sleep 2 ;;
      4)
        systemctl enable "$unit" &>/dev/null && log_success "Enabled ${name} at boot" || log_error "Failed"
        sleep 1 ;;
      5)
        systemctl disable "$unit" &>/dev/null && log_success "Disabled ${name} at boot" || log_error "Failed"
        sleep 1 ;;
      6)
        echo ""
        draw_line_thin
        systemctl --no-pager --full status "$unit" 2>/dev/null | head -20 || true
        draw_line_thin
        local stats_p=""
        stats_p=$(source "${INSTANCES_DIR}/${name}.conf" 2>/dev/null && echo "${STATS_PORT:-}") || true
        if [[ -n "$stats_p" ]]; then
          echo ""
          log_info "Stats (port ${stats_p}):"
          curl -sf "localhost:${stats_p}/stats" 2>/dev/null || echo "  (not available)"
          echo ""
        fi
        pause_prompt ;;
      7)
        echo ""
        draw_line_thin
        journalctl -u "$unit" --no-pager -n 40 2>/dev/null || log_warn "No logs available"
        draw_line_thin
        pause_prompt ;;
      8)
        echo ""
        draw_line_thin
        cat "${INSTANCES_DIR}/${name}.conf" 2>/dev/null || log_error "Config not found"
        draw_line_thin
        pause_prompt ;;
      9)
        (
          local PORT="" SECRET="" DOMAIN="" FAKE_TLS=""
          load_instance_config "$name" || true
          generate_links "${DOMAIN:-unknown}" "${PORT:-0}" "${SECRET:-unknown}" "${FAKE_TLS:-no}"
        )
        pause_prompt ;;
      10)
        delete_single_service "$name"
        return 0 ;;
      0) return 0 ;;
    esac
  done
}

# --- Show All Connection Links -----------------------------------------------
show_all_links() {
  echo ""
  draw_line
  center_text "CONNECTION LINKS" "${C_CYAN}${C_BOLD}"
  draw_line

  local instances
  instances=$(list_instances)
  if [[ -z "$instances" ]]; then
    echo ""
    log_info "No services found."
    pause_prompt
    return 0
  fi

  local name
  for name in $instances; do
    (
      local PORT="" SECRET="" DOMAIN="" FAKE_TLS=""
      load_instance_config "$name" || true
      echo ""
      printf '  %b>> %s%b\n' "${C_BOLD}${C_CYAN}" "$name" "${C_RESET}"
      generate_links "${DOMAIN:-unknown}" "${PORT:-0}" "${SECRET:-unknown}" "${FAKE_TLS:-no}"
    )
  done
  echo ""
  pause_prompt
}

# --- View Status / Logs / Stats ----------------------------------------------
view_status_menu() {
  local name
  name=$(select_instance) || { pause_prompt; return 0; }

  echo ""
  draw_line
  center_text "STATUS: ${name}" "${C_CYAN}${C_BOLD}"
  draw_line
  echo ""

  show_instance_summary "$name"

  echo ""
  log_step "Systemd Status"
  local unit
  unit=$(get_service_unit_name "$name")
  systemctl --no-pager --full status "$unit" 2>/dev/null | sed -n '1,15p' || true

  echo ""
  log_step "Recent Logs"
  journalctl -u "$unit" --no-pager -n 10 2>/dev/null || true

  echo ""
  log_step "Stats"
  local stats_p=""
  stats_p=$(source "${INSTANCES_DIR}/${name}.conf" 2>/dev/null && echo "${STATS_PORT:-}") || true
  if [[ -n "$stats_p" ]]; then
    curl -sf "localhost:${stats_p}/stats" 2>/dev/null || echo "  Stats not available"
  else
    echo "  Stats port unknown"
  fi
  echo ""

  pause_prompt
}

# --- Repair Installation -----------------------------------------------------
repair_installation() {
  echo ""
  draw_line
  center_text "REPAIR INSTALLATION" "${C_CYAN}${C_BOLD}"
  draw_line
  echo ""

  local fixed=0
  local issues=0

  # 1. apt/dpkg
  log_step "Checking package manager"
  if dpkg --configure -a 2>/dev/null && apt-get --fix-broken install -y 2>/dev/null; then
    log_success "Package manager is healthy"
  else
    log_warn "Package manager had issues (attempted repair)"
    (( fixed++ )) || true
  fi

  # 2. Dependencies
  log_step "Checking dependencies"
  install_dependencies

  # 3. Binary
  log_step "Checking MTProxy binary"
  if [[ -x "$MTPROXY_BIN" ]]; then
    log_success "Binary exists and is executable"
  elif [[ -d "${MTPROXY_BASE}/.git" ]]; then
    log_warn "Binary missing, attempting rebuild..."
    if make -C "$MTPROXY_BASE" -j"$(nproc)" 2>/dev/null; then
      if [[ -x "$MTPROXY_BIN" ]]; then
        log_success "Rebuild successful"
        (( fixed++ )) || true
      else
        log_error "Binary still missing after rebuild"
        (( issues++ )) || true
      fi
    else
      log_error "Rebuild failed"
      (( issues++ )) || true
    fi
  else
    log_error "MTProxy source not found. Run Install/Update first."
    (( issues++ )) || true
  fi

  # 4. Proxy files
  log_step "Checking proxy configuration files"
  if [[ -f "${MTPROXY_BASE}/proxy-secret" ]]; then
    log_success "proxy-secret exists"
  else
    log_warn "proxy-secret missing, downloading..."
    if curl -fsSL -o "${MTPROXY_BASE}/proxy-secret" "$PROXY_SECRET_URL" 2>/dev/null; then
      log_success "Downloaded proxy-secret"
      (( fixed++ )) || true
    else
      log_error "Failed to download proxy-secret"
      (( issues++ )) || true
    fi
  fi

  if [[ -f "${MTPROXY_BASE}/proxy-multi.conf" ]]; then
    log_success "proxy-multi.conf exists"
  else
    log_warn "proxy-multi.conf missing, downloading..."
    if curl -fsSL -o "${MTPROXY_BASE}/proxy-multi.conf" "$PROXY_CONFIG_URL" 2>/dev/null; then
      log_success "Downloaded proxy-multi.conf"
      (( fixed++ )) || true
    else
      log_error "Failed to download proxy-multi.conf"
      (( issues++ )) || true
    fi
  fi

  # 5. Service template
  log_step "Checking systemd service template"
  if [[ -f "/etc/systemd/system/${SERVICE_TEMPLATE}" ]]; then
    log_success "Service template exists"
  else
    log_warn "Service template missing, recreating..."
    install_service_template
    log_success "Service template restored"
    (( fixed++ )) || true
  fi

  # 6. Daemon reload
  log_step "Reloading systemd"
  systemctl daemon-reload
  log_success "Systemd reloaded"

  # 7. System user
  log_step "Checking system user"
  if id -u "$MTPROXY_USER" &>/dev/null; then
    log_success "User '${MTPROXY_USER}' exists"
  else
    useradd -r -s /usr/sbin/nologin "$MTPROXY_USER"
    log_success "User '${MTPROXY_USER}' created"
    (( fixed++ )) || true
  fi

  # 8. Permissions
  log_step "Checking file permissions"
  if [[ -d "$MTPROXY_BASE" ]]; then
    chown -R root:root "$MTPROXY_BASE"
  fi
  if [[ -x "$MTPROXY_BIN" ]]; then
    chmod 755 "$MTPROXY_BIN"
  fi
  mkdir -p "$INSTANCES_DIR" "$LOG_DIR"
  log_success "Permissions verified"

  # 9. Sysctl
  log_step "Checking sysctl settings"
  if [[ -f "$SYSCTL_CONF" ]]; then
    log_success "Sysctl configuration exists"
  else
    cat > "$SYSCTL_CONF" <<'SYSCTL'
kernel.pid_max = 65535
net.ipv4.tcp_window_scaling = 1
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
SYSCTL
    sysctl --system &>/dev/null || true
    log_success "Sysctl configuration restored"
    (( fixed++ )) || true
  fi

  # 10. Instance configs
  log_step "Checking instance configurations"
  local instances
  instances=$(list_instances)
  if [[ -n "$instances" ]]; then
    local iname
    for iname in $instances; do
      if ( load_instance_config "$iname" ) 2>/dev/null; then
        log_detail "${iname}: config OK"
      else
        log_warn "${iname}: config has issues"
        (( issues++ )) || true
      fi
      # Check port in UFW
      if command -v ufw &>/dev/null; then
        local inst_port=""
        inst_port=$(source "${INSTANCES_DIR}/${iname}.conf" 2>/dev/null && echo "${PORT:-}") || true
        if [[ -n "$inst_port" ]]; then
          if ! ufw status 2>/dev/null | grep -q "${inst_port}/tcp"; then
            log_detail "${iname}: adding UFW rule for port ${inst_port}"
            ufw allow "${inst_port}/tcp" &>/dev/null || true
          fi
        fi
      fi
    done
  else
    log_info "No instances found to check"
  fi

  # Report
  echo ""
  draw_line
  center_text "REPAIR REPORT" "${C_GREEN}${C_BOLD}"
  draw_line
  echo ""
  log_info "Items fixed:      ${fixed}"
  log_info "Issues remaining: ${issues}"
  if (( issues == 0 )); then
    log_success "Installation appears healthy!"
  else
    log_warn "Some issues remain. Consider running Install/Update to fix."
  fi
  echo ""
  pause_prompt
}

# --- Delete Single Service ---------------------------------------------------
delete_single_service() {
  local name="${1:-}"

  if [[ -z "$name" ]]; then
    name=$(select_instance) || { pause_prompt; return 0; }
  fi

  echo ""
  draw_line
  center_text "DELETE SERVICE: ${name}" "${C_RED}${C_BOLD}"
  draw_line
  echo ""

  if ! ui_yesno "Confirm Deletion" "Are you sure you want to delete service '${name}'? This cannot be undone."; then
    log_info "Deletion cancelled."
    pause_prompt
    return 0
  fi

  # Offer backup
  if ui_yesno "Backup Config" "Do you want to backup the configuration before deleting?"; then
    local backup_dir="/tmp/mtproxy-backup-$(date +%s)"
    mkdir -p "$backup_dir"
    cp "${INSTANCES_DIR}/${name}.conf" "${backup_dir}/" 2>/dev/null || true
    log_success "Config backed up to: ${backup_dir}/"
  fi

  local unit
  unit=$(get_service_unit_name "$name")

  log_step "Stopping service"
  systemctl stop "$unit" 2>/dev/null || true
  systemctl disable "$unit" 2>/dev/null || true
  log_success "Service stopped and disabled"

  log_step "Removing configuration"
  rm -f "${INSTANCES_DIR}/${name}.conf"
  log_success "Configuration removed"

  log_info "Note: You may want to manually remove any UFW rules for this service's port."

  systemctl daemon-reload

  echo ""
  log_success "Service '${name}' has been deleted."
  echo ""
  pause_prompt
}

# --- Delete Service (menu entry) ---------------------------------------------
delete_service_menu() {
  delete_single_service ""
}

# --- Full Uninstall ----------------------------------------------------------
full_uninstall() {
  echo ""
  draw_line
  center_text "FULL UNINSTALL" "${C_RED}${C_BOLD}"
  draw_line
  echo ""

  log_warn "This will remove MTProxy, ALL services, and ALL configurations."
  echo ""

  if ! ui_yesno "First Confirmation" "Are you sure you want to completely uninstall MTProxy?"; then
    log_info "Uninstall cancelled."
    pause_prompt
    return 0
  fi

  if ! ui_yesno "FINAL CONFIRMATION" "THIS IS IRREVERSIBLE. All services and data will be lost. Continue?"; then
    log_info "Uninstall cancelled."
    pause_prompt
    return 0
  fi

  # Offer backup
  if ui_yesno "Backup" "Do you want to backup all configurations before uninstalling?"; then
    local backup_dir="/tmp/mtproxy-full-backup-$(date +%s)"
    mkdir -p "$backup_dir"
    cp -r "$INSTANCES_DIR" "${backup_dir}/" 2>/dev/null || true
    log_success "Configurations backed up to: ${backup_dir}/"
  fi

  # Stop and disable all services
  log_step "Stopping all services"
  local instances
  instances=$(list_instances)
  if [[ -n "$instances" ]]; then
    local sname
    for sname in $instances; do
      local sunit
      sunit=$(get_service_unit_name "$sname")
      systemctl stop "$sunit" 2>/dev/null || true
      systemctl disable "$sunit" 2>/dev/null || true
      log_detail "Stopped: ${sname}"
    done
  fi
  log_success "All services stopped"

  # Remove service template
  log_step "Removing systemd files"
  rm -f "/etc/systemd/system/${SERVICE_TEMPLATE}"
  systemctl daemon-reload
  log_success "Systemd files removed"

  # Remove configurations
  log_step "Removing configurations"
  rm -rf "$INSTANCES_DIR"
  rm -rf /etc/mtproxy
  log_success "Configurations removed"

  # Remove source and binary
  log_step "Removing MTProxy source"
  rm -rf "$MTPROXY_BASE"
  log_success "Source removed"

  # Remove sysctl
  log_step "Removing sysctl settings"
  rm -f "$SYSCTL_CONF"
  sysctl --system &>/dev/null || true
  log_success "Sysctl settings removed"

  # Remove logs
  log_step "Removing logs"
  rm -rf "$LOG_DIR"
  log_success "Logs removed"

  # Remove user
  log_step "Removing system user"
  if id -u "$MTPROXY_USER" &>/dev/null; then
    userdel "$MTPROXY_USER" 2>/dev/null || true
    log_success "User '${MTPROXY_USER}' removed"
  fi

  log_info "Note: SSH (22/tcp) UFW rule was preserved."
  log_info "You may want to manually remove other UFW rules."

  echo ""
  draw_line
  center_text "UNINSTALL COMPLETE" "${C_GREEN}${C_BOLD}"
  draw_line
  echo ""
  log_success "MTProxy has been completely removed from this system."
  echo ""
  pause_prompt
}

# --- Main Menu ---------------------------------------------------------------
main_menu() {
  while true; do
    show_banner
    local choice
    choice=$(ui_menu "MTProxy Manager v${SCRIPT_VERSION} @A9ii" "Select an option:" \
      "1"  "Install / Update MTProxy Core" \
      "2"  "Create New MTProxy Service" \
      "3"  "List Existing Services" \
      "4"  "Manage Existing Service" \
      "5"  "Show Connection Links" \
      "6"  "View Service Status / Logs / Stats" \
      "7"  "Repair Installation" \
      "8"  "Delete Service" \
      "9"  "Full Uninstall" \
      "0"  "Exit" \
    ) || { echo ""; log_info "Goodbye!"; exit 0; }

    case "$choice" in
      1) install_core ;;
      2) create_service ;;
      3) list_services ;;
      4) manage_service ;;
      5) show_all_links ;;
      6) view_status_menu ;;
      7) repair_installation ;;
      8) delete_service_menu ;;
      9) full_uninstall ;;
      0)
        echo ""
        draw_line
        center_text "Thank you for using MTProxy Manager!" "${C_CYAN}"
        draw_line
        echo ""
        exit 0 ;;
    esac
  done
}

# --- CLI Argument Handling ---------------------------------------------------
handle_cli_args() {
  case "${1:-}" in
    --install|--update)
      run_system_checks
      install_core
      exit 0 ;;
    --create)
      run_system_checks
      create_service
      exit 0 ;;
    --list)
      detect_ui
      list_services
      exit 0 ;;
    --links)
      detect_ui
      show_all_links
      exit 0 ;;
    --repair)
      run_system_checks
      repair_installation
      exit 0 ;;
    --uninstall)
      detect_ui
      full_uninstall
      exit 0 ;;
    --status)
      detect_ui
      view_status_menu
      exit 0 ;;
    --help|-h)
      echo ""
      echo "MTProxy Installer & Manager v${SCRIPT_VERSION}"
      echo ""
      echo "Usage: $0 [OPTION]"
      echo ""
      echo "Options:"
      echo "  --install    Install or update MTProxy core"
      echo "  --create     Create a new MTProxy service"
      echo "  --list       List existing services"
      echo "  --links      Show connection links for all services"
      echo "  --status     View service status, logs, and stats"
      echo "  --repair     Repair installation"
      echo "  --uninstall  Full uninstall"
      echo "  --help       Show this help"
      echo ""
      echo "Running without arguments starts the interactive menu."
      echo ""
      exit 0 ;;
    "")
      return 0 ;;
    *)
      echo "Unknown option: ${1}"
      echo "Use --help for available options."
      exit 1 ;;
  esac
}

# --- Entry Point -------------------------------------------------------------
main() {
  handle_cli_args "$@"
  detect_ui
  show_banner
  run_system_checks
  main_menu
}

main "$@"
