#!/bin/bash

# Simple Storage Analysis Script
# Basic storage check using SSH instead of complex WP-CLI/Drush eval

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== SIMPLE STORAGE ANALYSIS ===${NC}"
echo "Generated: $(date)"
echo "======================================"
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

echo -e "${YELLOW}Analyzing: $SITE_NAME.$ENVIRONMENT${NC}"
echo

# Test 1: Basic authentication
echo -e "${YELLOW}[STEP 1] Checking authentication...${NC}"
if terminus auth:whoami &> /dev/null; then
    echo -e "${GREEN}✓ Authenticated${NC}"
else
    echo -e "${RED}✗ ERROR: Not authenticated${NC}"
    exit 1
fi

# Test 2: Environment accessibility
echo -e "${YELLOW}[STEP 2] Checking environment...${NC}"
if terminus env:info $SITE_NAME.$ENVIRONMENT --field=id &> /dev/null; then
    echo -e "${GREEN}✓ Environment accessible${NC}"
else
    echo -e "${RED}✗ ERROR: Cannot access $SITE_NAME.$ENVIRONMENT${NC}"
    exit 1
fi

# Test 3: Wake environment
echo -e "${YELLOW}[STEP 3] Waking environment...${NC}"
terminus env:wake $SITE_NAME.$ENVIRONMENT >/dev/null 2>&1
echo -e "${GREEN}✓ Environment awakened${NC}"

# Test 4: Basic SSH storage check
echo -e "${YELLOW}[STEP 4] Getting basic storage information via SSH...${NC}"
echo

echo "=== SSH-BASED STORAGE ANALYSIS ==="
echo "Site: $SITE_NAME.$ENVIRONMENT"
echo "Generated: $(date)"
echo "--------------------------------"

# Get SSH connection details
echo "Getting SSH connection details..."
SSH_DETAILS=$(terminus connection:info $SITE_NAME.$ENVIRONMENT --format=list --field="SFTP Command" 2>/dev/null | grep "sftp -o Port" | head -1)
if [ -z "$SSH_DETAILS" ]; then
    echo -e "${RED}✗ ERROR: Could not get SSH connection details${NC}"
    exit 1
fi

# Extract SSH connection info
SSH_HOST=$(echo "$SSH_DETAILS" | sed 's/.*Port=2222 //' | tr -d ' ')
echo "SSH host: $SSH_HOST"

# Basic total size using SSH with timeout
echo "Getting total site size (this may take a moment for large sites)..."
TOTAL_SIZE=$(timeout 30 ssh -o Port=2222 -o StrictHostKeyChecking=no "$SSH_HOST" "du -sh . 2>/dev/null | cut -f1" 2>/dev/null)
SIZE_EXIT_CODE=$?

if [ $SIZE_EXIT_CODE -eq 0 ] && [ -n "$TOTAL_SIZE" ]; then
    echo -e "${GREEN}✓ Total site size: $TOTAL_SIZE${NC}"
elif [ $SIZE_EXIT_CODE -eq 124 ]; then
    echo -e "${YELLOW}⚠ Size calculation timed out (site is very large)${NC}"
    echo "Trying quick estimate..."
    QUICK_SIZE=$(timeout 10 ssh -o Port=2222 -o StrictHostKeyChecking=no "$SSH_HOST" "du -sh --max-depth=1 . 2>/dev/null | tail -1 | cut -f1" 2>/dev/null)
    if [ -n "$QUICK_SIZE" ]; then
        echo -e "${GREEN}✓ Estimated size: $QUICK_SIZE${NC}"
    else
        echo -e "${YELLOW}⚠ Could not estimate size${NC}"
    fi
else
    echo -e "${RED}✗ ERROR: Could not get total size${NC}"
    echo "This might indicate a very large site or connectivity issue"
fi

# File count using SSH with timeout
echo "Getting file count..."
FILE_COUNT=$(timeout 20 ssh -o Port=2222 -o StrictHostKeyChecking=no "$SSH_HOST" "find . -type f 2>/dev/null | wc -l" 2>/dev/null)
if [ $? -eq 0 ] && [ -n "$FILE_COUNT" ]; then
    echo -e "${GREEN}✓ Total files: $FILE_COUNT${NC}"
