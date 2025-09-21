#!/bin/bash

# Debug Information Script
# Collects system and environment information for troubleshooting

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== DEBUG INFORMATION COLLECTOR ===${NC}"
echo "Generated: $(date)"
echo "========================================"
echo

# System Information
echo -e "${YELLOW}[SYSTEM] Operating System Information${NC}"
echo "======================================"
echo "OS: $(uname -a)"
echo "Distribution: $(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d= -f2 | tr -d '\"' || echo 'Unknown')"
echo "Kernel: $(uname -r)"
echo "Architecture: $(uname -m)"

# Check if running in WSL
if grep -qi microsoft /proc/version 2>/dev/null; then
    echo -e "${YELLOW}WSL Environment Detected${NC}"
    WSL_VERSION=$(wsl.exe -l -v 2>/dev/null | grep -E '^\*' | awk '{print $3}' || echo "Unknown")
    echo "WSL Version: $WSL_VERSION"
fi
echo

# User Information
echo -e "${YELLOW}[USER] User Environment${NC}"
echo "======================"
echo "Current user: $(whoami)"
echo "Home directory: $HOME"
echo "Working directory: $(pwd)"
echo "Shell: $SHELL"
echo "PATH: $PATH"
echo

# SSH Information
echo -e "${YELLOW}[SSH] SSH Configuration${NC}"
echo "======================="
echo "SSH client version:"
ssh -V 2>&1 | head -1

echo
echo "SSH key files in ~/.ssh:"
if [ -d ~/.ssh ]; then
    ls -la ~/.ssh/ | grep -E '\.(pub|pem)$' || echo "No SSH key files found"
else
    echo "~/.ssh directory not found"
fi

echo
echo "SSH agent status:"
if [ -n "$SSH_AUTH_SOCK" ]; then
    echo "SSH agent socket: $SSH_AUTH_SOCK"
    ssh-add -l 2>/dev/null || echo "No SSH keys loaded in agent"
else
    echo "SSH agent not running or not configured"
fi
echo

# Terminus Information
echo -e "${YELLOW}[TERMINUS] Terminus CLI Information${NC}"
echo "===================================="
if command -v terminus &> /dev/null; then
    echo "Terminus path: $(which terminus)"
    echo "Terminus version: $(terminus --version 2>/dev/null | head -1)"

    echo
    echo "Terminus configuration:"
    if [ -f ~/.terminus/config.yml ]; then
        echo "Config file exists: ~/.terminus/config.yml"
    else
        echo "Config file not found: ~/.terminus/config.yml"
    fi

    echo
    echo "Authentication status:"
    if terminus auth:whoami &> /dev/null; then
        WHOAMI=$(terminus auth:whoami 2>/dev/null)
        echo -e "${GREEN}✓ Authenticated as: $WHOAMI${NC}"

        echo
        echo "Available sites:"
        SITE_COUNT=$(terminus site:list --format=count 2>/dev/null || echo "0")
        echo "Total accessible sites: $SITE_COUNT"

        if [ "$SITE_COUNT" -gt 0 ]; then
            echo "Recent sites:"
            terminus site:list --format=table --fields=name,framework,created 2>/dev/null | head -5
        fi
    else
        echo -e "${RED}✗ Not authenticated${NC}"
    fi
else
    echo -e "${RED}✗ Terminus CLI not installed${NC}"
fi
echo

# Network Information
echo -e "${YELLOW}[NETWORK] Network Configuration${NC}"
echo "==============================="
echo "Network interfaces:"
ip addr show 2>/dev/null | grep -E '^[0-9]+:' | head -5 || ifconfig 2>/dev/null | grep -E '^[a-z]' | head -5 || echo "Could not get network info"

echo
echo "DNS configuration:"
if [ -f /etc/resolv.conf ]; then
    echo "Nameservers:"
    grep nameserver /etc/resolv.conf | head -3
else
    echo "Could not read DNS configuration"
fi

echo
echo "Connectivity test to Pantheon:"
if ping -c 1 pantheon.io >/dev/null 2>&1; then
    echo -e "${GREEN}✓ Can reach pantheon.io${NC}"
else
    echo -e "${RED}✗ Cannot reach pantheon.io${NC}"
fi
echo

# Environment Variables
echo -e "${YELLOW}[ENV] Relevant Environment Variables${NC}"
echo "====================================="
env | grep -E '^(HOME|USER|SHELL|PATH|SSH_|TERMINUS_)' | sort

# If site name provided, test specific site connectivity
if [ $# -gt 0 ]; then
    SITE_NAME=$1
    echo
    echo -e "${YELLOW}[SITE] Site-Specific Debug for: $SITE_NAME${NC}"
    echo "=============================================="

    if command -v terminus &> /dev/null && terminus auth:whoami &> /dev/null; then
        if terminus site:info $SITE_NAME --field=name &> /dev/null; then
            echo -e "${GREEN}✓ Site accessible${NC}"

            echo "Site framework: $(terminus site:info $SITE_NAME --field=framework 2>/dev/null)"
            echo "Site created: $(terminus site:info $SITE_NAME --field=created 2>/dev/null)"

            echo
            echo "Environment connectivity:"
            for env in dev test live; do
                if terminus env:info $SITE_NAME.$env --field=id &> /dev/null; then
                    echo -e "  ${GREEN}✓ $env${NC}"

                    # Test SSH connectivity
                    SSH_TEST=$(terminus env:ssh $SITE_NAME.$env -- "echo 'test'" 2>&1)
                    if echo "$SSH_TEST" | grep -q "test"; then
                        echo -e "    ${GREEN}✓ SSH working${NC}"
                    else
                        echo -e "    ${RED}✗ SSH failed: $SSH_TEST${NC}"
                    fi
                else
                    echo -e "  ${RED}✗ $env (not accessible)${NC}"
                fi
            done
        else
            echo -e "${RED}✗ Site not accessible${NC}"
        fi
    else
        echo "Skipping site tests (Terminus not available or not authenticated)"
    fi
fi

echo
echo -e "${BLUE}=== DEBUG INFORMATION COMPLETE ===${NC}"
echo "Copy this output when reporting issues for faster troubleshooting."