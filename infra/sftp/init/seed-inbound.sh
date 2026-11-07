#!/bin/bash
# Runs inside the atmoz/sftp container on start-up (/etc/sftp.d/*).
# Copies the sample supplier files into the user's inbound folder with the
# right owner, so the Mule app can read, move and delete them.
set -euo pipefail
home=/home/supplier
for dir in inbound processed error; do
    mkdir -p "$home/$dir"
done
cp -n /samples/*.csv "$home/inbound/" 2>/dev/null || true
chown -R 1001:100 "$home/inbound" "$home/processed" "$home/error"
