#!/bin/bash
su ec2-user
# install and start Docker service
sudo yum install docker -y
sudo systemctl enable docker.service
sudo systemctl start docker.service
sudo usermod -a -G docker ec2-user

# install docker-compose
sudo curl -L https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m) -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Download Spline demo Docker-compose config files
mkdir /home/ec2-user/spline
cd /home/ec2-user/spline
wget https://raw.githubusercontent.com/AbsaOSS/spline-getting-started/main/docker/compose.yaml
wget https://raw.githubusercontent.com/AbsaOSS/spline-getting-started/main/docker/.env

# can use below to get public IP if needed
# TOKEN=`curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"`
# IP_ADDRESS=`curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/public-ipv4`

# echo $IP_ADDRESS

# if using public ip, specify as below to enable external connections
# DOCKER_HOST_EXTERNAL=$IP_ADDRESS docker-compose up
docker-compose up

echo Finished