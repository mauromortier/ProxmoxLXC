#!/bin/bash

# Variables for the LXC container configuration
TEMPLATE="debian-12-standard_12.7-1_amd64.tar.zst"  # LXC template name
STORAGE="local"                      # Storage location for the root filesystem
TARGET_STORAGE="Spinny"              # Storage location where CT will live
DISK_SIZE="8"                        # Disk size for the container, in GB
CPU_CORES=2                          # Number of CPU cores
MEMORY_MB=512                        # Memory in MB
GATEWAY="192.168.0.1"                # Gateway IP address
PASSWORD="PASSWORD"                  # Root password for the container
BRIDGE="vmbr0"                       # Network bridge
START_AFTER_CREATE=1                 # Start container after creation (1 = yes, 0 = no)



# Prompt for LXC Container ID
read -p "Enter the CTID you'd like: " CTID
if [ -z "$CTID" ]; then
    echo "Container ID cannot be empty. Exiting."
    exit 1
fi

# Prompt for hostname
read -p "Enter the hostname for the container: " HOSTNAME
if [ -z "$HOSTNAME" ]; then
    echo "Hostname cannot be empty. Exiting."
    exit 1
fi

# Prompt for IP address
read -p "Enter the IP address for the container (with subnet, e.g., 192.168.0.10/24): " IP_ADDRESS
if [ -z "$IP_ADDRESS" ]; then
    echo "IP address cannot be empty. Exiting."
    exit 1
fi

# Download the template if it’s not already downloaded
echo "Checking for template..."
if ! pveam list $STORAGE | grep -q "$TEMPLATE"; then
    echo "Template not found. Downloading template $TEMPLATE..."
    pveam download $STORAGE $TEMPLATE
else
    echo "Template already exists."
fi

# Create the LXC container
echo "Creating LXC container with ID $CTID..."
pct create $CTID ${STORAGE}:vztmpl/$TEMPLATE \
    --rootfs ${TARGET_STORAGE}:$DISK_SIZE \
    --hostname $HOSTNAME \
    --cores $CPU_CORES \
    --memory $MEMORY_MB \
    --net0 name=eth0,bridge=$BRIDGE,ip=$IP_ADDRESS,gw=$GATEWAY \
    --password $PASSWORD \
    --start $START_AFTER_CREATE

echo "Container $CTID created successfully."

# Enabling autostart on boot
echo "Enabling autostart on boot for container $CTID..."
pct set $CTID --onboot 1

echo "Container setup complete."
echo "starting updates"

# Updating the LXC remotely
pct exec $CTID -- apt update
lxc-attach $CTID -- apt upgrade -y

# Installing Dependencies & Docker
lxc-attach $CTID --  apt-get install -y \
  ca-certificates \
  curl \
  gnupg \
  lsb-release && \
  mkdir -p /etc/apt/keyrings && \
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg && \
  echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null && \
  apt-get update && apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
