#!/bin/bash

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Setting up license watch daemon..."

# Install inotify-tools
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Installing inotify-tools..."
apt-get install -y inotify-tools

# Create the watch script
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Creating watch script..."
cat << 'WATCHSCRIPT' > /opt/UnityLicensingServer/watch_for_license_upload.sh
#!/bin/bash

# Set up logging
exec 1> >(logger -s -t $(basename $0)) 2>&1

echo "Starting license file watch process for filename: ${license_server_name}.zip"

# Function to refresh the s3fs mount
refresh_s3fs_mount() {
    echo "Refreshing S3 mount..."
    ls -la /mnt/s3 > /dev/null 2>&1
}

# Function to process the license file
process_license_file() {
    echo "License file detected, starting import..."

    # Copy to local directory
    echo "Copying file from S3 to local directory..."
    if ! cp /mnt/s3/${license_server_name}.zip /opt/UnityLicensingServer/; then
        echo "Failed to copy file from S3"
        return 1
    fi

    # Verify file was copied
    echo "Verifying copied file..."
    if [ ! -f "/opt/UnityLicensingServer/${license_server_name}.zip" ]; then
        echo "File not found in local directory after copy"
        return 1
    fi

    # Create expect script for import
    echo "Creating expect script..."
    cat << IMPORTSCRIPT > /opt/UnityLicensingServer/import.exp
#!/usr/bin/expect -f
log_file /tmp/unity_import.log
exp_internal 1
set timeout 30

# Use bash for command execution
spawn bash
expect "$"

# Run the Unity Licensing Server import command (using full paths)
send "cd /opt/UnityLicensingServer && sudo ./Unity.Licensing.Server import ${license_server_name}.zip\r"
expect {
    "Enter the index number of the toolset that should be used by default:" {
        send "1\r"
        exp_continue
    }
    "Successfully imported licensing files" {
        puts "Import successful"
        exit 0
    }
    timeout {
        puts "Timeout waiting for completion"
        exit 2
    }
    eof {
        puts "Unexpected end of file"
        exit 1
    }
}
IMPORTSCRIPT

    chmod +x /opt/UnityLicensingServer/import.exp

    # Run the import script
    echo "Running import script..."
    cd /opt/UnityLicensingServer
    ./import.exp 2>&1 | tee /tmp/import_execution.log
    IMPORT_STATUS=$?

    # Capture all relevant logs
    echo "--- Import Execution Log ---" >> /tmp/import_debug.log
    cat /tmp/import_execution.log >> /tmp/import_debug.log
    echo "--- Unity Import Log ---" >> /tmp/import_debug.log
    cat /tmp/unity_import.log >> /tmp/import_debug.log
    echo "--- Current Directory Contents ---" >> /tmp/import_debug.log
    ls -la >> /tmp/import_debug.log

    if [ $IMPORT_STATUS -eq 0 ]; then
        echo "License import successful"

        # Restart the Unity License Server
        echo "Restarting Unity License Server..."
        sudo systemctl restart unity-license-server

        # Move the processed file to a 'processed' folder
        mkdir -p /mnt/s3/processed
        mv /mnt/s3/${license_server_name}.zip /mnt/s3/processed/${license_server_name}.zip.$(date +%Y%m%d_%H%M%S)

        # Copy debug logs to S3
        cp /tmp/import_debug.log /mnt/s3/processed/import_debug.$(date +%Y%m%d_%H%M%S).log

        # Create success flag file
        echo "Import completed successfully and server restarted at $(date)" > /mnt/s3/import_success.txt

        # Stop the watch service
        sudo systemctl stop unity-license-watch
        return 0
    else
        echo "License import failed"
        # Move the file to a 'failed' folder
        mkdir -p /mnt/s3/failed
        mv /mnt/s3/${license_server_name}.zip /mnt/s3/failed/${license_server_name}.zip.$(date +%Y%m%d_%H%M%S)

        # Copy debug logs to S3
        cp /tmp/import_debug.log /mnt/s3/failed/import_debug.$(date +%Y%m%d_%H%M%S).log

        # Create error flag file
        echo "Import failed at $(date)" > /mnt/s3/import_error.txt
        return 1
    fi
}

# Initial refresh of the mount
refresh_s3fs_mount

# Main watch loop combining inotify and periodic checks
(
    # Watch for file system events
    inotifywait -m -e create,moved_to /mnt/s3 &
    INOTIFY_PID=$!

    while true; do
        # Refresh the mount before checking
        refresh_s3fs_mount

        # Check if file exists (periodic check)
        if [ -f "/mnt/s3/${license_server_name}.zip" ]; then
            echo "File found through periodic check"
            process_license_file
            if [ $? -eq 0 ]; then
                kill $INOTIFY_PID
                exit 0
            fi
        fi

        sleep 10
    done
) &

# Wait for either inotify events or periodic checks
while read -r directory events filename; do
    echo "Event '$events' detected on file: $filename"

    # Refresh the mount when an event is detected
    refresh_s3fs_mount

    if [ "$filename" = "${license_server_name}.zip" ]; then
        echo "Target file detected through inotify"
        process_license_file
        if [ $? -eq 0 ]; then
            exit 0
        fi
    fi
done < <(inotifywait -m -e create,moved_to /mnt/s3)
WATCHSCRIPT

# Make the watch script executable and set ownership
chmod +x /opt/UnityLicensingServer/watch_for_license_upload.sh
chown ubuntu:ubuntu /opt/UnityLicensingServer/watch_for_license_upload.sh

# Create the systemd service
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Creating systemd service for license watch..."
cat << WATCHSERVICE > /etc/systemd/system/unity-license-watch.service
[Unit]
Description=Unity License File Watch Service
After=network.target unity-license-server.service

[Service]
Type=simple
User=ubuntu
Group=unity-licensing-server
WorkingDirectory=/opt/UnityLicensingServer
ExecStart=/bin/bash -l -c '/opt/UnityLicensingServer/watch_for_license_upload.sh'
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
WATCHSERVICE

# Ensure proper ownership of all Unity License Server files
chown -R ubuntu:ubuntu /opt/UnityLicensingServer

# Configure sudo access for the ubuntu user to manage the service without password
echo "ubuntu ALL=(ALL) NOPASSWD: /bin/systemctl restart unity-license-server" > /etc/sudoers.d/unity-license
echo "ubuntu ALL=(ALL) NOPASSWD: /bin/systemctl stop unity-license-watch" >> /etc/sudoers.d/unity-license
echo "ubuntu ALL=(ALL) NOPASSWD: /opt/UnityLicensingServer/Unity.Licensing.Server" >> /etc/sudoers.d/unity-license
chmod 440 /etc/sudoers.d/unity-license

# Enable and start the watch service
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Enabling and starting license watch service..."
systemctl daemon-reload
systemctl enable unity-license-watch
systemctl start unity-license-watch

echo "[$(date '+%Y-%m-%d %H:%M:%S')] License watch daemon setup completed"
