#!/bin/bash
# Update package lists
apt-get update

# Install required packages
apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

# Add Docker's official GPG key
mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# Set up the Docker repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker Engine
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Enable and start Docker service
systemctl enable docker
systemctl start docker

# Add the current user to the docker group (optional)
usermod -aG docker $USER

# Pull Docker Compose YAML file
mkdir /opt/app
cd /opt/app
curl -L https://releases.conduktor.io/console -o docker-compose.yml

# set up crontab to run docker compose on restart
(crontab -l 2>/dev/null; echo "@reboot docker compose -f /opt/app/docker-compose.yml up -d") | crontab -

# reboot the instance
reboot