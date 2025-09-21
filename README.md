# Pantheon Storage Analysis Tool

A comprehensive storage analysis script for sites hosted on Pantheon with automatic platform detection and multi-format export capabilities.

## Features

- **Platform Auto-Detection**: Automatically identifies WordPress, Drupal, or generic sites
- **Comprehensive Analysis**: Total site size, directory breakdown, file statistics, and component analysis
- **Multi-Environment Support**: Analyze dev, test, live, or all environments with comparison
- **Export Capabilities**: JSON, CSV, TXT, HTML, and Markdown formats
- **Robust Error Handling**: Handles PHP warnings and broken pipe errors common on Pantheon
- **Database Size Reporting**: Platform-specific database size analysis

## Requirements

- **Terminus CLI** (`/usr/local/bin/terminus`): Pantheon's command-line tool
- **Authenticated Terminus session**: Must be logged in via `terminus auth:login`
- **Platform-specific tools**:
  - WordPress sites: WP-CLI integration via `terminus remote:wp`
  - Drupal sites: Drush integration via `terminus remote:drush`
  - Generic sites: SSH access via Terminus connection info
- **Standard Unix tools**: `du`, `find`, `wc`, `grep`

## Installation

1. Clone this repository:
```bash
git clone https://github.com/hiiamhuy/storage-analysis.git
cd storage-analysis
```

2. Make the script executable:
```bash
chmod +x storage-analysis.sh
```

3. Ensure Terminus CLI is installed and authenticated:
```bash
terminus auth:login
```

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
- `dev`: Development environment
- `test`: Test environment
- `live`: Production environment
- `all`: Analyze all three environments with comparison

### Examples
```bash
# Analyze live environment
./storage-analysis.sh mysite live

# Compare all environments
./storage-analysis.sh mysite all

# Interactive mode
./storage-analysis.sh
```

## Output

The script provides detailed analysis including:

- **Total site size** using `du` commands
- **Directory breakdown** of root-level directories, sorted by size
- **Content analysis**:
  - WordPress: wp-content breakdown (plugins, uploads, themes)
  - Drupal: sites/default/files and modules analysis
- **File statistics** including total file counts
- **Component analysis**:
  - WordPress: largest plugins
  - Drupal: largest modules
- **Database size** using platform-appropriate tools
- **Multi-environment comparison** (when using `all` option)

## Export Formats

The script supports exporting results to multiple formats:

- **JSON**: Structured data for programmatic processing
- **CSV**: Spreadsheet format for data analysis
- **TXT**: Plain text report
- **HTML**: Formatted web report with styling
- **Markdown**: Documentation format for GitHub/wikis
- **ALL**: Export to all formats simultaneously

Export files are automatically named: `storage-analysis-{site}-{envs}-{timestamp}.{format}`

## Platform Support

### WordPress Sites
- Uses `terminus remote:wp` with WP-CLI eval commands
- Detailed wp-content analysis (plugins, themes, uploads)
- Plugin size analysis for largest components
- Database size via WP-CLI

### Drupal Sites
- Uses `terminus remote:drush` with Drush eval commands
- Analysis of sites/default/files and modules
- Module size breakdown
- Database size via Drush

### Generic Sites
- SSH-based analysis using Terminus connection info
- Basic file system analysis
- Standard Unix commands for size calculation

## Technical Implementation

### Error Handling
- **PHP warning suppression** using `error_reporting(E_ERROR | E_PARSE)`
- **Broken pipe prevention** by processing data in PHP arrays
- **Command output filtering** to remove noise and warnings
- **Platform-specific error handling** for different tool variations

### Performance Considerations
- Efficient `du` commands for size calculations
- Array-based processing to avoid shell pipe issues
- Optimized file counting methods
- Minimal external command calls

## Troubleshooting

### Common Issues

1. **Authentication Problems**
```bash
terminus auth:whoami
terminus auth:login
```

2. **Permission Issues**
```bash
chmod +x storage-analysis.sh
```

3. **Platform Detection Issues**
```bash
terminus site:info sitename --field=framework
```

4. **Connection Problems**
```bash
terminus connection:info sitename.env
```

## Development

### Testing
```bash
# Test authentication
terminus auth:whoami

# List available sites
terminus site:list

# Test specific site access
terminus env:info sitename.env
```

### Basic Tests
The repository includes basic test scripts in the `basic-tests/` directory:
- `auth-test.sh`: Check Terminus authentication
- `connection-test.sh`: Test site connectivity
- `platform-test.sh`: Verify platform detection
- `simple-storage.sh`: Basic storage analysis

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test with various site types
5. Submit a pull request

## License

This project is open source and available under the MIT License.

## Support

For issues, questions, or contributions, please use the GitHub issue tracker.