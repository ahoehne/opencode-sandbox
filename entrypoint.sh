#!/usr/bin/env bash
set -e

# Color constants
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Helper functions
info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Sandbox flags (use --sandbox-* prefix to avoid conflicts with opencode flags)
FLAG_FORCE_UPDATE=false
FLAG_DEBUG=false
FLAG_SKIP_INSTALL=false

# Parse command-line flags (--sandbox-* flags are consumed, rest passed to opencode)
OPENCODE_ARGS=()
for arg in "$@"; do
	case "$arg" in
		--sandbox-force-update) FLAG_FORCE_UPDATE=true ;;
		--sandbox-debug)        FLAG_DEBUG=true ;;
		--sandbox-skip-install) FLAG_SKIP_INSTALL=true ;;
		*)                      OPENCODE_ARGS+=("$arg") ;;
	esac
done

debug() { if [[ "$FLAG_DEBUG" = true ]]; then echo -e "${YELLOW}[DEBUG]${NC} $1"; fi; }

debug "FLAG_FORCE_UPDATE=$FLAG_FORCE_UPDATE"
debug "FLAG_DEBUG=$FLAG_DEBUG"
debug "FLAG_SKIP_INSTALL=$FLAG_SKIP_INSTALL"
debug "OPENCODE_ARGS=${OPENCODE_ARGS[*]}"

# Check if npm is available
check_npm() {
	if ! command -v npm &>/dev/null; then
		error "npm is not installed in container"
	fi
}

# Check if opencode is already installed
check_opencode_installed() {
	command -v opencode &>/dev/null
}

# Install or update opencode-ai
install_opencode() {
	# Skip install entirely if requested
	if [[ "$FLAG_SKIP_INSTALL" = true ]]; then
		debug "Skipping install check (--sandbox-skip-install)"
		return
	fi

	# Force update if requested
	if [[ "$FLAG_FORCE_UPDATE" = true ]]; then
		info "Force update requested, reinstalling opencode-ai..."
		npm install -g opencode-ai || error "Failed to install opencode-ai"
		return
	fi

	# Smart update: only install if not present
	if check_opencode_installed; then
		local version
		version=$(opencode --version 2>/dev/null || echo "unknown")
		if [ -z "$version" ]; then
			warn "opencode found but version check failed, forcing reinstall..."
			npm install -g opencode-ai || error "Failed to install opencode-ai"
			return
		fi
		info "opencode already installed ($version), skipping reinstall"
		info "Use --sandbox-force-update to force reinstall"
	else
		info "opencode not found, installing opencode-ai..."
		npm install -g opencode-ai || error "Failed to install opencode-ai"

		# Verify installation succeeded
		if ! check_opencode_installed; then
			error "opencode-ai installed but opencode command not found in PATH"
		fi

		local version
		version=$(opencode --version 2>/dev/null || echo "unknown")
		info "opencode installed successfully ($version)"
	fi
}

# Main execution
main() {
	debug "Starting entrypoint in $(pwd)"
	info "Checking prerequisites..."
	check_npm

	install_opencode

	info "Starting opencode in $(pwd)..."
	debug "Executing: opencode ${OPENCODE_ARGS[*]}"
	exec opencode "${OPENCODE_ARGS[@]}"
}

main
