

#!/bin/bash

# Error-Free Storage Analyzer for Pantheon
# Handles PHP warnings and broken pipe errors

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}PANTHEON STORAGE ANALYZER${NC}"
echo "======================================"
echo

# Check terminus
if ! command -v terminus &> /dev/null; then
    echo -e "${RED}ERROR: Terminus CLI not installed${NC}"
    exit 1
fi

if ! terminus auth:whoami &> /dev/null; then
    echo -e "${RED}ERROR: Terminus not authenticated${NC}"
    exit 1
fi

# Function to detect platform
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

# Universal function to get basic size and file count for environment comparison
get_basic_info() {
    local site=$1
    local env=$2
    local platform=$3

    case $platform in
        "wordpress")
            # WordPress method
            local size=$(terminus remote:wp $site.$env -- eval "
            error_reporting(0);
            exec('du -sk . 2>/dev/null', \$t);
            \$kb = !empty(\$t) ? (int)explode('\t', \$t[0])[0] : 0;
            if(\$kb >= 1048576) echo round(\$kb/1048576, 2) . ' GB';
            else if(\$kb >= 1024) echo round(\$kb/1024, 2) . ' MB';
            else echo \$kb . ' KB';
            " 2>/dev/null | grep -v "Warning:" | tail -1)

            local files=$(terminus remote:wp $site.$env -- eval "
            error_reporting(0);
            exec('find . -type f 2>/dev/null | wc -l', \$f);
            echo number_format(trim(implode('', \$f)));
            " 2>/dev/null | grep -v "Warning:" | tail -1)
            ;;

        "drupal")
            # Drupal method
            local size=$(terminus remote:drush $site.$env -- eval "
            error_reporting(0);
            exec('du -sk . 2>/dev/null', \$t);
            \$kb = !empty(\$t) ? (int)explode('\t', \$t[0])[0] : 0;
            if(\$kb >= 1048576) echo round(\$kb/1048576, 2) . ' GB';
            else if(\$kb >= 1024) echo round(\$kb/1024, 2) . ' MB';
            else echo \$kb . ' KB';
            " 2>/dev/null | grep -v "Warning:" | tail -1)

            local files=$(terminus remote:drush $site.$env -- eval "
            error_reporting(0);
            exec('find . -type f 2>/dev/null | wc -l', \$f);
            echo number_format(trim(implode('', \$f)));
            " 2>/dev/null | grep -v "Warning:" | tail -1)
            ;;

        *)
            # Generic SSH method
            local size=$(terminus env:ssh $site.$env -- "du -sh . 2>/dev/null | cut -f1" 2>/dev/null | grep -v "Warning:" | head -1)
            local files=$(terminus env:ssh $site.$env -- "find . -type f 2>/dev/null | wc -l" 2>/dev/null | grep -v "Warning:" | tail -1)
            ;;
    esac

    echo "$size|$files"
}

# WordPress-specific storage analysis
get_wordpress_storage() {
    local site=$1
    local env=$2

    echo -e "${GREEN}=== $site.$env STORAGE ANALYSIS ===${NC}"
    echo "Generated: $(date)"
    echo "------------------------------------------------"

    # Wake environment
    echo "Waking environment..."
    terminus env:wake $site.$env >/dev/null 2>&1

    # Get storage with error suppression
    echo "Calculating storage (suppressing PHP warnings)..."

    terminus remote:wp $site.$env -- eval "
    // Suppress all PHP warnings and notices
    error_reporting(E_ERROR | E_PARSE);
    ini_set('display_errors', 0);

    echo \"\\n=== SITE: $site | ENV: $env ===\\n\";

    // Method 1: Total site calculation
    echo \"[SIZE] TOTAL SITE SIZE\\n\";
    echo str_repeat('-', 30) . \"\\n\";

    \$output = array();
    \$return_var = 0;
    exec('du -sk . 2>/dev/null', \$output, \$return_var);

    if(\$return_var === 0 && !empty(\$output)) {
        \$total_kb = (int)explode(\"\\t\", \$output[0])[0];

        if(\$total_kb >= 1048576) {
            \$size_display = round(\$total_kb/1048576, 2) . ' GB';
        } elseif(\$total_kb >= 1024) {
            \$size_display = round(\$total_kb/1024, 2) . ' MB';
        } else {
            \$size_display = \$total_kb . ' KB';
        }

        echo \"TOTAL: \" . \$size_display . \" (\" . number_format(\$total_kb) . \" KB)\\n\\n\";

        // Output for bash capture - special markers for data extraction
        echo \"[SUMMARY_DATA_START]\\n\";
        echo \"TOTAL_SIZE=\" . \$size_display . \"\\n\";
        echo \"[SUMMARY_DATA_END]\\n\";
    } else {
        echo \"Error calculating total size\\n\\n\";
        // Output for bash capture - error case
        echo \"[SUMMARY_DATA_START]\\n\";
        echo \"TOTAL_SIZE=Unknown\\n\";
        echo \"[SUMMARY_DATA_END]\\n\";
    }

    // Root directories (no sorting to avoid broken pipe)
    echo \"[DIRS] ROOT DIRECTORIES\\n\";
    echo str_repeat('-', 30) . \"\\n\";

    \$dirs = array();
    exec('du -sk */ 2>/dev/null', \$dirs);

    // Parse and sort in PHP to avoid broken pipe
    \$dir_sizes = array();
    foreach(\$dirs as \$line) {
        if(preg_match('/^(\d+)\s+(.+)$/', \$line, \$matches)) {
            \$size_kb = (int)\$matches[1];
            \$path = rtrim(\$matches[2], '/');
            \$dir_sizes[\$path] = \$size_kb;
        }
    }

    // Sort by size (largest first)
    arsort(\$dir_sizes);

    foreach(\$dir_sizes as \$path => \$size_kb) {
        if(\$size_kb >= 1048576) {
            \$size_display = round(\$size_kb/1048576, 2) . ' GB';
        } elseif(\$size_kb >= 1024) {
            \$size_display = round(\$size_kb/1024, 2) . ' MB';
        } else {
            \$size_display = \$size_kb . ' KB';
        }
        printf(\"%-12s %s\\n\", \$size_display, \$path);
    }
    echo \"\\n\";

    // wp-content breakdown (no external sorting)
    echo \"[CONTENT] wp-content BREAKDOWN\\n\";
    echo str_repeat('-', 30) . \"\\n\";

    if(is_dir('wp-content')) {
        \$content_items = array();
        exec('du -sk wp-content/* 2>/dev/null', \$content_items);

        \$content_sizes = array();
        foreach(\$content_items as \$line) {
            if(preg_match('/^(\d+)\s+(.+)$/', \$line, \$matches)) {
                \$size_kb = (int)\$matches[1];
                \$path = \$matches[2];
                \$name = basename(\$path);
                \$content_sizes[\$name] = \$size_kb;
            }
        }

        arsort(\$content_sizes);

        foreach(\$content_sizes as \$name => \$size_kb) {
            if(\$size_kb >= 1048576) {
                \$size_display = round(\$size_kb/1048576, 2) . ' GB';
            } elseif(\$size_kb >= 1024) {
                \$size_display = round(\$size_kb/1024, 2) . ' MB';
            } else {
                \$size_display = \$size_kb . ' KB';
            }
            printf(\"%-12s %s\\n\", \$size_display, \$name);
        }
    } else {
        echo \"wp-content directory not found\\n\";
    }
    echo \"\\n\";

    // File counts (safe counting)
    echo \"[STATS] FILE STATISTICS\\n\";
    echo str_repeat('-', 30) . \"\\n\";

    \$file_count = 0;
    \$dir_count = 0;
    \$upload_count = 0;
    \$plugin_count = 0;

    // Count files safely
    \$find_output = array();
    exec('find . -type f 2>/dev/null | wc -l', \$find_output);
    \$file_count = !empty(\$find_output) ? (int)trim(\$find_output[0]) : 0;

    \$find_dirs = array();
    exec('find . -type d 2>/dev/null | wc -l', \$find_dirs);
    \$dir_count = !empty(\$find_dirs) ? (int)trim(\$find_dirs[0]) : 0;

    if(is_dir('wp-content/uploads')) {
        \$upload_files = array();
        exec('find wp-content/uploads -type f 2>/dev/null | wc -l', \$upload_files);
        \$upload_count = !empty(\$upload_files) ? (int)trim(\$upload_files[0]) : 0;
    }

    if(is_dir('wp-content/plugins')) {
        \$plugin_files = array();
        exec('find wp-content/plugins -type f 2>/dev/null | wc -l', \$plugin_files);
        \$plugin_count = !empty(\$plugin_files) ? (int)trim(\$plugin_files[0]) : 0;
    }

    echo \"Total files: \" . number_format(\$file_count) . \"\\n\";
    echo \"Total directories: \" . number_format(\$dir_count) . \"\\n\";
    echo \"Upload files: \" . number_format(\$upload_count) . \"\\n\";
    echo \"Plugin files: \" . number_format(\$plugin_count) . \"\\n\\n\";

    // Output for bash capture - file statistics
    echo \"[FILE_STATS_START]\\n\";
    echo \"TOTAL_FILES=\" . number_format(\$file_count) . \"\\n\";
    echo \"TOTAL_DIRS=\" . number_format(\$dir_count) . \"\\n\";
    echo \"[FILE_STATS_END]\\n\";

    // Top plugins (safe method)
    echo \"[PLUGINS] LARGEST PLUGINS\\n\";
    echo str_repeat('-', 30) . \"\\n\";

    if(is_dir('wp-content/plugins')) {
        \$plugin_dirs = array();
        exec('du -sk wp-content/plugins/*/ 2>/dev/null', \$plugin_dirs);

        \$plugin_sizes = array();
        foreach(\$plugin_dirs as \$line) {
            if(preg_match('/^(\d+)\s+(.+)$/', \$line, \$matches)) {
                \$size_kb = (int)\$matches[1];
                \$path = rtrim(\$matches[2], '/');
                \$plugin_name = basename(\$path);
                \$plugin_sizes[\$plugin_name] = \$size_kb;
            }
        }

        arsort(\$plugin_sizes);

        \$count = 0;
        foreach(\$plugin_sizes as \$name => \$size_kb) {
            if(\$count >= 10) break;

            if(\$size_kb >= 1024) {
                \$size_display = round(\$size_kb/1024, 2) . ' MB';
            } else {
                \$size_display = \$size_kb . ' KB';
            }
            printf(\"%-12s %s\\n\", \$size_display, \$name);
            \$count++;
        }
    }
    echo \"\\n\";

    // Upload breakdown (safe method)
    echo \"[UPLOADS] UPLOADS BREAKDOWN\\n\";
    echo str_repeat('-', 30) . \"\\n\";

    if(is_dir('wp-content/uploads')) {
        \$upload_dirs = array();
        exec('du -sk wp-content/uploads/*/ 2>/dev/null', \$upload_dirs);

        \$upload_sizes = array();
        foreach(\$upload_dirs as \$line) {
            if(preg_match('/^(\d+)\s+(.+)$/', \$line, \$matches)) {
                \$size_kb = (int)\$matches[1];
                \$path = rtrim(\$matches[2], '/');
                \$dir_name = basename(\$path);
                \$upload_sizes[\$dir_name] = \$size_kb;
            }
        }

        arsort(\$upload_sizes);

        \$count = 0;
        foreach(\$upload_sizes as \$name => \$size_kb) {
            if(\$count >= 10) break;

            if(\$size_kb >= 1048576) {
                \$size_display = round(\$size_kb/1048576, 2) . ' GB';
            } elseif(\$size_kb >= 1024) {
                \$size_display = round(\$size_kb/1024, 2) . ' MB';
            } else {
                \$size_display = \$size_kb . ' KB';
            }
            printf(\"%-12s %s\\n\", \$size_display, \$name);
            \$count++;
        }
    } else {
        echo \"No uploads directory found\\n\";
    }
    echo \"\\n\";
    " 2>/dev/null

    # Database size (separate to avoid PHP warnings)
    echo "[DATABASE] DATABASE SIZE"
    echo "------------------------------"

    # Get database size and format it nicely
    local db_info=$(terminus remote:wp $site.$env -- db size 2>/dev/null | grep -v "Warning:" | grep -v "Notice:")

    if [ -n "$db_info" ]; then
        # Extract size from the table output and convert to human readable
        local db_bytes=$(echo "$db_info" | grep -o '[0-9]*' | tail -1)
        if [ -n "$db_bytes" ] && [ "$db_bytes" -gt 0 ]; then
            # Convert bytes to human readable format
            if [ "$db_bytes" -ge 1073741824 ]; then
                local db_size=$(echo "scale=2; $db_bytes / 1073741824" | bc 2>/dev/null || echo "scale=2; $db_bytes / 1073741824" | awk '{print $1/1073741824}')
                echo "Database Size: ${db_size} GB"
            elif [ "$db_bytes" -ge 1048576 ]; then
                local db_size=$(echo "scale=2; $db_bytes / 1048576" | bc 2>/dev/null || echo "scale=2; $db_bytes / 1048576" | awk '{print $1/1048576}')
                echo "Database Size: ${db_size} MB"
            elif [ "$db_bytes" -ge 1024 ]; then
                local db_size=$(echo "scale=2; $db_bytes / 1024" | bc 2>/dev/null || echo "scale=2; $db_bytes / 1024" | awk '{print $1/1024}')
                echo "Database Size: ${db_size} KB"
            else
                echo "Database Size: ${db_bytes} bytes"
            fi
        else
            echo "Database Size: Unable to determine"
        fi
    else
        echo "Database Size: Unable to determine"
    fi

    echo "------------------------------------------------"
    echo

    # Capture summary data from the WordPress analysis output
    local wp_output=$(terminus remote:wp $site.$env -- eval "
    // Minimal script to extract summary data we already calculated
    echo \"[EXTRACT_SUMMARY_START]\\n\";

    // Re-calculate just the essential summary data
    \$output = array();
    exec('du -sk . 2>/dev/null', \$output);
    if(!empty(\$output)) {
        \$total_kb = (int)explode(\"\\t\", \$output[0])[0];
        if(\$total_kb >= 1048576) {
            echo \"TOTAL_SIZE=\" . round(\$total_kb/1048576, 2) . ' GB' . \"\\n\";
        } elseif(\$total_kb >= 1024) {
            echo \"TOTAL_SIZE=\" . round(\$total_kb/1024, 2) . ' MB' . \"\\n\";
        } else {
            echo \"TOTAL_SIZE=\" . \$total_kb . ' KB' . \"\\n\";
        }
    } else {
        echo \"TOTAL_SIZE=Unknown\\n\";
    }

    \$file_output = array();
    exec('find . -type f 2>/dev/null | wc -l', \$file_output);
    \$file_count = !empty(\$file_output) ? (int)trim(\$file_output[0]) : 0;
    echo \"TOTAL_FILES=\" . number_format(\$file_count) . \"\\n\";

    \$dir_output = array();
    exec('find . -type d 2>/dev/null | wc -l', \$dir_output);
    \$dir_count = !empty(\$dir_output) ? (int)trim(\$dir_output[0]) : 0;
    echo \"TOTAL_DIRS=\" . number_format(\$dir_count) . \"\\n\";

    echo \"[EXTRACT_SUMMARY_END]\\n\";
    " 2>/dev/null | grep -v "Warning:")

    # Parse the structured output to extract values
    local captured_size=$(echo "$wp_output" | sed -n '/\[EXTRACT_SUMMARY_START\]/,/\[EXTRACT_SUMMARY_END\]/p' | grep "TOTAL_SIZE=" | cut -d'=' -f2)
    local captured_files=$(echo "$wp_output" | sed -n '/\[EXTRACT_SUMMARY_START\]/,/\[EXTRACT_SUMMARY_END\]/p' | grep "TOTAL_FILES=" | cut -d'=' -f2)
    local captured_dirs=$(echo "$wp_output" | sed -n '/\[EXTRACT_SUMMARY_START\]/,/\[EXTRACT_SUMMARY_END\]/p' | grep "TOTAL_DIRS=" | cut -d'=' -f2)

    # Store in global analysis data if not already set (for multi-env, use first successful capture)
    if [ -z "${ANALYSIS_DATA[total_size]}" ] && [ -n "$captured_size" ] && [ "$captured_size" != "Unknown" ]; then
        ANALYSIS_DATA[total_size]="$captured_size"
    fi
    if [ -z "${ANALYSIS_DATA[total_files]}" ] && [ -n "$captured_files" ] && [ "$captured_files" != "0" ]; then
        ANALYSIS_DATA[total_files]="$captured_files"
    fi
    if [ -z "${ANALYSIS_DATA[total_dirs]}" ] && [ -n "$captured_dirs" ] && [ "$captured_dirs" != "0" ]; then
        ANALYSIS_DATA[total_dirs]="$captured_dirs"
    fi
}

# Drupal-specific storage analysis
get_drupal_storage() {
    local site=$1
    local env=$2

    echo -e "${GREEN}=== $site.$env STORAGE ANALYSIS (Drupal) ===${NC}"
    echo "Generated: $(date)"
    echo "------------------------------------------------"

    # Wake environment
    echo "Waking environment..."
    terminus env:wake $site.$env >/dev/null 2>&1

    # Get storage with simplified approach using SSH for Drupal
    echo "Calculating storage (using SSH connection)..."

    echo
    echo "=== SITE: $site | ENV: $env ==="
    echo
    # Use simplified drush eval commands instead of complex SSH
    echo "[SIZE] TOTAL SITE SIZE"
    echo "------------------------------"
    local total_size=$(terminus remote:drush $site.$env -- eval "\$output = shell_exec('du -sh . 2>/dev/null'); echo trim(explode('\t', \$output)[0]);" 2>/dev/null | grep -v "warning\|notice\|Command:" | tail -1)
    echo "TOTAL: ${total_size:-Unknown}"

    echo
    echo "[DIRS] ROOT DIRECTORIES"
    echo "------------------------------"
    terminus remote:drush $site.$env -- eval "exec('du -sh */ 2>/dev/null | sort -hr | head -10', \$output); foreach(\$output as \$line) echo \$line;" 2>/dev/null | grep -v "warning\|notice\|Command:"

    echo
    echo "[STATS] FILE STATISTICS"
    echo "------------------------------"
    local total_files=$(terminus remote:drush $site.$env -- eval "echo trim(shell_exec('find . -type f 2>/dev/null | wc -l'));" 2>/dev/null | grep -v "warning\|notice\|Command:" | tail -1)
    local total_dirs=$(terminus remote:drush $site.$env -- eval "echo trim(shell_exec('find . -type d 2>/dev/null | wc -l'));" 2>/dev/null | grep -v "warning\|notice\|Command:" | tail -1)
    local drupal_files=$(terminus remote:drush $site.$env -- eval "echo is_dir('sites/default/files') ? trim(shell_exec('find sites/default/files -type f 2>/dev/null | wc -l')) : '0';" 2>/dev/null | grep -v "warning\|notice\|Command:" | tail -1)

    echo "Total files: ${total_files:-Unknown}"
    echo "Total directories: ${total_dirs:-Unknown}"
    echo "Drupal files: ${drupal_files:-0}"

    echo
    echo "[CONTENT] DRUPAL FILES BREAKDOWN"
    echo "------------------------------"
    terminus remote:drush $site.$env -- eval "if(is_dir('sites/default/files')) { exec('du -sh sites/default/files/* 2>/dev/null | sort -hr | head -5', \$output); foreach(\$output as \$line) echo \$line; } else { echo 'No files directory found'; }" 2>/dev/null | grep -v "warning\|notice\|Command:"

    echo
    echo "[MODULES] LARGEST MODULES"
    echo "------------------------------"
    terminus remote:drush $site.$env -- eval "if(is_dir('modules')) { exec('du -sh modules/*/ 2>/dev/null | sort -hr | head -5', \$output); foreach(\$output as \$line) echo \$line; } else { echo 'No modules directory found'; }" 2>/dev/null | grep -v "warning\|notice\|Command:"

    echo

    # Database size (separate to avoid PHP warnings)
    echo "[DATABASE] DATABASE SIZE"
    echo "------------------------------"

    # Get total database size in MB
    local db_total_mb=$(terminus remote:drush $site.$env -- sql:query "SELECT ROUND(SUM((data_length + index_length) / 1024 / 1024), 2) AS total_mb FROM information_schema.tables WHERE table_schema=DATABASE();" 2>/dev/null | grep -v "Warning:" | grep -v "Notice:" | grep -v "total_mb" | grep -E "^[0-9]+(\.[0-9]+)?$" | head -1)

    if [ -n "$db_total_mb" ] && [ "$db_total_mb" != "0.00" ]; then
        # Convert to appropriate units
        local db_total_mb_int=$(echo "$db_total_mb" | cut -d'.' -f1)
        if [ "$db_total_mb_int" -ge 1024 ]; then
            local db_size_gb=$(echo "scale=2; $db_total_mb / 1024" | awk '{print $1/1024}')
            echo "Database Size: ${db_size_gb} GB"
        else
            echo "Database Size: ${db_total_mb} MB"
        fi

        # Show breakdown of largest tables
        echo ""
        echo "Largest Tables:"
        terminus remote:drush $site.$env -- sql:query "SELECT table_name, ROUND(((data_length + index_length) / 1024 / 1024), 2) AS 'size_mb' FROM information_schema.tables WHERE table_schema = DATABASE() AND ((data_length + index_length) / 1024 / 1024) > 0 ORDER BY (data_length + index_length) DESC LIMIT 5;" 2>/dev/null | grep -v "Warning:" | grep -v "Notice:" | grep -v "table_name" | grep -E "^[a-zA-Z]" | while read -r line; do
            echo "  $line"
        done 2>/dev/null || echo "  Unable to show table breakdown"
    else
        echo "Database Size: Unable to determine"
    fi

    echo "------------------------------------------------"
    echo

    # Store in global analysis data if not already set (for multi-env, use first successful capture)
    # Clean up values by removing any extra whitespace or unwanted characters
    total_size=$(echo "$total_size" | xargs)
    total_files=$(echo "$total_files" | xargs)
    total_dirs=$(echo "$total_dirs" | xargs)

    if [ -z "${ANALYSIS_DATA[total_size]}" ] && [ -n "$total_size" ] && [ "$total_size" != "Unknown" ] && [ "$total_size" != "" ]; then
        ANALYSIS_DATA[total_size]="$total_size"
    fi
    if [ -z "${ANALYSIS_DATA[total_files]}" ] && [ -n "$total_files" ] && [ "$total_files" != "Unknown" ] && [ "$total_files" != "" ]; then
        ANALYSIS_DATA[total_files]="$total_files"
    fi
    if [ -z "${ANALYSIS_DATA[total_dirs]}" ] && [ -n "$total_dirs" ] && [ "$total_dirs" != "Unknown" ] && [ "$total_dirs" != "" ]; then
        ANALYSIS_DATA[total_dirs]="$total_dirs"
    fi
}

# Generic storage analysis for non-WordPress/non-Drupal sites
get_generic_storage() {
    local site=$1
    local env=$2

    echo -e "${GREEN}=== $site.$env STORAGE ANALYSIS (Generic) ===${NC}"
    echo "Generated: $(date)"
    echo "------------------------------------------------"

    # Wake environment
    echo "Waking environment..."
    terminus env:wake $site.$env >/dev/null 2>&1

    # Get SSH connection info
    echo "Connecting via SSH for generic analysis..."

    # Use SSH connection to run basic storage commands
    local connection=$(terminus connection:info $site.$env --format=json 2>/dev/null)

    if [ $? -eq 0 ]; then
        echo "[SIZE] TOTAL SITE SIZE"
        echo "------------------------------"

        # Total site size
        local total_size=$(terminus env:ssh $site.$env -- "du -sh . 2>/dev/null | cut -f1" 2>/dev/null | grep -v "Warning:" | head -1)
        echo "TOTAL: ${total_size:-Unknown}"

        echo
        echo "[DIRS] ROOT DIRECTORIES"
        echo "------------------------------"

        # Directory breakdown
        terminus env:ssh $site.$env -- "du -sh */ 2>/dev/null | sort -hr | head -10" 2>/dev/null | grep -v "Warning:"

        echo
        echo "[STATS] FILE STATISTICS"
        echo "------------------------------"

        # File counts
        local total_files=$(terminus env:ssh $site.$env -- "find . -type f 2>/dev/null | wc -l" 2>/dev/null | grep -v "Warning:" | tail -1)
        local total_dirs=$(terminus env:ssh $site.$env -- "find . -type d 2>/dev/null | wc -l" 2>/dev/null | grep -v "Warning:" | tail -1)

        echo "Total files: $total_files"
        echo "Total directories: $total_dirs"

        echo
        echo "[DIRS] LARGEST DIRECTORIES"
        echo "------------------------------"

        # Find largest directories recursively
        terminus env:ssh $site.$env -- "find . -type d -exec du -sh {} + 2>/dev/null | sort -hr | head -10" 2>/dev/null | grep -v "Warning:"

        echo
        echo "[FILES] LARGEST FILES"
        echo "------------------------------"

        # Find largest individual files
        terminus env:ssh $site.$env -- "find . -type f -exec ls -lh {} + 2>/dev/null | sort -k5 -hr | head -10 | awk '{print \$5 \" \" \$9}'" 2>/dev/null | grep -v "Warning:"

    else
        echo "[ERROR] Unable to establish SSH connection for detailed analysis"
        echo "Basic connection test using terminus env:info..."

        # Fallback to basic terminus commands
        if terminus env:info $site.$env --field=connection_mode >/dev/null 2>&1; then
            echo "[OK] Environment is accessible"
            echo "[WARNING] SSH analysis unavailable - showing basic info only"
        else
            echo "[ERROR] Environment is not accessible"
        fi
    fi

    echo
    echo "💾 DATABASE SIZE"
    echo "------------------------------"
    echo "Database size analysis not available for generic platforms"

    echo "------------------------------------------------"
    echo "Note: Generic analysis provides basic file system information."
    echo "For full features, use WordPress or Drupal sites."
    echo

    # Store in global analysis data if not already set (for multi-env, use first successful capture)
    # Clean up values by removing any extra whitespace or unwanted characters
    total_size=$(echo "$total_size" | xargs)
    total_files=$(echo "$total_files" | xargs)
    total_dirs=$(echo "$total_dirs" | xargs)

    if [ -z "${ANALYSIS_DATA[total_size]}" ] && [ -n "$total_size" ] && [ "$total_size" != "Unknown" ] && [ "$total_size" != "" ]; then
        ANALYSIS_DATA[total_size]="$total_size"
    fi
    if [ -z "${ANALYSIS_DATA[total_files]}" ] && [ -n "$total_files" ] && [ "$total_files" != "Unknown" ] && [ "$total_files" != "" ]; then
        ANALYSIS_DATA[total_files]="$total_files"
    fi
    if [ -z "${ANALYSIS_DATA[total_dirs]}" ] && [ -n "$total_dirs" ] && [ "$total_dirs" != "Unknown" ] && [ "$total_dirs" != "" ]; then
        ANALYSIS_DATA[total_dirs]="$total_dirs"
    fi
}

# Export functionality variables
EXPORT_FORMAT=""
EXPORT_ENABLED=false
EXPORT_DATA=""

# Global variables for export data capture
declare -A ANALYSIS_DATA
ANALYSIS_DATA[site_name]=""
ANALYSIS_DATA[platform]=""
ANALYSIS_DATA[environments]=""
ANALYSIS_DATA[timestamp]=""
ANALYSIS_DATA[total_size]=""
ANALYSIS_DATA[total_files]=""
ANALYSIS_DATA[total_dirs]=""
declare -a ENV_COMPARISON_DATA
declare -A DETAILED_ANALYSIS

# Export functions
export_to_json() {
    local filename="storage-analysis-${ANALYSIS_DATA[site_name]}-$(echo "${ANALYSIS_DATA[environments]}" | tr ' ' '-')-$(date +%Y%m%d-%H%M%S).json"

    cat > "$filename" << EOF
{
  "analysis_metadata": {
    "site_name": "${ANALYSIS_DATA[site_name]}",
    "platform": "${ANALYSIS_DATA[platform]}",
    "environments": "${ANALYSIS_DATA[environments]}",
    "timestamp": "${ANALYSIS_DATA[timestamp]}"
  },
  "summary": {
    "total_size": "${ANALYSIS_DATA[total_size]:-"Unknown"}",
    "total_files": "${ANALYSIS_DATA[total_files]:-"Unknown"}",
    "total_directories": "${ANALYSIS_DATA[total_dirs]:-"Unknown"}"
  },
  "environment_comparison": [
$(for env_data in "${ENV_COMPARISON_DATA[@]}"; do
    IFS='|' read -r env size files <<< "$env_data"
    echo "    {\"environment\": \"$env\", \"size\": \"$size\", \"files\": \"$files\"}"
    [ "$env_data" != "${ENV_COMPARISON_DATA[-1]}" ] && echo ","
done)
  ],
  "detailed_analysis": {
$(for key in "${!DETAILED_ANALYSIS[@]}"; do
    echo "    \"$key\": \"${DETAILED_ANALYSIS[$key]}\""
    [ "$key" != "$(echo "${!DETAILED_ANALYSIS[@]}" | tr ' ' '\n' | tail -1)" ] && echo ","
done)
  }
}
EOF

    echo -e "${GREEN}[OK] Analysis exported to JSON: $filename${NC}"
}

export_to_csv() {
    local filename="storage-analysis-${ANALYSIS_DATA[site_name]}-$(echo "${ANALYSIS_DATA[environments]}" | tr ' ' '-')-$(date +%Y%m%d-%H%M%S).csv"

    cat > "$filename" << EOF
Site Name,Platform,Environments,Timestamp,Total Size,Total Files,Total Directories
"${ANALYSIS_DATA[site_name]}","${ANALYSIS_DATA[platform]}","${ANALYSIS_DATA[environments]}","${ANALYSIS_DATA[timestamp]}","${ANALYSIS_DATA[total_size]:-"Unknown"}","${ANALYSIS_DATA[total_files]:-"Unknown"}","${ANALYSIS_DATA[total_dirs]:-"Unknown"}"

Environment Comparison
Environment,Size,Files
$(for env_data in "${ENV_COMPARISON_DATA[@]}"; do
    IFS='|' read -r env size files <<< "$env_data"
    echo "\"$env\",\"$size\",\"$files\""
done)
EOF

    echo -e "${GREEN}[OK] Analysis exported to CSV: $filename${NC}"
}

export_to_txt() {
    local filename="storage-analysis-${ANALYSIS_DATA[site_name]}-$(echo "${ANALYSIS_DATA[environments]}" | tr ' ' '-')-$(date +%Y%m%d-%H%M%S).txt"

    cat > "$filename" << EOF
PANTHEON STORAGE ANALYSIS REPORT
===============================================

Site Information:
- Site Name: ${ANALYSIS_DATA[site_name]}
- Platform: ${ANALYSIS_DATA[platform]}
- Environments Analyzed: ${ANALYSIS_DATA[environments]}
- Analysis Date: ${ANALYSIS_DATA[timestamp]}

Summary:
- Total Size: ${ANALYSIS_DATA[total_size]:-"Unknown"}
- Total Files: ${ANALYSIS_DATA[total_files]:-"Unknown"}
- Total Directories: ${ANALYSIS_DATA[total_dirs]:-"Unknown"}

Environment Comparison:
$(printf "%-12s %-15s %-12s\n" "Environment" "Total Size" "Files")
$(printf "%-12s %-15s %-12s\n" "----------" "----------" "-----")
$(for env_data in "${ENV_COMPARISON_DATA[@]}"; do
    IFS='|' read -r env size files <<< "$env_data"
    printf "%-12s %-15s %-12s\n" "$env" "$size" "$files"
done)
EOF

    echo -e "${GREEN}[OK] Analysis exported to TXT: $filename${NC}"
}

export_to_html() {
    local filename="storage-analysis-${ANALYSIS_DATA[site_name]}-$(echo "${ANALYSIS_DATA[environments]}" | tr ' ' '-')-$(date +%Y%m%d-%H%M%S).html"

    cat > "$filename" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Pantheon Storage Analysis Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background: #f5f5f5; }
        .container { max-width: 1000px; margin: 0 auto; background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        h1 { color: #2c5aa0; border-bottom: 3px solid #2c5aa0; padding-bottom: 10px; }
        h2 { color: #34495e; margin-top: 30px; }
        .info-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); gap: 15px; margin: 20px 0; }
        .info-box { background: #ecf0f1; padding: 15px; border-radius: 5px; border-left: 4px solid #3498db; }
        .info-box strong { color: #2c3e50; }
        table { width: 100%; border-collapse: collapse; margin: 20px 0; }
        th, td { padding: 12px; text-align: left; border-bottom: 1px solid #ddd; }
        th { background-color: #3498db; color: white; }
        tr:nth-child(even) { background-color: #f2f2f2; }
        .footer { margin-top: 30px; padding-top: 20px; border-top: 1px solid #ddd; color: #7f8c8d; font-size: 14px; }
    </style>
</head>
<body>
    <div class="container">
        <h1>[STORAGE] Pantheon Storage Analysis Report</h1>

        <div class="info-grid">
            <div class="info-box">
                <strong>Site Name:</strong><br>
EOF

    cat >> "$filename" << EOF
                ${ANALYSIS_DATA[site_name]}
            </div>
            <div class="info-box">
                <strong>Platform:</strong><br>
                ${ANALYSIS_DATA[platform]}
            </div>
            <div class="info-box">
                <strong>Environments:</strong><br>
                ${ANALYSIS_DATA[environments]}
            </div>
            <div class="info-box">
                <strong>Analysis Date:</strong><br>
                ${ANALYSIS_DATA[timestamp]}
            </div>
        </div>

        <h2>[STATS] Summary Statistics</h2>
        <div class="info-grid">
            <div class="info-box">
                <strong>Total Size:</strong><br>
                ${ANALYSIS_DATA[total_size]:-"Unknown"}
            </div>
            <div class="info-box">
                <strong>Total Files:</strong><br>
                ${ANALYSIS_DATA[total_files]:-"Unknown"}
            </div>
            <div class="info-box">
                <strong>Total Directories:</strong><br>
                ${ANALYSIS_DATA[total_dirs]:-"Unknown"}
            </div>
        </div>

        <h2>[COMPARE] Environment Comparison</h2>
        <table>
            <thead>
                <tr>
                    <th>Environment</th>
                    <th>Total Size</th>
                    <th>Files</th>
                </tr>
            </thead>
            <tbody>
$(for env_data in "${ENV_COMPARISON_DATA[@]}"; do
    IFS='|' read -r env size files <<< "$env_data"
    echo "                <tr><td>$env</td><td>$size</td><td>$files</td></tr>"
done)
            </tbody>
        </table>

        <div class="footer">
        </div>
    </div>
</body>
</html>
EOF

    echo -e "${GREEN}[OK] Analysis exported to HTML: $filename${NC}"
}

export_to_markdown() {
    local filename="storage-analysis-${ANALYSIS_DATA[site_name]}-$(echo "${ANALYSIS_DATA[environments]}" | tr ' ' '-')-$(date +%Y%m%d-%H%M%S).md"

    cat > "$filename" << EOF
# [STORAGE] Pantheon Storage Analysis Report

## Site Information

| Field | Value |
|-------|-------|
| **Site Name** | ${ANALYSIS_DATA[site_name]} |
| **Platform** | ${ANALYSIS_DATA[platform]} |
| **Environments Analyzed** | ${ANALYSIS_DATA[environments]} |
| **Analysis Date** | ${ANALYSIS_DATA[timestamp]} |

## [STATS] Summary Statistics

| Metric | Value |
|--------|-------|
| **Total Size** | ${ANALYSIS_DATA[total_size]:-"Unknown"} |
| **Total Files** | ${ANALYSIS_DATA[total_files]:-"Unknown"} |
| **Total Directories** | ${ANALYSIS_DATA[total_dirs]:-"Unknown"} |

## [COMPARE] Environment Comparison

| Environment | Total Size | Files |
|-------------|------------|-------|
$(for env_data in "${ENV_COMPARISON_DATA[@]}"; do
    IFS='|' read -r env size files <<< "$env_data"
    echo "| $env | $size | $files |"
done)

---
EOF

    echo -e "${GREEN}[OK] Analysis exported to Markdown: $filename${NC}"
}

# Export to all formats simultaneously
export_all() {
    echo -e "${GREEN}Exporting analysis results to all formats...${NC}"
    echo

    export_to_json
    export_to_csv
    export_to_txt
    export_to_html
    export_to_markdown

    echo
    echo -e "${GREEN}[COMPLETE] All export formats created successfully!${NC}"
    echo "Files created:"
    echo "  - JSON: storage-analysis-${ANALYSIS_DATA[site_name]}-$(echo "${ANALYSIS_DATA[environments]}" | tr ' ' '-')-$(date +%Y%m%d-%H%M%S).json"
    echo "  - CSV: storage-analysis-${ANALYSIS_DATA[site_name]}-$(echo "${ANALYSIS_DATA[environments]}" | tr ' ' '-')-$(date +%Y%m%d-%H%M%S).csv"
    echo "  - TXT: storage-analysis-${ANALYSIS_DATA[site_name]}-$(echo "${ANALYSIS_DATA[environments]}" | tr ' ' '-')-$(date +%Y%m%d-%H%M%S).txt"
    echo "  - HTML: storage-analysis-${ANALYSIS_DATA[site_name]}-$(echo "${ANALYSIS_DATA[environments]}" | tr ' ' '-')-$(date +%Y%m%d-%H%M%S).html"
    echo "  - Markdown: storage-analysis-${ANALYSIS_DATA[site_name]}-$(echo "${ANALYSIS_DATA[environments]}" | tr ' ' '-')-$(date +%Y%m%d-%H%M%S).md"
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [site-name] [environment] [export-options]"
    echo ""
    echo "Arguments:"
    echo "  site-name    Name of the Pantheon site (optional - will prompt if not provided)"
    echo "  environment  Environment to analyze: dev, test, live, all (optional - will prompt if not provided)"
    echo ""
    echo "Export Options:"
    echo "  --export-json    Export results to JSON format"
    echo "  --export-csv     Export results to CSV format"
    echo "  --export-txt     Export results to TXT format"
    echo "  --export-html    Export results to HTML format"
    echo "  --export-md      Export results to Markdown format"
    echo "  --export-all     Export results to ALL formats (JSON, CSV, TXT, HTML, MD)"
    echo "  -e json|csv|txt|html|md|all  Short form export option"
    echo ""
    echo "Examples:"
    echo "  $0 mysite dev"
    echo "  $0 mysite all --export-json"
    echo "  $0 mysite live -e csv"
    echo "  $0 mysite live --export-all"
    echo "  $0 mysite dev -e all"
    echo "  $0  # Interactive mode"
}

# Parse arguments
SITE_NAME=""
ENV_INPUT=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h)
            show_usage
            exit 0
            ;;
        --export-json)
            EXPORT_ENABLED=true
            EXPORT_FORMAT="json"
            shift
            ;;
        --export-csv)
            EXPORT_ENABLED=true
            EXPORT_FORMAT="csv"
            shift
            ;;
        --export-txt)
            EXPORT_ENABLED=true
            EXPORT_FORMAT="txt"
            shift
            ;;
        --export-html)
            EXPORT_ENABLED=true
            EXPORT_FORMAT="html"
            shift
            ;;
        --export-md)
            EXPORT_ENABLED=true
            EXPORT_FORMAT="md"
            shift
            ;;
        --export-all)
            EXPORT_ENABLED=true
            EXPORT_FORMAT="all"
            shift
            ;;
        -e)
            EXPORT_ENABLED=true
            EXPORT_FORMAT="$2"
            if [[ ! "$EXPORT_FORMAT" =~ ^(json|csv|txt|html|md|all)$ ]]; then
                echo -e "${RED}ERROR: Invalid export format '$EXPORT_FORMAT'. Use: json, csv, txt, html, md, or all${NC}"
                exit 1
            fi
            shift 2
            ;;
        -*)
            echo -e "${RED}ERROR: Unknown option $1${NC}"
            show_usage
            exit 1
            ;;
        *)
            if [ -z "$SITE_NAME" ]; then
                SITE_NAME="$1"
            elif [ -z "$ENV_INPUT" ]; then
                ENV_INPUT="$1"
            else
                echo -e "${RED}ERROR: Too many arguments${NC}"
                show_usage
                exit 1
            fi
            shift
            ;;
    esac
done

# Get inputs if not provided
if [ -z "$SITE_NAME" ]; then
    echo "Available sites:"
    terminus site:list --format=table --fields=name 2>/dev/null
    echo
    read -p "Enter site name: " SITE_NAME
fi

if [ -z "$ENV_INPUT" ]; then
    echo "Environments: dev, test, live, all"
    read -p "Enter environment: " ENV_INPUT
fi

# Process environment selection
case $ENV_INPUT in
    "all")
        ENVIRONMENTS=("dev" "test" "live")
        ;;
    "dev"|"test"|"live")
        ENVIRONMENTS=("$ENV_INPUT")
        ;;
    *)
        echo -e "${YELLOW}Invalid environment. Using 'live'${NC}"
        ENVIRONMENTS=("live")
        ;;
esac

# Detect platform
PLATFORM=$(detect_platform $SITE_NAME)

# Initialize export data
ANALYSIS_DATA[site_name]="$SITE_NAME"
ANALYSIS_DATA[platform]="$PLATFORM"
ANALYSIS_DATA[environments]="${ENVIRONMENTS[*]}"
ANALYSIS_DATA[timestamp]="$(date)"
ENV_COMPARISON_DATA=()

echo
echo -e "${GREEN}Analyzing: $SITE_NAME${NC}"
echo -e "${GREEN}Platform: $PLATFORM${NC}"
echo -e "${GREEN}Environment(s): ${ENVIRONMENTS[*]}${NC}"
echo

# Run analysis
for env in "${ENVIRONMENTS[@]}"; do
    if terminus env:info $SITE_NAME.$env --field=id >/dev/null 2>&1; then
        case $PLATFORM in
            "wordpress")
                get_wordpress_storage "$SITE_NAME" "$env"
                ;;
            "drupal")
                get_drupal_storage "$SITE_NAME" "$env"
                ;;
            *)
                get_generic_storage "$SITE_NAME" "$env"
                ;;
        esac
    else
        echo -e "${RED}ERROR: Cannot access $SITE_NAME.$env${NC}"
        echo "------------------------------------------------"
        echo
    fi
