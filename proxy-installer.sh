#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Helper Functions ---

# Generates a random 5-character alphanumeric string.
random() {
    tr </dev/urandom -dc A-Za-z0-9 | head -c5
    echo
}

# Generates a random IPv6 /64 subnet.
# Expects the IPv6 prefix as the first argument.
gen64() {
    local array=(1 2 3 4 5 6 7 8 9 0 a b c d e f)
    ip64() {
        echo "${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}"
    }
    echo "$1:$(ip64):$(ip64):$(ip64):$(ip64)"
}

# --- Core Functions ---

# Downloads and compiles the latest version of 3proxy.
install_3proxy() {
    echo "INFO: Fetching the latest 3proxy version..."
    API_RESPONSE=$(curl -s https://api.github.com/repos/z3APA3A/3proxy/releases/latest)
    LATEST_URL=$(echo "$API_RESPONSE" | awk -F '"' '/browser_download_url.*tar.gz/ {print $4}')

    if [ -z "$LATEST_URL" ]; then
        echo "ERROR: Could not fetch the latest 3proxy version URL. Exiting." >&2
        echo "INFO: Full API response was:" >&2
        echo "$API_RESPONSE" >&2
        exit 1
    fi
    echo "INFO: Latest version URL: ${LATEST_URL}"

    echo "INFO: Downloading and compiling 3proxy..."
    # Get the filename from the URL (e.g., 3proxy-0.9.4.tar.gz)
    FILENAME=$(basename "$LATEST_URL")
    # Get the directory name from the filename (e.g., 3proxy-0.9.4)
    DIR_NAME=$(echo "$FILENAME" | sed 's/\.tar\.gz//')

    curl -sL "$LATEST_URL" | tar -zxf -
    cd "$DIR_NAME"
    make -f Makefile.Linux
    mkdir -p /usr/local/etc/3proxy/bin/
    cp src/3proxy /usr/local/etc/3proxy/bin/

    # The rest of the installation (service files) will be handled by another function.

    cd "$WORKDIR"
    echo "INFO: 3proxy compilation complete."
}

# Generates the data file with proxy details.
gen_data() {
    echo "INFO: Generating proxy data for auth mode: ${AUTH_MODE}..."
    rm -f "$WORKDATA"

    # Use a case statement to handle different auth modes
    case "$AUTH_MODE" in
        "random")
            seq "$START_PORT" "$LAST_PORT" | while read -r port; do
                echo "usr$(random)/pass$(random)/${IP4}/${port}/$(gen64 "${IP6_PREFIX}")" >> "$WORKDATA"
            done
            ;;
        "static")
            seq "$START_PORT" "$LAST_PORT" | while read -r port; do
                echo "${STATIC_USER}/${STATIC_PASS}/${IP4}/${port}/$(gen64 "${IP6_PREFIX}")" >> "$WORKDATA"
            done
            ;;
        "none")
            seq "$START_PORT" "$LAST_PORT" | while read -r port; do
                echo "none/none/${IP4}/${port}/$(gen64 "${IP6_PREFIX}")" >> "$WORKDATA"
            done
            ;;
    esac
    echo "INFO: Proxy data generated at ${WORKDATA}"
}

# Generates the 3proxy configuration file.
gen_3proxy_config() {
    echo "INFO: Generating 3proxy configuration for auth mode: ${AUTH_MODE}..."

    # Start with a clean config file
    > /usr/local/etc/3proxy/3proxy.cfg

    # Add logging directives if logging is enabled
    if [ "$LOGGING_ENABLED" = true ]; then
        echo "INFO: Logging enabled."
        cat >> /usr/local/etc/3proxy/3proxy.cfg <<EOF
nolog
log /usr/local/etc/3proxy/logs/3proxy.log D
logformat "- +_L%t.%.%N %I %O %U %C:%p %T"
EOF
    fi

    # Add the basic, common configuration
    cat >> /usr/local/etc/3proxy/3proxy.cfg <<EOF
daemon
maxconn 1000
nserver 8.8.8.8
nserver 8.8.4.4
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
setgid 65535
setuid 65535
flush
EOF

    # Add configuration sections based on auth mode
    if [ "$AUTH_MODE" != "none" ]; then
        echo "auth strong" >> /usr/local/etc/3proxy/3proxy.cfg
        if [ "$AUTH_MODE" = "static" ]; then
            echo "users ${STATIC_USER}:CL:${STATIC_PASS}" >> /usr/local/etc/3proxy/3proxy.cfg
            awk -F "/" -v user="${STATIC_USER}" '{print "allow " user "\nsocks -6 -p" $4 " -i" $3 " -e" $5 "\nflush"}' "${WORKDATA}" >> /usr/local/etc/3proxy/3proxy.cfg
        else # random
            echo "users \$(awk -F "/" 'BEGIN{ORS="";} {print \$1 \":CL:\" \$2 \" \"}' "${WORKDATA}")" >> /usr/local/etc/3proxy/3proxy.cfg
            awk -F "/" '{print "allow " $1 "\nsocks -6 -p" $4 " -i" $3 " -e" $5 "\nflush"}' "${WORKDATA}" >> /usr/local/etc/3proxy/3proxy.cfg
        fi
    else # none
        awk -F "/" '{print "socks -6 -p" $4 " -i" $3 " -e" $5 "\nflush"}' "${WORKDATA}" >> /usr/local/etc/3proxy/3proxy.cfg
    fi
    echo "INFO: 3proxy configuration generated."
}

