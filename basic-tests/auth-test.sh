#!/bin/bash

# Basic Authentication Test Script
# Tests Terminus authentication and basic connectivity

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== TERMINUS AUTHENTICATION TEST ===${NC}"
echo "Generated: $(date)"
echo "=============================================="
echo

# Test 1: Check if Terminus is installed
echo -e "${YELLOW}[TEST 1] Checking Terminus installation...${NC}"
if command -v terminus &> /dev/null; then
    TERMINUS_VERSION=$(terminus --version 2>/dev/null | head -1)
    echo -e "${GREEN}✓ Terminus found: $TERMINUS_VERSION${NC}"
else
    echo -e "${RED}✗ ERROR: Terminus CLI not installed${NC}"
    echo "Please install Terminus CLI: https://pantheon.io/docs/terminus/install"
    exit 1
fi
echo

# Test 2: Check authentication status
echo -e "${YELLOW}[TEST 2] Checking authentication status...${NC}"
if terminus auth:whoami &> /dev/null; then
    WHOAMI=$(terminus auth:whoami 2>/dev/null)
    echo -e "${GREEN}✓ Authenticated as: $WHOAMI${NC}"
else
    echo -e "${RED}✗ ERROR: Not authenticated with Terminus${NC}"
    echo "Please run: terminus auth:login"
    echo "Recommended: Use machine tokens for automation"
    echo "https://pantheon.io/docs/machine-tokens"
    exit 1
fi
echo

# Test 3: List accessible sites
echo -e "${YELLOW}[TEST 3] Testing site access...${NC}"
SITE_COUNT=$(terminus site:list --format=count 2>/dev/null || echo "0")
if [ "$SITE_COUNT" -gt 0 ]; then
    echo -e "${GREEN}✓ Can access $SITE_COUNT sites${NC}"
    echo "Available sites:"
    terminus site:list --format=table --fields=name,framework,created 2>/dev/null | head -10
else
    echo -e "${RED}✗ ERROR: Cannot access any sites${NC}"
    echo "This could indicate permission or authentication issues"
fi
echo

# Test 4: Check specific site if provided
if [ $# -gt 0 ]; then
    SITE_NAME=$1
    echo -e "${YELLOW}[TEST 4] Testing specific site: $SITE_NAME${NC}"

    if terminus site:info $SITE_NAME --field=name &> /dev/null; then
        echo -e "${GREEN}✓ Site '$SITE_NAME' is accessible${NC}"

        # Get site info
        FRAMEWORK=$(terminus site:info $SITE_NAME --field=framework 2>/dev/null)
        CREATED=$(terminus site:info $SITE_NAME --field=created 2>/dev/null)
        echo "  Framework: $FRAMEWORK"
        echo "  Created: $CREATED"

        # Test environments
        echo "  Environments:"
        for env in dev test live; do
            if terminus env:info $SITE_NAME.$env --field=id &> /dev/null; then
                echo -e "    ${GREEN}✓ $env${NC}"
            else
                echo -e "    ${RED}✗ $env (not accessible)${NC}"
            fi
        done
    else
        echo -e "${RED}✗ ERROR: Site '$SITE_NAME' not found or not accessible${NC}"
    fi
else
    echo -e "${YELLOW}[TEST 4] Skipped - no site name provided${NC}"
    echo "Usage: $0 [site-name]"
fi

echo
echo -e "${BLUE}=== AUTHENTICATION TEST COMPLETE ===${NC}"