done

# Quick comparison if multiple environments
if [ ${#ENVIRONMENTS[@]} -gt 1 ]; then
    echo -e "${GREEN}=== ENVIRONMENT COMPARISON ===${NC}"
    printf "%-12s %-15s %-12s\n" "Environment" "Total Size" "Files"
    echo "----------------------------------------"

    for env in "${ENVIRONMENTS[@]}"; do
        if terminus env:info $SITE_NAME.$env --field=id >/dev/null 2>&1; then
            # Get size and file count using platform-appropriate method
            info=$(get_basic_info "$SITE_NAME" "$env" "$PLATFORM")
            size=$(echo "$info" | cut -d'|' -f1)
            files=$(echo "$info" | cut -d'|' -f2)

            # Handle empty responses
            size=${size:-"Unknown"}
            files=${files:-"Unknown"}

            printf "%-12s %-15s %-12s\n" "$env" "$size" "$files"
            # Capture data for export
            ENV_COMPARISON_DATA+=("$env|$size|$files")
        else
            printf "%-12s %-15s %-12s\n" "$env" "ACCESS ERROR" "-"
            # Capture error data for export
            ENV_COMPARISON_DATA+=("$env|ACCESS ERROR|-")
        fi
    done
fi

echo
echo -e "${GREEN}[OK] Analysis complete!${NC}"
echo -e "${YELLOW}Note: PHP warnings from plugins are suppressed for cleaner output${NC}"

# Export functionality
if [ "$EXPORT_ENABLED" = true ]; then
    echo
    echo -e "${GREEN}Exporting analysis results...${NC}"
    case $EXPORT_FORMAT in
        "json")
            export_to_json
            ;;
        "csv")
            export_to_csv
            ;;
        "txt")
            export_to_txt
            ;;
        "html")
            export_to_html
            ;;
        "md")
            export_to_markdown
            ;;
        "all")
            export_all
            ;;
        *)
            echo -e "${RED}ERROR: Unknown export format: $EXPORT_FORMAT${NC}"
            ;;
    esac
else
    # Prompt user if they want to export
    echo
    read -p "Would you like to export the analysis results? (y/N): " export_choice
    if [[ "$export_choice" =~ ^[Yy]$ ]]; then
        echo "Available export formats:"
        echo "  1) JSON - Structured data format"
        echo "  2) CSV - Spreadsheet format"
        echo "  3) TXT - Plain text report"
        echo "  4) HTML - Formatted web report"
        echo "  5) Markdown - Documentation format"
        echo "  6) ALL - Export to all formats above"
        echo
        read -p "Choose export format (1-6): " format_choice

        case $format_choice in
            1)
                export_to_json
                ;;
            2)
                export_to_csv
                ;;
            3)
                export_to_txt
                ;;
            4)
                export_to_html
                ;;
            5)
                export_to_markdown
                ;;
            6)
                export_all
                ;;
            *)
                echo -e "${YELLOW}Invalid choice. Skipping export.${NC}"
                ;;
        esac
    fi
fi
