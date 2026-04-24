#!/usr/bin/env bash
# ============================================================================
#  LXC Deployer for Proxmox — Docker Edition
#  Creates a Debian LXC container with Docker + Compose
#
#  Run on your Proxmox host:
#    bash lxc-docker.sh
# ============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ── Pre-flight ─────────────────────────────────────────────────────────────
[[ $(id -u) -eq 0 ]]          || error "Must be run as root on the Proxmox host."
command -v pct   &>/dev/null  || error "pct not found — are you on a Proxmox host?"
command -v pveam &>/dev/null  || error "pveam not found — are you on a Proxmox host?"

# ── Configuration ──────────────────────────────────────────────────────────
TEMPLATE="debian-13-standard_13.1-2_amd64.tar.zst"
NEXT_ID=$(pvesh get /cluster/nextid 2>/dev/null || echo "100")

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║      LXC Docker Deployer (Proxmox)               ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════╝${NC}"
echo ""

prompt() {
  local label="$1" default="$2" varname="$3"
  read -rp "$label [$default]: " val
  printf -v "$varname" '%s' "${val:-$default}"
}

prompt    "Container ID"             "$NEXT_ID"   CT_ID
[[ "$CT_ID" =~ ^[0-9]+$ ]]          || error "Container ID must be a number."
pct status "$CT_ID" &>/dev/null      && error "Container $CT_ID already exists."

prompt    "Hostname"                 "docker"     CT_HOSTNAME
read -rsp "Root password: "                       CT_PASSWORD; echo ""
[[ -n "$CT_PASSWORD" ]]              || error "Password cannot be empty."
prompt    "CPU cores"                "2"          CT_CORES
prompt    "RAM in MB"                "2048"       CT_RAM
prompt    "Swap in MB"               "512"        CT_SWAP
prompt    "Disk size in GB"          "20"         CT_DISK
prompt    "Storage"                  "SSD2"  CT_STORAGE
prompt    "IP (dhcp or 192.168.0.x/24)" "dhcp"       CT_IP

CT_GW=""
if [[ "$CT_IP" != "dhcp" ]]; then
  prompt  "Gateway"                  ""           CT_GW
  [[ -n "$CT_GW" ]] || error "Gateway required for static IP."
fi

prompt    "DNS server"               "1.1.1.1"    CT_DNS

echo ""
echo -e "${BOLD}Summary${NC}"
echo "──────────────────────────────────────"
echo "  ID:       $CT_ID"
echo "  Hostname: $CT_HOSTNAME"
echo "  CPU:      $CT_CORES cores"
echo "  RAM:      $CT_RAM MB"
echo "  Swap:     $CT_SWAP MB"
echo "  Disk:     ${CT_DISK}G on $CT_STORAGE"
echo "  Network:  $CT_IP"
echo "  DNS:      $CT_DNS"
echo "──────────────────────────────────────"
echo ""
read -rp "Proceed? (Y/n): " confirm
[[ "$confirm" =~ ^([Yy]|)$ ]] || { echo "Aborted."; exit 0; }

# ── Download template if needed ────────────────────────────────────────────
info "Checking for template..."
if ! pveam list local 2>/dev/null | grep -q "$TEMPLATE"; then
  info "Downloading $TEMPLATE..."
  pveam download local "$TEMPLATE" || error "Download failed. Try running 'pveam update' first."
fi
success "Template ready."

# ── Create container ───────────────────────────────────────────────────────
info "Creating container $CT_ID..."

NET="name=eth0,bridge=vmbr0"
[[ "$CT_IP" == "dhcp" ]] && NET+=",ip=dhcp" || NET+=",ip=$CT_IP,gw=$CT_GW"

pct create "$CT_ID" "local:vztmpl/$TEMPLATE" \
  --hostname   "$CT_HOSTNAME" \
  --password   "$CT_PASSWORD" \
  --cores      "$CT_CORES" \
  --memory     "$CT_RAM" \
  --swap       "$CT_SWAP" \
  --rootfs     "$CT_STORAGE:$CT_DISK" \
  --net0       "$NET" \
  --nameserver "$CT_DNS" \
  --ostype     debian \
  --unprivileged 0 \
  --features   nesting=1,keyctl=1 \
  --onboot     1 \
  --start      0

# Required for Docker-in-LXC
echo "lxc.apparmor.profile: unconfined" >> "/etc/pve/lxc/${CT_ID}.conf"
success "Container created."

# ── Start & wait for network ───────────────────────────────────────────────
info "Starting container..."
pct start "$CT_ID"
sleep 3

info "Waiting for network..."
attempts=0
while ! pct exec "$CT_ID" -- ping -c1 -W2 1.1.1.1 &>/dev/null; do
  ((attempts++))
  [[ $attempts -lt 30 ]] || error "No network after 60s."
  sleep 2
done
success "Container is online."

# ── Update system ──────────────────────────────────────────────────────────
info "Updating system..."
pct exec "$CT_ID" -- bash -c "
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get upgrade -y -qq
  apt-get install sudo -y -qq
  apt-get install curl -y -qq
"
success "System updated."

# ── Install Docker ─────────────────────────────────────────────────────────
info "Installing Docker..."
pct exec "$CT_ID" -- bash -c "
  # Add Docker's official GPG key:
apt-get update -qq
apt-get install ca-certificates -y -qq
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources:
tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: \$(. /etc/os-release && echo \"\$VERSION_CODENAME\")
Components: stable
Architectures: \$(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

apt-get update -qq

apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl start docker
"
success "Docker installed."

# ── Install Fastfetch ─────────────────────────────────────────────────────────

pct exec "$CT_ID" -- bash -c "
apt-get install fastfetch -y -qq
echo ""
echo ""
echo ""
echo ""
fastfetch
"

# ── Done ───────────────────────────────────────────────────────────────────
CT_IP_LIVE=$(pct exec "$CT_ID" -- hostname -I 2>/dev/null | awk '{print $1}')


echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║            Container Ready!                      ║${NC}"
echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BOLD}Container:${NC}  $CT_ID ($CT_HOSTNAME)"
echo -e "  ${BOLD}IP:${NC}         ${CT_IP_LIVE:-pending (DHCP)}"
echo ""
echo ""
echo ""
