#!/bin/bash

# Connection Test Script
# Tests SSH connectivity and remote command execution

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== TERMINUS CONNECTION TEST ===${NC}"
echo "Generated: $(date)"
echo "=============================================="
echo

# Check if site name provided
if [ $# -eq 0 ]; then
    echo -e "${RED}ERROR: Site name required${NC}"
    echo "Usage: $0 <site-name> [environment]"
    echo "Example: $0 uwsurgery dev"
    exit 1
fi

SITE_NAME=$1
ENVIRONMENT=${2:-"dev"}

echo -e "${YELLOW}Testing connection to: $SITE_NAME.$ENVIRONMENT${NC}"
echo

# Test 1: Basic Terminus authentication
echo -e "${YELLOW}[TEST 1] Verifying Terminus authentication...${NC}"
if terminus auth:whoami &> /dev/null; then
    WHOAMI=$(terminus auth:whoami 2>/dev/null)
    echo -e "${GREEN}✓ Authenticated as: $WHOAMI${NC}"
else
    echo -e "${RED}✗ ERROR: Not authenticated${NC}"
    exit 1
fi
echo

# Test 2: Environment accessibility
echo -e "${YELLOW}[TEST 2] Testing environment accessibility...${NC}"
if terminus env:info $SITE_NAME.$ENVIRONMENT --field=id &> /dev/null; then
    ENV_ID=$(terminus env:info $SITE_NAME.$ENVIRONMENT --field=id 2>/dev/null)
    echo -e "${GREEN}✓ Environment accessible: $ENV_ID${NC}"
else
    echo -e "${RED}✗ ERROR: Cannot access $SITE_NAME.$ENVIRONMENT${NC}"
    echo "Check if site name and environment are correct"
    exit 1
fi
echo

# Test 3: Wake environment
echo -e "${YELLOW}[TEST 3] Waking environment...${NC}"
if terminus env:wake $SITE_NAME.$ENVIRONMENT &> /dev/null; then
    echo -e "${GREEN}✓ Environment awakened successfully${NC}"
else
    echo -e "${YELLOW}⚠ Warning: Could not wake environment (may already be awake)${NC}"
fi
echo

# Test 4: Get connection info
echo -e "${YELLOW}[TEST 4] Getting connection information...${NC}"
if terminus connection:info $SITE_NAME.$ENVIRONMENT --format=table &> /dev/null; then
    echo -e "${GREEN}✓ Connection info available:${NC}"
    terminus connection:info $SITE_NAME.$ENVIRONMENT --format=table 2>/dev/null
else
    echo -e "${RED}✗ ERROR: Cannot get connection info${NC}"
fi
echo

# Test 5: Basic SSH connectivity
echo -e "${YELLOW}[TEST 5] Testing basic SSH connectivity...${NC}"
SSH_OUTPUT=$(terminus env:ssh $SITE_NAME.$ENVIRONMENT -- "echo 'SSH connection successful'" 2>&1)
SSH_EXIT_CODE=$?

if [ $SSH_EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}✓ SSH connection successful${NC}"
    echo "Output: $SSH_OUTPUT"
else
    echo -e "${RED}✗ ERROR: SSH connection failed${NC}"
    echo "Error output: $SSH_OUTPUT"
    echo
    echo "This is likely the source of your 'Permission denied (publickey)' error"
    echo "Possible solutions:"
    echo "1. Check SSH key configuration"
    echo "2. Ensure your SSH key is added to your Pantheon account"
    echo "3. Try regenerating SSH keys in your Pantheon dashboard"
fi
echo

# Test 6: Simple remote command
if [ $SSH_EXIT_CODE -eq 0 ]; then
    echo -e "${YELLOW}[TEST 6] Testing simple remote commands...${NC}"

    # Test pwd
    PWD_OUTPUT=$(terminus env:ssh $SITE_NAME.$ENVIRONMENT -- "pwd" 2>/dev/null)
    echo -e "${GREEN}✓ Working directory: $PWD_OUTPUT${NC}"

    # Test ls
    LS_OUTPUT=$(terminus env:ssh $SITE_NAME.$ENVIRONMENT -- "ls -la | head -5" 2>/dev/null)
    echo -e "${GREEN}✓ Directory listing:${NC}"
    echo "$LS_OUTPUT"
else
    echo -e "${YELLOW}[TEST 6] Skipped - SSH connection failed${NC}"
fi
echo

# Test 7: Platform-specific command test
echo -e "${YELLOW}[TEST 7] Testing platform-specific commands...${NC}"
FRAMEWORK=$(terminus site:info $SITE_NAME --field=framework 2>/dev/null)
echo "Site framework: $FRAMEWORK"

case $FRAMEWORK in
    "wordpress")
        echo "Testing WP-CLI remote connection..."
        WP_OUTPUT=$(terminus remote:wp $SITE_NAME.$ENVIRONMENT -- "--version" 2>&1)
        WP_EXIT_CODE=$?

        if [ $WP_EXIT_CODE -eq 0 ]; then
            echo -e "${GREEN}✓ WP-CLI connection successful${NC}"
            echo "$WP_OUTPUT"
        else
            echo -e "${RED}✗ ERROR: WP-CLI connection failed${NC}"
            echo "Error: $WP_OUTPUT"
        fi
        ;;
    "drupal"|"drupal8"|"drupal9"|"drupal10")
        echo "Testing Drush remote connection..."
        DRUSH_OUTPUT=$(terminus remote:drush $SITE_NAME.$ENVIRONMENT -- "status" 2>&1)
        DRUSH_EXIT_CODE=$?

        if [ $DRUSH_EXIT_CODE -eq 0 ]; then
            echo -e "${GREEN}✓ Drush connection successful${NC}"
            echo "$DRUSH_OUTPUT" | head -10
        else
            echo -e "${RED}✗ ERROR: Drush connection failed${NC}"
            echo "Error: $DRUSH_OUTPUT"
        fi
        ;;
    *)
        echo "Generic platform - SSH-only testing"
        ;;
esac

echo
echo -e "${BLUE}=== CONNECTION TEST COMPLETE ===${NC}"