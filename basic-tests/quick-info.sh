#!/bin/bash

# Quick Site Information Script
# Gets basic info without long-running size calculations

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== QUICK SITE INFORMATION ===${NC}"
echo "Generated: $(date)"
echo "============================="
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

echo -e "${YELLOW}Getting quick info for: $SITE_NAME.$ENVIRONMENT${NC}"
echo

# Get SSH connection details
echo "Getting SSH connection details..."
SSH_DETAILS=$(terminus connection:info $SITE_NAME.$ENVIRONMENT --format=list --field="SFTP Command" 2>/dev/null | grep "sftp -o Port" | head -1)
if [ -z "$SSH_DETAILS" ]; then
    echo -e "${RED}✗ ERROR: Could not get SSH connection details${NC}"
    exit 1
fi

SSH_HOST=$(echo "$SSH_DETAILS" | sed 's/.*Port=2222 //' | tr -d ' ')
echo -e "${GREEN}✓ SSH host: $SSH_HOST${NC}"

# Quick tests with very short timeouts
echo
echo -e "${YELLOW}Quick connectivity test...${NC}"
QUICK_TEST=$(timeout 5 ssh -o Port=2222 -o StrictHostKeyChecking=no -o ConnectTimeout=5 "$SSH_HOST" "pwd && echo 'Connection OK'" 2>/dev/null)
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ SSH connection working${NC}"
    echo "Working directory: $(echo "$QUICK_TEST" | head -1)"
else
    echo -e "${RED}✗ SSH connection failed or timed out${NC}"
    exit 1
fi

echo
echo -e "${YELLOW}Quick directory listing...${NC}"
QUICK_LS=$(timeout 5 ssh -o Port=2222 -o StrictHostKeyChecking=no "$SSH_HOST" "ls -la | head -10" 2>/dev/null)
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Directory contents:${NC}"
    echo "$QUICK_LS"
else
    echo -e "${YELLOW}⚠ Could not get directory listing${NC}"
fi

echo
echo -e "${YELLOW}Quick disk space check...${NC}"
DISK_INFO=$(timeout 5 ssh -o Port=2222 -o StrictHostKeyChecking=no "$SSH_HOST" "df -h . | tail -1" 2>/dev/null)
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Disk usage:${NC}"
    echo "$DISK_INFO"
else
    echo -e "${YELLOW}⚠ Could not get disk info${NC}"
fi

echo
echo -e "${YELLOW}Quick size estimate (top-level only)...${NC}"
QUICK_SIZE=$(timeout 10 ssh -o Port=2222 -o StrictHostKeyChecking=no "$SSH_HOST" "du -sh --max-depth=0 . 2>/dev/null" 2>/dev/null)
if [ $? -eq 0 ] && [ -n "$QUICK_SIZE" ]; then
    echo -e "${GREEN}✓ Quick size estimate: $QUICK_SIZE${NC}"
else
    echo -e "${YELLOW}⚠ Size calculation taking too long - site is very large${NC}"

    # Try even faster approach
    echo "Trying alternative approach..."
    ALT_SIZE=$(timeout 5 ssh -o Port=2222 -o StrictHostKeyChecking=no "$SSH_HOST" "ls -lah | tail -1 | awk '{print \$5}'" 2>/dev/null)
    if [ -n "$ALT_SIZE" ]; then
        echo -e "${GREEN}✓ Alternative estimate available${NC}"
    else
        echo -e "${YELLOW}⚠ Site too large for quick analysis${NC}"
    fi
fi

echo
echo -e "${YELLOW}Platform-specific quick check...${NC}"
FRAMEWORK=$(terminus site:info $SITE_NAME --field=framework 2>/dev/null)
echo "Platform: $FRAMEWORK"

case $FRAMEWORK in
    "wordpress")
        echo "Checking for WordPress directories..."
        WP_CHECK=$(timeout 5 ssh -o Port=2222 -o StrictHostKeyChecking=no "$SSH_HOST" "ls -la wp-content 2>/dev/null | head -3" 2>/dev/null)
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓ wp-content directory found${NC}"
            echo "$WP_CHECK"
        else
            echo -e "${YELLOW}⚠ wp-content check timed out${NC}"
        fi
        ;;
    "drupal"|"drupal8"|"drupal9"|"drupal10")
        echo "Checking for Drupal directories..."
        DRUPAL_CHECK=$(timeout 5 ssh -o Port=2222 -o StrictHostKeyChecking=no "$SSH_HOST" "ls -la sites/default/files 2>/dev/null | head -3" 2>/dev/null)
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓ sites/default/files directory found${NC}"
            echo "$DRUPAL_CHECK"
        else
            echo -e "${YELLOW}⚠ Drupal files check timed out${NC}"
        fi
        ;;
    *)
        echo "Generic platform - no specific checks"
        ;;
esac

echo
echo -e "${BLUE}=== QUICK ANALYSIS COMPLETE ===${NC}"
echo "Note: For full storage analysis, use the main storage script."
echo "The site appears to be quite large, which is why size calculations take time."