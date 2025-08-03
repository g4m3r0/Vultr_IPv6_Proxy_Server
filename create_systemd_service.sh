# Creates the systemd service file for 3proxy.
create_systemd_service() {
    echo "INFO: Creating systemd service file..."
    cat > /etc/systemd/system/3proxy.service <<EOF
[Unit]
Description=3proxy Proxy Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/etc/3proxy/bin/3proxy /usr/local/etc/3proxy/3proxy.cfg
ExecStop=/bin/kill \$(cat /usr/local/etc/3proxy/3proxy.pid)
RemainAfterExit=yes
Restart=on-failure
LimitNOFILE=10048
User=nobody
Group=nobody

[Install]
WantedBy=multi-user.target
EOF

    echo "INFO: Reloading systemd daemon..."
    systemctl daemon-reload
    echo "INFO: Enabling 3proxy service to start on boot..."
    systemctl enable 3proxy
}