else
    echo -e "${YELLOW}⚠ Could not get file count (timed out or error)${NC}"
fi

# Directory breakdown using SSH with timeout
echo
echo "Getting directory breakdown..."
DIR_OUTPUT=$(timeout 20 ssh -o Port=2222 -o StrictHostKeyChecking=no "$SSH_HOST" "du -sh */ 2>/dev/null | sort -rh | head -10" 2>/dev/null)
if [ $? -eq 0 ] && [ -n "$DIR_OUTPUT" ]; then
    echo -e "${GREEN}✓ Top directories by size:${NC}"
    echo "$DIR_OUTPUT"
else
    echo -e "${YELLOW}⚠ Could not get directory breakdown (timed out or error)${NC}"
    echo "Trying simpler approach..."
    SIMPLE_DIRS=$(timeout 10 ssh -o Port=2222 -o StrictHostKeyChecking=no "$SSH_HOST" "ls -la | head -10" 2>/dev/null)
    if [ -n "$SIMPLE_DIRS" ]; then
        echo "Directory listing:"
        echo "$SIMPLE_DIRS"
    fi
fi

# Working directory info
echo
echo "Getting basic environment info..."
WORKING_DIR=$(terminus env:ssh $SITE_NAME.$ENVIRONMENT -- "pwd" 2>/dev/null)
echo "Working directory: $WORKING_DIR"

DISK_USAGE=$(terminus env:ssh $SITE_NAME.$ENVIRONMENT -- "df -h . 2>/dev/null | tail -1" 2>/dev/null)
echo "Disk usage: $DISK_USAGE"

# Platform-specific content check
echo
echo -e "${YELLOW}[STEP 5] Checking for platform-specific content...${NC}"
FRAMEWORK=$(terminus site:info $SITE_NAME --field=framework 2>/dev/null)
echo "Platform: $FRAMEWORK"

case $FRAMEWORK in
    "wordpress")
        echo "Checking for WordPress content..."
        WP_CONTENT=$(terminus env:ssh $SITE_NAME.$ENVIRONMENT -- "du -sh wp-content 2>/dev/null | cut -f1" 2>/dev/null)
        if [ $? -eq 0 ] && [ -n "$WP_CONTENT" ]; then
            echo -e "${GREEN}✓ wp-content size: $WP_CONTENT${NC}"

            # Check wp-content subdirectories
            WP_DIRS=$(terminus env:ssh $SITE_NAME.$ENVIRONMENT -- "du -sh wp-content/*/ 2>/dev/null | sort -rh" 2>/dev/null)
            if [ -n "$WP_DIRS" ]; then
                echo "wp-content breakdown:"
                echo "$WP_DIRS"
            fi
        else
            echo -e "${YELLOW}⚠ No wp-content directory found${NC}"
        fi
        ;;
    "drupal"|"drupal8"|"drupal9"|"drupal10")
        echo "Checking for Drupal content..."
        DRUPAL_FILES=$(terminus env:ssh $SITE_NAME.$ENVIRONMENT -- "du -sh sites/default/files 2>/dev/null | cut -f1" 2>/dev/null)
        if [ $? -eq 0 ] && [ -n "$DRUPAL_FILES" ]; then
            echo -e "${GREEN}✓ sites/default/files size: $DRUPAL_FILES${NC}"
        else
            echo -e "${YELLOW}⚠ No sites/default/files directory found${NC}"
        fi
        ;;
    *)
        echo "Generic platform - no specific content checks"
        ;;
esac

echo
echo -e "${BLUE}=== SIMPLE STORAGE ANALYSIS COMPLETE ===${NC}"
echo "Summary:"
echo "  Site: $SITE_NAME.$ENVIRONMENT"
echo "  Platform: $FRAMEWORK"
echo "  Total Size: $TOTAL_SIZE"
echo "  Total Files: $FILE_COUNT"