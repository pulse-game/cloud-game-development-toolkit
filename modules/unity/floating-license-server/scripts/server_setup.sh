#!/bin/bash

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting user data script execution..."

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Installing prerequisites..."
apt-get update
apt-get install -y fuse3 s3fs unzip expect

# Install and start SSM Agent
#echo "[$(date '+%Y-%m-%d %H:%M:%S')] Installing and starting SSM Agent..."
#snap install amazon-ssm-agent --classic
#systemctl enable snap.amazon-ssm-agent.amazon-ssm-agent.service
#systemctl start snap.amazon-ssm-agent.amazon-ssm-agent.service

# Install AWS CLI v2
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Installing AWS CLI v2..."
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install

# Mount S3 bucket to file system
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Creating mount point..."
mkdir -p /mnt/s3
chown ubuntu:ubuntu /mnt/s3
chmod 755 /mnt/s3

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Mounting S3 bucket..."
s3fs "${s3_bucket_name}" /mnt/s3 -o iam_role="${iam_role_name}" -o allow_other -o uid=$(id -u ubuntu) -o gid=$(id -g ubuntu) -o stat_cache_expire=1 -o use_cache=/tmp -o del_cache

# Create the unity-licensing-server group
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Creating unity-licensing-server group..."
groupadd unity-licensing-server

# Add ubuntu user to the group
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Adding ubuntu user to unity-licensing-server group..."
usermod -a -G unity-licensing-server ubuntu

# Set correct ownership for Unity directories
chown -R ubuntu:unity-licensing-server /opt/UnityLicensingServer
chown -R ubuntu:unity-licensing-server /usr/share/unity3d/LicensingServer

# Set correct permissions
chmod -R 775 /opt/UnityLicensingServer
chmod -R 775 /usr/share/unity3d/LicensingServer

# Create directory and extract file
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Creating Unity License Server directory..."
mkdir -p /opt/UnityLicensingServer
chown ubuntu:ubuntu /opt/UnityLicensingServer

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Copying and extracting Unity License Server..."
cp /mnt/s3/"${license_server_file_name}" /opt/UnityLicensingServer/
cd /opt/UnityLicensingServer
unzip "${license_server_file_name}"
chmod +x Unity.Licensing.Server

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Getting admin password from Secrets Manager..."
ADMIN_PASSWORD=$(aws secretsmanager get-secret-value --secret-id "${admin_password_arn}" --query 'SecretString' --output text)

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Setting up Unity License Server..."
# Create expect script
cat << 'EXPECT' > setup.exp
#!/usr/bin/expect -f
set servername [lindex $argv 0]
set serverport [lindex $argv 1]
set password [lindex $argv 2]
spawn ./Unity.Licensing.Server setup
expect "Enter the server name"
send "$servername\r"
expect "Do you want the licensing server to use HTTPS?"
send "n\r"
expect "Enter the index number of the network interface"
send "2\r"
expect "Enter server's listening port number"
send "$serverport\r"
expect "Create a password"
send "$password\r"
expect "Confirm the password"
send "$password\r"
expect eof
EXPECT

chmod +x setup.exp
./setup.exp "${license_server_name}" "${license_server_port}" "$ADMIN_PASSWORD"

# Ensure Unity License Server data directory exists with correct permissions
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Setting up Unity License Server data directory..."
mkdir -p /usr/share/unity3d/LicensingServer/data
chown -R ubuntu:ubuntu /usr/share/unity3d/LicensingServer
chmod -R 755 /usr/share/unity3d/LicensingServer

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Creating systemd service..."
cat << 'SYSTEMD' > /etc/systemd/system/unity-license-server.service
[Unit]
Description=Unity License Server
After=network.target

[Service]
Type=simple
User=ubuntu
Group=unity-licensing-server
WorkingDirectory=/opt/UnityLicensingServer
ExecStart=/opt/UnityLicensingServer/Unity.Licensing.Server run
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
SYSTEMD

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting Unity License Server..."
systemctl daemon-reload
systemctl enable unity-license-server
systemctl start unity-license-server

# Add automatic S3 mount on boot
echo "${s3_bucket_name} /mnt/s3 fuse.s3fs _netdev,allow_other,iam_role=${iam_role_name},uid=$(id -u ubuntu),gid=$(id -g ubuntu) 0 0" >> /etc/fstab

# Copy generated files to S3
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Copying generated files to S3..."
cp /opt/UnityLicensingServer/server-registration-request.xml /mnt/s3/
cp /opt/UnityLicensingServer/services-config.json /mnt/s3/
