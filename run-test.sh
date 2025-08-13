#!/bin/bash

# Simple test runner script
# Usage: ./run-test.sh [config-file]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${1:-test-config.env}"

# Load configuration
if [[ -f "$CONFIG_FILE" ]]; then
    echo "Loading configuration from: $CONFIG_FILE"
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
else
    echo "Configuration file not found: $CONFIG_FILE"
    echo "Using default values..."
fi

# Run the test
exec "$SCRIPT_DIR/test-proxmox-deployment.sh"