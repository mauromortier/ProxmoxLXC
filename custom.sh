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
}

# Function for setting default container parameters
function default_settings {
  CT_TYPE="1"
  PW=""
  CT_ID=$NEXTID
  HN=$NSAPP
  DISK_SIZE="$var_disk"
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
    NET="$user_ip/24"
    echo "Using static IP: $NET"
  fi
  
  GATE=""
  APT_CACHER=""
  APT_CACHER_IP=""
  DISABLEIP6="yes"
  MTU=""
  SD=""
  NS=""
  MAC=""
  VLAN=""
  SSH="yes"
  VERB="no"
  echo_default
}

# Function to update the Docker LXC
function update_script {
  header_info
  if [[ ! -d /var ]]; then 
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_info "Updating ${APP} LXC"
  apt-get update &>/dev/null
  apt-get -y upgrade &>/dev/null
  msg_ok "Updated ${APP} LXC"
  exit
}

# Function to start the process
function start_process {
  header_info
  load_variables
  default_settings
  start
  build_container
  description
  msg_ok "Completed Successfully!\n"
}

# Start the script
start_process
