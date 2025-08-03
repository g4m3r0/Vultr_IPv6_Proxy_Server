# IPv6 Proxy Installer

This script automates the setup of a large number of IPv6 proxy servers using 3proxy on CentOS/RHEL-based systems. It consolidates the functionality of several previous scripts into a single, flexible, and robust installer.

## Features

-   **Flexible Authentication:** Supports three authentication modes:
    -   `none`: Proxies with no authentication.
    -   `random`: Each proxy gets a unique, randomly generated username and password.
    -   `static`: All proxies share a single, user-defined username and password.
-   **Customizable:** Allows configuration of the number of proxies and the starting port via command-line arguments.
-   **Secure:** Saves the generated proxy list to a local file instead of uploading to a public service.
-   **Robust:** Includes error handling and sanity checks.

## Prerequisites

-   A server running a `yum`-based Linux distribution (e.g., CentOS, RHEL).
-   Root or sudo privileges on the server.
-   A dedicated `/64` IPv6 block routed to your server's main IPv6 address.

## Usage

The script is controlled via command-line arguments.

```sh
./proxy-installer.sh -c <count> -m <mode> [options]
```

### Required Arguments

-   `-c`, `--count <number>`: The total number of proxies you want to create.
-   `-m`, `--mode <mode>`: The authentication mode. Must be one of `none`, `random`, or `static`.

### Optional Arguments

-   `-p`, `--port <number>`: The starting port for the proxies. (Default: `3128`)
-   `-u`, `--user <username>`: The username for `static` authentication mode. (Required if mode is `static`)
-   `-P`, `--password <password>`: The password for `static` authentication mode. (Required if mode is `static`)
-   `-h`, `--help`: Displays the help message.

## Examples

First, make the script executable:
```sh
chmod +x proxy-installer.sh
```

### Example 1: Create 500 Proxies with No Authentication

This will create 500 proxies starting from port 3128. The proxy list will be in the format `IP:PORT`.

```sh
./proxy-installer.sh --count 500 --mode none
```

### Example 2: Create 1000 Proxies with Random Usernames/Passwords

This will create 1000 proxies, each with a unique, randomly generated username and password. The proxy list will be in the format `IP:PORT:USER:PASS`.

```sh
./proxy-installer.sh -c 1000 -m random -p 20000
```

### Example 3: Create 200 Proxies with a Single Static Username/Password

This will create 200 proxies, all sharing the username `myuser` and the password `mypass123`.

```sh
./proxy-installer.sh -c 200 -m static -u myuser -P mypass123
```

## Output

After running, the script will create a file named `proxy-list.txt` in the working directory (`/home/proxy-installer`). The format of this file depends on the chosen authentication mode.
