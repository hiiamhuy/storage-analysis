# Basic Test Scripts for Pantheon Storage Analysis

These simplified scripts help troubleshoot authentication and connection issues with the main storage analysis tool.

## The Problem

Users encountering this error:
```
dev.6164a8ae-ecfa-46ea-a3eb-0c2575daca2d@appserver.dev.6164a8ae-ecfa-46ea-a3eb-0c2575daca2d.drush.in: Permission denied (publickey).
```

This indicates SSH authentication failures when Terminus tries to execute remote commands.

## Troubleshooting Scripts

### 1. `auth-test.sh` - Authentication Test
Tests basic Terminus authentication and site access.

**Usage:**
```bash
./auth-test.sh [site-name]
```

**What it checks:**
- Terminus CLI installation
- Authentication status (`terminus auth:whoami`)
- Site accessibility
- Environment availability

**Example:**
```bash
./auth-test.sh uwsurgery
```

### 2. `connection-test.sh` - Connection Test
Tests SSH connectivity and remote command execution.

**Usage:**
```bash
./connection-test.sh <site-name> [environment]
```

**What it checks:**
- Environment accessibility
- SSH connection via `terminus env:ssh`
- Platform-specific tools (WP-CLI/Drush)
- Connection information

**Example:**
```bash
./connection-test.sh uwsurgery dev
```

### 3. `platform-test.sh` - Platform Detection
Tests platform detection without remote execution.

**Usage:**
```bash
./platform-test.sh <site-name>
```

**What it checks:**
- Site framework detection
- Environment details
- Available platform tools

**Example:**
```bash
./platform-test.sh uwsurgery
```

### 4. `simple-storage.sh` - Minimal Storage Analysis
Basic storage analysis using SSH instead of WP-CLI/Drush eval.

**Usage:**
```bash
./simple-storage.sh <site-name> [environment]
```

**What it does:**
- Uses direct SSH commands instead of complex PHP eval
- Gets basic size and file count information
- Avoids potential WP-CLI/Drush issues

**Example:**
```bash
./simple-storage.sh uwsurgery dev
```

### 5. `debug-info.sh` - System Debug Information
Collects comprehensive system and environment information.

**Usage:**
```bash
./debug-info.sh [site-name]
```

**What it collects:**
- Operating system information
- WSL environment details (if applicable)
- SSH configuration and keys
- Terminus configuration
- Network connectivity
- Site-specific connectivity tests

**Example:**
```bash
./debug-info.sh uwsurgery
```

## Recommended Troubleshooting Steps

### Step 1: Basic Authentication
```bash
./auth-test.sh uwsurgery
```
This verifies you can authenticate and access the site.

### Step 2: Connection Testing
```bash
./connection-test.sh uwsurgery dev
```
This isolates SSH connectivity issues.

### Step 3: Debug Information
```bash
./debug-info.sh uwsurgery
```
Collect detailed system information for support.

### Step 4: Simple Storage Analysis
```bash
./simple-storage.sh uwsurgery dev
```
Try basic storage analysis without complex remote commands.

## Common Solutions

### SSH Key Issues
1. **Generate new SSH keys:**
   ```bash
   ssh-keygen -t rsa -b 4096 -C "your.email@domain.com"
   ```

2. **Add to SSH agent:**
   ```bash
   eval "$(ssh-agent -s)"
   ssh-add ~/.ssh/id_rsa
   ```

3. **Add public key to Pantheon:**
   - Go to Pantheon Dashboard → Account → SSH Keys
   - Add contents of `~/.ssh/id_rsa.pub`

### Machine Token Authentication
Use machine tokens for automation:
```bash
terminus auth:login --machine-token=YOUR_TOKEN
```

### WSL-Specific Issues
For Windows WSL users:
1. Ensure SSH agent is running
2. Check SSH key permissions: `chmod 600 ~/.ssh/id_rsa`
3. Verify network connectivity to Pantheon

## Expected Output Patterns

### Success Pattern
```
✓ Authenticated as: user@domain.com
✓ Site accessible
✓ SSH connection successful
✓ Total site size: 2.1GB
```

### Failure Pattern
```
✗ ERROR: SSH connection failed
Error output: Permission denied (publickey)
```

## Getting Help

If all scripts fail with SSH errors:
1. Run `debug-info.sh` and save output
2. Check SSH key configuration in Pantheon dashboard
3. Try regenerating SSH keys
4. Contact support with debug information