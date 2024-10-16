#!/bin/sh

set -e

export VAULT_ADDR=${VAULT_ADDR}

# Function to check if Vault is initialized
is_initialized() {
    vault status | grep -q 'Initialized.*true'
}

# Function to check if Vault is sealed
is_sealed() {
    vault status | grep -q 'Sealed.*true'
}

# Start Vault in server mode
vault server -config=/vault/config/vault.hcl &

# Capture the Vault server PID
VAULT_PID=$!

# Wait for Vault to start
sleep 5

# Check if Vault is initialized
if ! is_initialized; then
    echo "Initializing Vault..."

    # Initialize Vault with key shares and key threshold
    vault operator init -key-shares=1 -key-threshold=1 >/vault/keys.txt

    # Extract Unseal Key and Root Token
    UNSEAL_KEY=$(grep 'Unseal Key 1:' /vault/keys.txt | awk '{print $NF}')
    ROOT_TOKEN=$(grep 'Initial Root Token:' /vault/keys.txt | awk '{print $NF}')

    # Unseal Vault
    vault operator unseal $UNSEAL_KEY

    # Login with Root Token
    vault login $ROOT_TOKEN

    echo "Vault initialized and unsealed."

elif is_sealed; then
    echo "Vault is sealed. Unsealing..."

    # Extract Unseal Key from stored keys
    if [ -f /vault/keys.txt ]; then
        UNSEAL_KEY=$(grep 'Unseal Key 1:' /vault/keys.txt | awk '{print $NF}')
        vault operator unseal $UNSEAL_KEY
        echo "Vault unsealed."
    else
        echo "Unseal key not found. Cannot unseal Vault."
        kill $VAULT_PID
        exit 1
    fi
else
    echo "Vault is already initialized and unsealed."
fi

# Wait for the Vault server process to exit
wait $VAULT_PID