# Generates firewall rules.
gen_iptables() {
    awk -F "/" '{print "iptables -I INPUT -p tcp --dport " $4 " -m state --state NEW -j ACCEPT"}' "${WORKDATA}" > "${WORKDIR}/boot_iptables.sh"
    chmod +x "${WORKDIR}/boot_iptables.sh"
    echo "INFO: Firewall rules script generated at ${WORKDIR}/boot_iptables.sh"
}

# Generates network interface configuration commands.
gen_ifconfig() {
    awk -F "/" -v iface="${INTERFACE}" '{print "ifconfig " iface " inet6 add " $5 "/64"}' "${WORKDATA}" > "${WORKDIR}/boot_ifconfig.sh"
    chmod +x "${WORKDIR}/boot_ifconfig.sh"
    echo "INFO: Network interface script generated at ${WORKDIR}/boot_ifconfig.sh"
}

# Creates the final proxy list file for the user.
gen_proxy_file_for_user() {
    echo "INFO: Generating proxy list file..."
    if [ "$AUTH_MODE" = "none" ]; then
        # Format: IP:PORT
        awk -F "/" '{print $3 ":" $4}' "${WORKDATA}" > proxy-list.txt
    else
        # Format: IP:PORT:USER:PASS
        awk -F "/" '{print $3 ":" $4 ":" $1 ":" $2}' "${WORKDATA}" > proxy-list.txt
    fi
    echo "INFO: Proxy list saved to $(pwd)/proxy-list.txt"
}

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

# --- Main Execution ---

# Function to display usage information
usage() {
    echo "Usage: $0 -c <count> -m <mode> [options]"
    echo "  -c, --count       Number of proxies to create (required)."
    echo "  -m, --mode        Authentication mode: 'none', 'random', 'static' (required)."
    echo "  -p, --port        Starting port number (default: 10000)."
    echo "  -u, --user        Username for 'static' auth mode."
    echo "  -P, --password    Password for 'static' auth mode."
    echo "  -l, --log         Enable detailed logging to /usr/local/etc/3proxy/logs/3proxy.log."
    echo "  -h, --help        Display this help message."
    exit 1
}

main() {
    # --- Default Configuration ---
    START_PORT=10000
    AUTH_MODE=""
    COUNT=0
    STATIC_USER=""
    STATIC_PASS=""
    LOGGING_ENABLED=false

    # --- Argument Parsing ---
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -c|--count)
                COUNT="$2"
                shift 2
                ;;
            -p|--port)
                START_PORT="$2"
                shift 2
                ;;
            -m|--mode)
                AUTH_MODE="$2"
                shift 2
                ;;
            -u|--user)
                STATIC_USER="$2"
                shift 2
                ;;
            -P|--password)
                STATIC_PASS="$2"
                shift 2
                ;;
            -l|--log)
                LOGGING_ENABLED=true
                shift 1
                ;;
            -h|--help)
                usage
                ;;
            *)
                echo "Unknown option: $1"
                usage
                ;;
        esac
    done

    # --- Sanity Checks ---
    if [ "$(id -u)" -ne 0 ]; then
        echo "ERROR: This script must be run as root." >&2
        exit 1
    fi

    if [ "$COUNT" -le 0 ] || [ -z "$AUTH_MODE" ]; then
        echo "ERROR: --count and --mode are required."
        usage
    fi

    if [ "$AUTH_MODE" != "none" ] && [ "$AUTH_MODE" != "random" ] && [ "$AUTH_MODE" != "static" ]; then
        echo "ERROR: Invalid auth mode. Must be one of 'none', 'random', or 'static'."
        usage
    fi

    if [ "$AUTH_MODE" = "static" ] && ([ -z "$STATIC_USER" ] || [ -z "$STATIC_PASS" ]); then
        echo "ERROR: --user and --password are required for 'static' auth mode."
        usage
    fi

    # --- Dependency Installation ---
    echo "INFO: Installing required packages (gcc, net-tools, bsdtar, zip, curl)..."
    # Suppressing output for cleanliness, but errors will still cause exit due to 'set -e'
    yum -y install gcc net-tools bsdtar zip curl >/dev/null

    # --- Environment Setup ---
    WORKDIR="/home/proxy-installer"
    WORKDATA="${WORKDIR}/data.txt"
    echo "INFO: Using working directory: ${WORKDIR}"
    mkdir -p "$WORKDIR"
    cd "$WORKDIR"

    # Clean up previous runs
    rm -f "$WORKDATA" "boot_*.sh" "proxy-list.txt"

    install_3proxy

    # --- Network Detection ---
    echo "INFO: Detecting network configuration..."
    IP4=$(curl -4 -s icanhazip.com)
    IP6_PREFIX=$(curl -6 -s icanhazip.com | cut -f1-4 -d':')
    INTERFACE=$(ip -o -4 route show to default | awk '{print $5}')
    echo "INFO: Public IPv4 detected: ${IP4}"
    echo "INFO: Public IPv6 prefix detected: ${IP6_PREFIX}"
    echo "INFO: Default network interface detected: ${INTERFACE}"

    # --- Generation Phase ---
    LAST_PORT=$(($START_PORT + $COUNT - 1))

    gen_data
    gen_3proxy_config
    gen_iptables
    gen_ifconfig

    # --- System Configuration ---
    create_systemd_service

    # --- Service Start ---
    echo "INFO: Applying configurations and starting proxy service..."
    bash "${WORKDIR}/boot_iptables.sh"
    bash "${WORKDIR}/boot_ifconfig.sh"
    echo "INFO: Restarting 3proxy service..."
    systemctl restart 3proxy

    # --- Output ---
    gen_proxy_file_for_user

    echo "SUCCESS: Proxy installation and configuration complete."
}

# Run the main function
main "$@"
