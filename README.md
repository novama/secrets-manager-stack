# Secrets Manager Stack

This repository provides a Docker Compose configuration to deploy HashiCorp Vault behind an Nginx reverse proxy. This setup is designed to manage secrets securely on-premises without incurring any costs, leveraging open-source tools.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Getting Started](#getting-started)
  - [Clone the Repository](#clone-the-repository)
  - [Directory Structure](#directory-structure)
  - [Environment Variables](#environment-variables)
- [Configuration](#configuration)
  - [Vault Configuration](#vault-configuration)
  - [Nginx Configuration](#nginx-configuration)
  - [Entrypoint Script](#entrypoint-script)
- [Running the Services](#running-the-services)
  - [Initialize and Unseal Vault](#initialize-and-unseal-vault)
- [Accessing Vault](#accessing-vault)
- [Stopping the Services](#stopping-the-services)
- [Data Persistence](#data-persistence)
- [Security Considerations](#security-considerations)
- [Troubleshooting](#troubleshooting)
- [License](#license)

---

## Overview

This project sets up HashiCorp Vault with an Nginx reverse proxy using Docker Compose. Vault is used for securely managing secrets, and Nginx serves as a reverse proxy to handle client requests and provide an additional layer of security.

## Architecture

- **Vault**: Handles secrets management and runs the Vault server.
- **Nginx**: Acts as a reverse proxy in front of Vault, forwarding client requests.

Both services are connected via a Docker network called `vault-net`.

## Prerequisites

- **Docker Engine** (version 19.03 or higher)
- **Docker Compose** (version 1.27 or higher)
- **Git** (to clone the repository)
- Basic knowledge of Docker and Docker Compose

## Getting Started

### Clone the Repository

```bash
git clone https://github.com/yourusername/vault-nginx-docker.git
cd vault-nginx-docker
```

### Directory Structure

Ensure your project directory has the following structure:

```
vault-nginx-docker/
├── docker-compose.yml
├── .env
├── config/
│   ├── vault/
│   │   ├── vault-config.hcl
│   │   ├── vault-entrypoint.sh
│   │   └── vault-keys.txt
│   └── nginx/
│       └── nginx-config.conf
├── data/
│   └── vault/   # Vault data will be stored here
└── README.md
```

- **docker-compose.yml**: Defines the Docker services.
- **.env**: Contains environment variables for the services.
- **config/**: Stores configuration files for Vault and Nginx.
- **data/**: Used for persisting Vault data.

### Environment Variables

Create a `.env` file in the project root with the following content:

```dotenv
VAULT_ADDR=http://0.0.0.0:8200
VAULT_API_ADDR=http://vault:8200
VAULT_LOG_LEVEL=info
```

- **VAULT_ADDR**: The address Vault listens on externally.
- **VAULT_API_ADDR**: The internal API address for Vault.
- **VAULT_LOG_LEVEL**: Logging level for Vault (e.g., debug, info, warn, error).

## Configuration

### Vault Configuration

Create a Vault configuration file at `config/vault/vault-config.hcl`:

```hcl
storage "file" {
  path = "/vault/data"
}

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = true
}

ui = true
```

- **storage "file"**: Uses the file system to store data at `/vault/data`.
- **listener "tcp"**: Listens on all network interfaces on port 8200 without TLS.
- **ui**: Enables the Vault web UI.

### Nginx Configuration

Create an Nginx configuration file at `config/nginx/nginx-config.conf`:

```nginx
worker_processes auto;

events {
    worker_connections 1024;
}

http {
    server {
        listen 80;
        server_name vault.secrets;

        location / {
            proxy_pass http://vault:8200;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }
    }
}
```

- **listen 80**: Nginx listens on port 80.
- **proxy_pass**: Forwards requests to the Vault service.

### Entrypoint Script

Create an entrypoint script for Vault at `config/vault/vault-entrypoint.sh`:

```bash
#!/bin/sh

set -e

export VAULT_ADDR=${VAULT_API_ADDR}

# Start Vault server in the background
vault server -config=/vault/config/vault.hcl &
VAULT_PID=$!

# Wait for Vault to start
sleep 5

# Check if Vault is initialized
if ! vault status | grep -q 'Initialized.*true'; then
  echo "Initializing Vault..."

  # Initialize Vault
  vault operator init -key-shares=1 -key-threshold=1 > /vault/keys.txt

  # Extract Unseal Key and Root Token
  UNSEAL_KEY=$(grep 'Unseal Key 1:' /vault/keys.txt | awk '{print $NF}')
  ROOT_TOKEN=$(grep 'Initial Root Token:' /vault/keys.txt | awk '{print $NF}')

  # Unseal Vault
  vault operator unseal $UNSEAL_KEY

  # Login with Root Token
  vault login $ROOT_TOKEN

  echo "Vault initialized and unsealed."
elif vault status | grep -q 'Sealed.*true'; then
  echo "Unsealing Vault..."

  # Unseal Vault
  UNSEAL_KEY=$(grep 'Unseal Key 1:' /vault/keys.txt | awk '{print $NF}')
  vault operator unseal $UNSEAL_KEY

  echo "Vault unsealed."
else
  echo "Vault is already initialized and unsealed."
fi

# Wait for the Vault process to exit
wait $VAULT_PID
```

**Make the script executable:**

```bash
chmod +x config/vault/vault-entrypoint.sh
```

## Running the Services

### Initialize and Unseal Vault

1. **Start the Docker Services:**

   ```bash
   docker-compose up -d
   ```

2. **Verify the Containers Are Running:**

   ```bash
   docker-compose ps
   ```

3. **Check the Logs:**

   ```bash
   docker-compose logs -f
   ```

   - Look for messages indicating that Vault has been initialized and unsealed.

## Accessing Vault

- **Vault UI:**

  Open your web browser and navigate to [http://localhost](http://localhost).

- **Vault CLI:**

  Use the following command to interact with Vault:

  ```bash
  docker exec -it vault vault status
  ```

- **Retrieve Unseal Key and Root Token:**

  The keys are stored in `config/vault/vault-keys.txt`.

  **Important:** Secure this file appropriately; it contains sensitive information.

## Stopping the Services

To stop and remove the containers, run:

```bash
docker-compose down
```

## Data Persistence

Vault data is persisted to the `data/vault` directory on the host machine, ensuring that your secrets and configurations are retained between restarts.

- **Volume Configuration in docker-compose.yml:**

  ```yaml
  volumes:
    vault-data:
      driver: local
      driver_opts:
        type: none
        device: ../data/vault
        o: bind
  ```

## Security Considerations

- **Unseal Keys and Root Token:**

  - **Secure Storage:** The unseal key and root token are stored in plaintext. Ensure `config/vault/vault-keys.txt` is secured and access is restricted.
  - **Avoid Committing to Version Control:** Do not commit the keys file to any version control system.

- **TLS Encryption:**

  - **Production Use:** It is highly recommended to enable TLS between Nginx and clients, and optionally between Nginx and Vault.
  - **Certificate Management:** If enabling TLS, manage SSL certificates appropriately.

- **Access Control:**

  - **Policies and Tokens:** Create specific policies and tokens for applications and users, avoiding the use of the root token for regular operations.

- **Firewall Rules:**

  - **Port Exposure:** Ensure only necessary ports are exposed and accessible.

- **Auto-Unseal Configuration:**

  - For production environments, consider configuring Vault's Auto-Unseal feature with a Key Management Service (KMS) to eliminate manual unsealing.

## Troubleshooting

- **Vault Container Exits Immediately:**

  - Ensure the entrypoint script is executable.
  - Check for syntax errors in the entrypoint script and configuration files.

- **Cannot Access Vault UI:**

  - Confirm that Nginx is running and properly configured.
  - Verify that port 80 is not being used by another service.

- **Error Messages in Logs:**

  - Use `docker-compose logs vault` and `docker-compose logs nginx` to inspect logs for errors.

- **Vault Not Unsealing Automatically:**

  - Ensure the unseal key is correctly stored in `vault-keys.txt`.
  - Verify that the entrypoint script has the correct logic to unseal Vault.

## License

This project is licensed under the [MIT License](LICENSE).

---

**Disclaimer:** This setup is intended for educational and development purposes. For production use, ensure that all security considerations are properly addressed.