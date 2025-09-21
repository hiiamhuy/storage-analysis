#!/bin/bash

# SSH Fix Script for WSL/Linux
# Addresses common SSH agent and key issues

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== SSH CONFIGURATION FIX ===${NC}"
echo "Generated: $(date)"
echo "================================="
echo

# Check current SSH setup
echo -e "${YELLOW}[STEP 1] Checking current SSH setup...${NC}"
echo "SSH directory contents:"
ls -la ~/.ssh/ 2>/dev/null || echo "~/.ssh directory not found"
echo

echo "SSH agent status:"
if [ -n "$SSH_AUTH_SOCK" ]; then
    echo "SSH agent socket: $SSH_AUTH_SOCK"
    ssh-add -l 2>/dev/null || echo "No SSH keys loaded in agent"
else
    echo "SSH agent not running"
fi
echo

# Check for private key
echo -e "${YELLOW}[STEP 2] Checking for SSH private key...${NC}"
if [ -f ~/.ssh/id_rsa ]; then
    echo -e "${GREEN}✓ Private key found: ~/.ssh/id_rsa${NC}"
    ls -la ~/.ssh/id_rsa
else
    echo -e "${RED}✗ Private key not found: ~/.ssh/id_rsa${NC}"
    echo "Need to generate SSH keys or copy existing ones"
fi
echo

# Start SSH agent if not running
echo -e "${YELLOW}[STEP 3] Starting SSH agent...${NC}"
if [ -z "$SSH_AUTH_SOCK" ]; then
    echo "Starting SSH agent..."
    eval "$(ssh-agent -s)"
    echo -e "${GREEN}✓ SSH agent started${NC}"
else
    echo -e "${GREEN}✓ SSH agent already running${NC}"
fi
echo

# Add SSH key if private key exists
echo -e "${YELLOW}[STEP 4] Adding SSH key to agent...${NC}"
if [ -f ~/.ssh/id_rsa ]; then
    # Check key permissions
    PERMS=$(stat -c "%a" ~/.ssh/id_rsa)
    if [ "$PERMS" != "600" ]; then
        echo "Fixing SSH key permissions..."
        chmod 600 ~/.ssh/id_rsa
        echo -e "${GREEN}✓ Fixed key permissions (set to 600)${NC}"
    fi

    # Add key to agent
    ssh-add ~/.ssh/id_rsa 2>/dev/null && echo -e "${GREEN}✓ SSH key added to agent${NC}" || echo -e "${RED}✗ Failed to add SSH key${NC}"
else
    echo -e "${YELLOW}⚠ No private key to add${NC}"
fi
echo

# Test SSH agent
echo -e "${YELLOW}[STEP 5] Testing SSH agent...${NC}"
echo "Keys in SSH agent:"
ssh-add -l 2>/dev/null || echo "No keys loaded in agent"
echo

# Generate new keys if needed
if [ ! -f ~/.ssh/id_rsa ]; then
    echo -e "${YELLOW}[STEP 6] Generating new SSH keys...${NC}"
    read -p "Generate new SSH keys? (y/N): " generate_keys
    if [[ "$generate_keys" =~ ^[Yy]$ ]]; then
        read -p "Enter your email for SSH key: " email
        ssh-keygen -t rsa -b 4096 -C "$email" -f ~/.ssh/id_rsa
        echo -e "${GREEN}✓ New SSH keys generated${NC}"

        # Add to agent
        eval "$(ssh-agent -s)"
        ssh-add ~/.ssh/id_rsa

        echo
        echo -e "${YELLOW}IMPORTANT: Add this public key to your Pantheon account:${NC}"
        echo "=========================================================="
        cat ~/.ssh/id_rsa.pub
        echo "=========================================================="
        echo "1. Go to https://dashboard.pantheon.io/account#ssh-keys"
        echo "2. Click 'Add Key'"
        echo "3. Paste the key above"
        echo "4. Save"
    fi
else
    echo -e "${YELLOW}[STEP 6] SSH keys exist - skipping generation${NC}"
    echo "Your public key (add to Pantheon if not already done):"
    echo "======================================================"
    cat ~/.ssh/id_rsa.pub 2>/dev/null || echo "Could not read public key"
    echo "======================================================"
fi
echo

# Test connection to Pantheon
echo -e "${YELLOW}[STEP 7] Testing connection to Pantheon...${NC}"
if [ $# -gt 0 ]; then
    SITE_NAME=$1
    ENV=${2:-"dev"}
    echo "Testing SSH connection to $SITE_NAME.$ENV..."

    timeout 10 terminus env:ssh $SITE_NAME.$ENV -- "echo 'SSH test successful'" 2>&1 || {
        echo -e "${RED}✗ SSH connection still failing${NC}"
        echo "Next steps:"
        echo "1. Ensure public key is added to Pantheon dashboard"
        echo "2. Wait a few minutes for key propagation"
        echo "3. Try again"
    }
else
    echo "No site specified - skipping connection test"
    echo "Usage: $0 [site-name] [environment]"
fi

echo
echo -e "${BLUE}=== SSH CONFIGURATION FIX COMPLETE ===${NC}"

# WSL-specific notes
echo
echo -e "${YELLOW}WSL-SPECIFIC NOTES:${NC}"
echo "==================="
echo "• SSH agent doesn't persist between WSL sessions"
echo "• Add this to ~/.bashrc for automatic SSH agent setup:"
echo "  eval \"\$(ssh-agent -s)\" && ssh-add ~/.ssh/id_rsa 2>/dev/null"
echo "• Or use Windows SSH agent integration"