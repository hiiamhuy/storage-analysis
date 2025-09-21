# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository contains a single Bash script (`storage-analysis.sh`) that provides comprehensive storage analysis for sites hosted on Pantheon. The script automatically detects the platform type (WordPress, Drupal, or generic) and provides platform-appropriate analysis. It is designed to handle common issues with PHP warnings and broken pipe errors that occur when analyzing site storage.

## Core Functionality

The script performs the following analyses:
- **Platform auto-detection** - Identifies WordPress, Drupal, or generic sites
- **Total site size calculation** using `du` commands
- **Directory breakdown** of root-level directories, sorted by size
- **Content analysis** - WordPress: wp-content (plugins, uploads, themes); Drupal: sites/default/files and modules
- **File statistics** including total file counts and platform-specific directory counts
- **Component analysis** - WordPress: largest plugins; Drupal: largest modules
- **Files breakdown** showing storage usage patterns
- **Database size reporting** using platform-appropriate tools (WP-CLI for WordPress, Drush for Drupal)
- **Multi-environment comparison** when analyzing multiple environments

## Dependencies

The script requires:
- **Terminus CLI** (`/usr/local/bin/terminus`) - Pantheon's command-line tool
- **Authenticated Terminus session** - User must be logged in via `terminus auth:login`
- **Platform-specific tools**:
  - WordPress sites: WP-CLI integration via `terminus remote:wp`
  - Drupal sites: Drush integration via `terminus remote:drush`
  - Generic sites: SSH access via Terminus connection info
- **Standard Unix tools**: `du`, `find`, `wc`, `grep`

## Usage

### Basic Usage
```bash
./storage-analysis.sh [site-name] [environment]
```

### Interactive Mode
```bash
./storage-analysis.sh
# Will prompt for site name and environment
```

### Environment Options
- `dev` - Development environment
- `test` - Test environment
- `live` - Production environment
- `all` - Analyze all three environments with comparison

### Examples
```bash
./storage-analysis.sh mysite live
./storage-analysis.sh mysite all
./storage-analysis.sh  # Interactive mode
```

## Technical Implementation

### Platform Detection and Routing
The script automatically detects the platform type using `terminus site:info --field=framework` and routes to appropriate analysis methods:
- **WordPress sites**: Uses `terminus remote:wp` with complex PHP eval statements for detailed analysis
- **Drupal sites**: Uses `terminus remote:drush` with simplified eval commands and SSH fallback
- **Generic sites**: Uses SSH-based commands for basic file system analysis

### Error Handling
The script implements robust error handling for common Pantheon issues:
- **PHP warning suppression** using `error_reporting(E_ERROR | E_PARSE)` and `ini_set('display_errors', 0)`
- **Broken pipe prevention** by avoiding external sorting and processing data in PHP arrays
- **Command output filtering** using `2>/dev/null` and `grep -v "Warning:"`
- **Platform-specific error handling** for WP-CLI and Drush command variations

### Storage Calculation Methods
- **WordPress**: Uses `du -sk` commands executed via `terminus remote:wp` with PHP eval, processing results in PHP arrays to avoid shell pipe issues
- **Drupal**: Uses simplified `shell_exec()` calls via `terminus remote:drush` for better compatibility
- **Generic**: Uses direct SSH commands via Terminus connection info for basic file system analysis
- All size calculations are done in kilobytes and converted to human-readable formats (KB/MB/GB)

### Multi-Environment Support
When analyzing multiple environments, the script provides a comparison table showing total size and file counts across dev/test/live environments. The comparison uses platform-appropriate methods:
- **WordPress**: WP-CLI eval commands
- **Drupal**: Drush eval commands
- **Generic**: SSH-based commands

### Supported Platforms
- **WordPress** (`framework: wordpress`): Full-featured analysis using WP-CLI
- **Drupal** (`framework: drupal*`): Comprehensive analysis using Drush and SSH
- **Generic/Other**: Basic file system analysis using SSH commands

## Development and Testing

### Script Testing
```bash
# Test the script with different sites and environments
./storage-analysis.sh test-site dev
./storage-analysis.sh test-site all

# Check script syntax
bash -n storage-analysis.sh

# Debug mode (add set -x to script temporarily)
bash -x storage-analysis.sh
```

### Common Development Tasks
- **Testing authentication**: `terminus auth:whoami`
- **List available sites**: `terminus site:list`
- **Check environment status**: `terminus env:info site.env`
- **Debug connection issues**: `terminus connection:info site.env`

## Export Functionality

The script supports multiple export formats for analysis results:
- **JSON** - Structured data format for programmatic processing
- **CSV** - Spreadsheet format for data analysis
- **TXT** - Plain text report for documentation
- **HTML** - Formatted web report with styling
- **Markdown** - Documentation format for GitHub/wikis
- **ALL** - Exports to all formats simultaneously

Export files are automatically named with timestamp patterns: `storage-analysis-{site}-{envs}-{timestamp}.{format}`

## Script Architecture

### Core Functions
- `detect_platform()` - Auto-detects WordPress, Drupal, or generic platforms
- `get_wordpress_storage()` - WordPress-specific analysis using WP-CLI eval
- `get_drupal_storage()` - Drupal-specific analysis using Drush eval
- `get_generic_storage()` - SSH-based analysis for generic platforms
- `get_basic_info()` - Universal function for environment comparisons
- `export_to_*()` - Multiple export format functions

### Data Processing Flow
1. **Authentication Check** - Validates Terminus CLI access
2. **Platform Detection** - Determines site framework type
3. **Environment Validation** - Verifies environment accessibility
4. **Storage Analysis** - Platform-specific data collection
5. **Multi-Environment Comparison** - Cross-environment statistics (when applicable)
6. **Export Processing** - Optional data export in various formats

### Error Resilience
The script is designed to handle common Pantheon hosting issues:
- Suppresses PHP warnings that don't affect functionality
- Uses array processing in PHP to avoid broken pipe errors
- Implements fallback methods for different platform configurations
- Filters command output to remove noise and warnings