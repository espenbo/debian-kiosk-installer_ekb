#!/bin/bash

LOGFILE="/var/log/kiosk-installer-wayland.log"

# Function to log messages
log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a $LOGFILE
}

# Function to get the IP address of the machine
get_ip_address() {
  hostname -I | awk '{print $1}'
}

# Default values
DEFAULT_BROWSER="firefox"
DEFAULT_USER="kiosk"
DEFAULT_GROUP="kiosk"
#DEFAULT_URL=$(get_ip_address)
DEFAULT_URL="192.168.1.3:8123"

# Function to prompt user for input or use default values
prompt_user_input() {
  local prompt=$1
  local default_value=$2
  local var_name=$3

  if [ "$DEFAULTS" = true ]; then
    eval $var_ame=\$default_value
  else
    read -p "$prompt [$default_value]: " input
    eval $var_name=\${input:-$default_value}
  fi
}

# Function to undo the installation
undo_installation() {
  log "Starting undo process..."
  
  log "Stopping LightDM service..."
  systemctl stop lightdm
  
  log "Removing installed packages..."
  apt-get remove --purge unclutter sway wdisplays lightdm locales -y
  
  if [ "$BROWSER_CHOICE" = "firefox" ] || [ "$BROWSER_CHOICE" = "both" ]; then
    apt-get remove --purge firefox -y
  fi

  if [ "$BROWSER_CHOICE" = "chromium" ] || [ "$BROWSER_CHOICE" = "both" ]; then
    apt-get remove --purge chromium -y
  fi

  log "Deleting user and group..."
  userdel -r $USERNAME
  groupdel $GROUPNAME

  log "Restoring backup files..."
  if [ -e "/etc/lightdm/lightdm.conf.backup" ]; then
    mv /etc/lightdm/lightdm.conf.backup /etc/lightdm/lightdm.conf
  fi

  if [ -e "/home/$USERNAME/.config/sway/config.backup" ]; then
    mv /home/$USERNAME/.config/sway/config.backup /home/$USERNAME/.config/sway/config
  fi

  log "Undo process completed."
}

# Parse command line arguments
DEFAULTS=false
UNDO=false
while getopts ":du" opt; do
  case $opt in
    d) DEFAULTS=true ;;
    u) UNDO=true ;;
    \?) echo "Invalid option -$OPTARG" >&2 ;;
  esac
done

if [ "$UNDO" = true ]; then
  undo_installation
  exit 0
fi

# Prompt for browser choice
prompt_user_input "Which browser do you want to install? (firefox/chromium/both)" "$DEFAULT_BROWSER" BROWSER_CHOICE

# Prompt for username
prompt_user_input "Enter the username to be created or use default" "$DEFAULT_USER" USERNAME

# Prompt for group name
prompt_user_input "Enter the group name to be created or use default" "$DEFAULT_GROUP" GROUPNAME

# Prompt for URL to display
prompt_user_input "Enter the URL to display in kiosk mode" "$DEFAULT_URL" URL

# Update package list
log "Updating package list..."
apt-get update

# Install necessary software based on browser choice
log "Installing necessary software..."
if [ "$BROWSER_CHOICE" = "firefox" ] || [ "$BROWSER_CHOICE" = "both" ]; then
  apt-get install firefox -y
fi

if [ "$BROWSER_CHOICE" = "chromium" ] || [ "$BROWSER_CHOICE" = "both" ]; then
  apt-get install chromium -y
fi

apt-get install unclutter sway wdisplays lightdm locales -y

# Create necessary directories
log "Creating necessary directories..."
mkdir -p /home/$USERNAME/.config/sway

# Create group and user
log "Creating group and user..."
groupadd $GROUPNAME
id -u $USERNAME &>/dev/null || useradd -m $USERNAME -g $GROUPNAME -s /bin/bash 

# Set correct ownership
log "Setting correct ownership..."
chown -R $USERNAME:$GROUPNAME /home/$USERNAME

# Backup and create LightDM configuration for autologin
log "Configuring LightDM..."
if [ -e "/etc/lightdm/lightdm.conf" ]; then
  mv /etc/lightdm/lightdm.conf /etc/lightdm/lightdm.conf.backup
fi
cat > /etc/lightdm/lightdm.conf << EOF
[SeatDefaults]
autologin-user=$USERNAME
user-session=sway
EOF

# Backup and create Sway configuration for autostart
log "Configuring Sway..."
if [ -e "/home/$USERNAME/.config/sway/config" ]; then
  mv /home/$USERNAME/.config/sway/config /home/$USERNAME/.config/sway/config.backup
fi
cat > /home/$USERNAME/.config/sway/config << EOF
# Sway configuration for kiosk

# Start unclutter to hide mouse cursor after 0.1 seconds of inactivity
exec_always --no-startup-id unclutter -idle 0.1 -grab

# Automatically configure screens
exec_always --no-startup-id wdisplays -e

# Start browser in kiosk mode
EOF

# Add Firefox to Sway configuration if chosen
if [ "$BROWSER_CHOICE" = "firefox" ] || [ "$BROWSER_CHOICE" = "both" ]; then
  echo 'exec_always --no-startup-id firefox --kiosk "$URL"' >> /home/$USERNAME/.config/sway/config
fi

# Add Chromium to Sway configuration if chosen
if [ "$BROWSER_CHOICE" = "chromium" ] || [ "$BROWSER_CHOICE" = "both" ]; then
  cat >> /home/$USERNAME/.config/sway/config << EOF
exec_always --no-startup-id chromium \
  --no-first-run \
  --start-maximized \
  --disable \
  --disable-translate \
  --disable-infobars \
  --disable-suggestions-service \
  --disable-save-password-bubble \
  --disable-session-crashed-bubble \
  --incognito \
  --kiosk "$URL"
EOF
fi

# Ensure the browser stays running by restarting if it crashes
cat >> /home/$USERNAME/.config/sway/config << EOF

# Ensure the browser stays running
exec_always --no-startup-id while :; do
  if ! pgrep -x "$BROWSER_CHOICE" > /dev/null
  then
    if [ "$BROWSER_CHOICE" = "firefox" ] || [ "$BROWSER_CHOICE" = "both" ]; then
      firefox --kiosk "$URL"
    fi
    if [ "$BROWSER_CHOICE" = "chromium" ] || [ "$BROWSER_CHOICE" = "both" ]; then
      chromium \
        --no-first-run \
        --start-maximized \
        --disable \
        --disable-translate \
        --disable-infobars \
        --disable-suggestions-service \
        --disable-save-password-bubble \
        --disable-session-crashed-bubble \
        --incognito \
        --kiosk "$URL"
    fi
  fi
  sleep 5
done
EOF

# Set correct ownership for Sway configuration
log "Setting correct ownership for Sway configuration..."
chown -R $USERNAME:$GROUPNAME /home/$USERNAME/.config/sway

log "Installation completed."
echo "Done!"
