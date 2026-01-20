# OpenCode Sandbox
A containerized environment for running OpenCode AI coding agent with strict isolation from your host system.

Supports both **Podman** (recommended) and **Docker**.

## Prerequisites

You need either Podman or Docker installed. The installer automatically detects which runtime is available, preferring Podman if both are installed.

### Option 1: Podman (Recommended)
- Podman installed (rootless by default)
- systemd (required for Podman socket management)

#### Verify Podman Installation
```bash
# Check if Podman is installed
podman --version

# Check if Podman Socket is enabled (needed to start container)
systemctl --user status podman.socket

# If not: enable and start it:
systemctl --user enable --now podman.socket
```

### Option 2: Docker
- Docker installed
- Docker daemon running
- User in docker group OR sudo access

#### Verify Docker Installation
```bash
# Check if Docker is installed
docker --version

# Check if Docker daemon is running
docker info

# If you get permission errors, add yourself to docker group:
sudo usermod -aG docker $USER
# Then log out and back in
```

## Installation
```bash
git clone https://github.com/ahoehne/opencode-sandbox.git
cd opencode-sandbox
./install.sh
```

The installer will:
- Detect available container runtime (Podman or Docker)
- Build the container image
- Create required directories
- Install the `opencode` alias for all detected shells (bash, zsh, fish)

After installation, reload your shell or follow the instructions shown by the installer.

## Uninstallation

### Interactive Mode (Recommended)
Run the uninstaller and choose what to remove:
```bash
./uninstall.sh
```

The uninstaller will prompt you for each component:
- Running/stopped containers
- Shell aliases (bash, zsh, fish)
- Container image (`opencode-sandbox:latest`)
- Data directories (`~/.sandboxes/opencode/`)
- Configuration directory (`~/.config/opencode/`)

### Force Mode
Remove everything without prompts:
```bash
./uninstall.sh --force
```

**Warning:** Force mode will delete all data, configuration, and containers without confirmation.

### Manual Backup (Optional)
Before uninstalling, you can backup your data and configuration:
```bash
tar -czf opencode-backup.tar.gz ~/.sandboxes/opencode ~/.config/opencode
```

## Usage
Never start opencode from other directories than your project directory (especially not homefolder)
Navigate to your project directory and run:
```bash
opencode
```

## Understanding the Setup

### Container Runtime Detection
The installer automatically detects available container runtimes:
1. Checks for Podman (preferred)
2. Falls back to Docker if Podman not found
3. Fails with clear instructions if neither is available

The detected runtime is stored in your shell alias, so switching runtimes requires re-running the installer.

### Key Features
1. **`--network host`**: Allows the container to access local services on your host machine, for instance LM Studio or a started webapp
2. **`TERM=xterm-256color`**: Proper terminal emulation for the TUI
3. **`-it` flags**: Required for interactive TTY allocation

### Security Features
The OpenCode sandbox uses multiple security layers:

| Feature | Podman | Docker | Description |
|---------|--------|--------|-------------|
| User Namespace Mapping | `--userns=keep-id` | n/a | Container user matches host user |
| User/Group Mapping | `--user $(id -u):$(id -g)` | `--user $(id -u):$(id -g)` | Run as current user |
| Read-only Filesystem | `--read-only` | `--read-only` | Prevents modifications to container image |
| Temporary Filesystem | `--tmpfs /tmp` | `--tmpfs /tmp` | Allows temporary files with size limits |
| Capability Dropping | `--cap-drop=ALL` | `--cap-drop=ALL` | Removes all Linux capabilities |
| No New Privileges | `--security-opt=no-new-privileges` | `--security-opt=no-new-privileges` | Prevents privilege escalation |
| SELinux Context | `:Z` suffix | `:Z` suffix | Proper SELinux labeling for volumes |

**Note:** Podman's `--userns=keep-id` provides additional user namespace isolation that Docker does not support natively.

### Directory Structure
The sandbox mounts these directories from your host:
- `~/.config/opencode/` -> `/home/opencodeuser/.config/opencode/` (OpenCode configuration)

  Note: it is using your ~/.config/opencode folder, if you dont want this, create a folder in ~/.sandboxes/opencode and change the alias
- `~/.sandboxes/opencode/.npm/` -> `/home/opencodeuser/.npm/` (Node.js packages)
- `~/.sandboxes/opencode/.opencode/` -> `/home/opencodeuser/.opencode/` (OpenCode global packages)
- `~/.sandboxes/opencode/.cache/` -> `/home/opencodeuser/.cache/` (Application cache)
- `~/.sandboxes/opencode/.local/` -> `/home/opencodeuser/.local/` (Local data)
- `~/.sandboxes/opencode/.cargo/` -> `/home/opencodeuser/.cargo/` (Rust packages)
- `./workspace/` -> `/workspace/` (Current project directory, read-only)

## Troubleshooting

### General Issues

#### Container hangs on startup
If the container appears to hang:

1. Check container status:
```bash
# For Podman
podman ps
podman ps -a  # Show all containers including stopped ones

# For Docker
docker ps
docker ps -a
```

2. Check container logs:
```bash
# For Podman
podman logs <container-id>

# For Docker
docker logs <container-id>
```

#### Permission errors
```bash
# Fix ownership on sandbox directories
chown -R $(id -u):$(id -g) ~/.config/opencode ~/.sandboxes/opencode

# Verify directory permissions
ls -la ~/.sandboxes/opencode/
ls -la ~/.config/opencode/
```

#### npm install fails with ECONNRESET
If opencode-ai installation fails with network errors:

1. **Retry by restarting the container** - transient network issues are common:
   ```bash
   opencode  # Just run again
   ```

2. **Check host network connectivity**:
   ```bash
    # Test from host
    curl -I https://registry.npmjs.org/
    ```

### Podman-specific Issues

#### Podman socket not active
```bash
# Enable and start the socket
systemctl --user enable --now podman.socket

# Verify it's running
systemctl --user status podman.socket
```

#### SELinux denials
If you see SELinux-related errors:
```bash
# Check for denials
sudo ausearch -m avc -ts recent

# The :Z suffix should handle most cases, but you may need to relabel:
chcon -Rt svirt_sandbox_file_t ~/.sandboxes/opencode
```

### Docker-specific Issues

#### Permission denied connecting to Docker daemon
```bash
# Add yourself to docker group
sudo usermod -aG docker $USER

# Log out and back in, or run:
newgrp docker

# Verify access
docker info
```

#### Docker daemon not running
```bash
# Start Docker daemon
sudo systemctl start docker

# Enable on boot
sudo systemctl enable docker
```

#### Rootless Docker setup (optional)
For enhanced security with Docker, consider rootless mode:
```bash
# Install rootless dependencies
sudo apt-get install -y uidmap

# Set up rootless Docker
dockerd-rootless-setuptool.sh install

# Use rootless Docker
export DOCKER_HOST=unix://$XDG_RUNTIME_DIR/docker.sock
```

### Switching Between Runtimes
If you switch from Podman to Docker (or vice versa):
```bash
# Re-run the installer to update aliases
./install.sh
```

The installer will detect the new runtime and update your shell aliases accordingly.

Follow instructions to reload shell or just open another.

