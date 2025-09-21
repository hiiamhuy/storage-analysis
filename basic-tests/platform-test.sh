#!/bin/bash

# Platform Detection Test Script
# Simple script to test platform detection without remote execution

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== PLATFORM DETECTION TEST ===${NC}"
echo "Generated: $(date)"
echo "==========================================="
echo

# Check if site name provided
if [ $# -eq 0 ]; then
    echo -e "${RED}ERROR: Site name required${NC}"
    echo "Usage: $0 <site-name>"
    echo "Example: $0 uwsurgery"
    exit 1
fi

SITE_NAME=$1

echo -e "${YELLOW}Testing platform detection for: $SITE_NAME${NC}"
echo

# Function to detect platform (same as main script)
detect_platform() {
    local site=$1
    local framework

    framework=$(terminus site:info $site --field=framework 2>/dev/null)

    case $framework in
        "wordpress")
            echo "wordpress"
            ;;
        "drupal"|"drupal8"|"drupal9"|"drupal10")
            echo "drupal"
            ;;
        *)
            echo "generic"
            ;;
    esac
}

# Test 1: Basic authentication check
echo -e "${YELLOW}[TEST 1] Checking authentication...${NC}"
if terminus auth:whoami &> /dev/null; then
    echo -e "${GREEN}✓ Authenticated${NC}"
else
    echo -e "${RED}✗ ERROR: Not authenticated${NC}"
    exit 1
fi
echo

# Test 2: Site accessibility
echo -e "${YELLOW}[TEST 2] Checking site accessibility...${NC}"
if terminus site:info $SITE_NAME --field=name &> /dev/null; then
    echo -e "${GREEN}✓ Site accessible${NC}"
else
    echo -e "${RED}✗ ERROR: Site not accessible${NC}"
    exit 1
fi
echo

# Test 3: Get detailed site information
echo -e "${YELLOW}[TEST 3] Getting site information...${NC}"
echo "Site Details:"
echo "============="

# Basic site info
SITE_INFO=$(terminus site:info $SITE_NAME --format=table 2>/dev/null)
echo "$SITE_INFO"
echo

# Test 4: Platform detection
echo -e "${YELLOW}[TEST 4] Detecting platform...${NC}"
FRAMEWORK=$(terminus site:info $SITE_NAME --field=framework 2>/dev/null)
PLATFORM=$(detect_platform $SITE_NAME)

echo "Raw framework field: '$FRAMEWORK'"
echo "Detected platform: '$PLATFORM'"
echo

# Test 5: Environment information
echo -e "${YELLOW}[TEST 5] Checking environments...${NC}"
echo "Environment Details:"
echo "==================="

for env in dev test live; do
    echo -e "${YELLOW}Environment: $env${NC}"
    if terminus env:info $SITE_NAME.$env --field=id &> /dev/null; then
        echo -e "  ${GREEN}✓ Accessible${NC}"

        # Get environment details
        ENV_INFO=$(terminus env:info $SITE_NAME.$env --format=table 2>/dev/null)
        echo "$ENV_INFO" | head -10
        echo
    else
        echo -e "  ${RED}✗ Not accessible${NC}"
        echo
    fi
done

# Test 6: Available tools check
echo -e "${YELLOW}[TEST 6] Checking available platform tools...${NC}"
case $PLATFORM in
    "wordpress")
        echo "WordPress site detected - should use WP-CLI"
        echo "Available WP-CLI commands:"
        terminus remote:wp $SITE_NAME.dev -- "cli info" 2>/dev/null | head -5 || echo "WP-CLI not accessible"
        ;;
    "drupal")
        echo "Drupal site detected - should use Drush"
        echo "Available Drush commands:"
        terminus remote:drush $SITE_NAME.dev -- "status" 2>/dev/null | head -5 || echo "Drush not accessible"
        ;;
    *)
        echo "Generic/Unknown platform - will use SSH only"
        ;;
esac

echo
echo -e "${BLUE}=== PLATFORM DETECTION COMPLETE ===${NC}"
echo "Summary:"
echo "  Site: $SITE_NAME"
echo "  Framework: $FRAMEWORK"
echo "  Platform: $PLATFORM"