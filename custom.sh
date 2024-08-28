#!/bin/bash

# Function to display header information
function header_info {
  clear
  cat <<"EOF"
    ____             __            
   / __ \____  _____/ /_  __  _____
  / / / / __ \/ ___/ //_/ _ \/ ___/
 / /_/ / /_/ / /__/ ,< /  __/ /    
/_____/\____/\___/_/|_|\___/_/     
 
EOF
}

# Function to load initial variables and settings
function load_variables {
  echo -e "Loading..."
  APP="Docker"
  var_disk="4"
  var_cpu="1"
  var_ram="1024"
  var_os="debian"
  var_version="12"
  STORAGE="Spinny"  # Use a valid storage name here, e.g., 'local' or another configured storage
}

# Function for setting default container parameters
function default_settings {
  CT_TYPE="1"  # Container type (1 for unprivileged container)
  PW=""        # Root password (leave empty for no password)
  CT_ID=$(pvesh get /cluster/nextid)  # Automatically get the next available ID
  HN="${APP,,}"  # Container hostname, lowercase app name
  DISK_SIZE="${var_disk}G"
  CORE_COUNT="$var_cpu"
  RAM_SIZE="$var_ram"
  BRG="vmbr0"
  
  # Ask for IP address or default to DHCP
  echo -n "Enter a static IP address (or press Enter to use DHCP): "
  read user_ip
  
  if [[ -z "$user_ip" ]]; then
    NET="dhcp"
    echo "Using DHCP for network configuration."
  else
    NET="$user_ip"
    echo "Using static IP: $NET"
  fi
  
  SSH="yes"
  echo "Default settings configured."
}

#Function to build the actual container
function build_container {
  echo "Building the LXC container..."
  
  # Ensure the container template exists
  TEMPLATE_PATH="/var/lib/vz/template/cache/debian-12-standard_12.2-1_amd64.tar.zst"
  if [[ ! -f $TEMPLATE_PATH ]]; then
    echo "Template $TEMPLATE_PATH does not exist. Please check the template path."
    exit 1
  fi

  # Create the container
  pct create $CT_ID $TEMPLATE_PATH \
    --hostname $HN \
    --cores $CORE_COUNT \
    --memory $RAM_SIZE \
    --net0 name=eth0,bridge=$BRG,ip=$NET \
    --rootfs Spinny:$var_disk,size=$var_disk"GB" \
    --unprivileged $CT_TYPE \
    --features nesting=1 \
    --password $PW

  # Check if the configuration file was created
  CONFIG_FILE="/etc/pve/lxc/$CT_ID.conf"
  if [[ ! -f $CONFIG_FILE ]]; then
    echo "Configuration file $CONFIG_FILE does not exist. Container creation might have failed."
    exit 1
  fi

  echo "Container created with ID $CT_ID."
}

# Function to start the container
function start {
  echo "Starting the container..."
  pct start $CT_ID
  echo "Container $CT_ID started."
}

# Function to configure the container for Docker
function description {
  echo "Configuring the container for Docker..."

  # Install Docker inside the container
  pct exec $CT_ID -- bash -c "apt-get update && apt-get install -y curl"
  pct exec $CT_ID -- bash -c "curl -fsSL https://get.docker.com | sh"

  echo "Docker installed in container $CT_ID."
}

# Function to update the Docker LXC
function update_script {
  header_info
  if ! pct status $CT_ID &>/dev/null; then 
    echo "No ${APP} Installation Found!"
    exit
  fi
  echo "Updating ${APP} LXC"
  pct exec $CT_ID -- bash -c "apt-get update && apt-get -y upgrade"
  echo "Updated ${APP} LXC"
  exit
}

# Function to signal completion
function msg_ok {
  echo -e "$1"
}

# Function to start the process
function start_process {
  header_info
  load_variables
  default_settings
  build_container
  start
  description
  msg_ok "Completed Successfully!\n"
}

# Start the script
start_process
