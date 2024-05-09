#!/bin/bash

# install and start Docker service
yum install docker -y
systemctl enable docker.service
systemctl start docker.service
usermod -a -G docker ec2-user

# install docker-compose
curl -L https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m) -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Download Spline demo Docker-compose config files
mkdir /home/ec2-user/spline
cd /home/ec2-user/spline
wget https://raw.githubusercontent.com/AbsaOSS/spline-getting-started/main/docker/compose.yaml
wget https://raw.githubusercontent.com/AbsaOSS/spline-getting-started/main/docker/.env

# can use below to get public IP if needed
# TOKEN=`curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"`
# IP_ADDRESS=`curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/local-ipv4`

# echo $IP_ADDRESS

# change to use public IP address if needed
# DOCKER_HOST_EXTERNAL=$IP_ADDRESS /usr/local/bin/docker-compose up

echo Finished