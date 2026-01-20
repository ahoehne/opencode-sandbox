#!/usr/bin/env bash

IMAGE_NAME="opencode-sandbox:latest"
FORCE_MODE=false
CONTAINER_RUNTIME=""

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Track what was removed for summary
REMOVED_CONTAINERS=0
REMOVED_ALIASES=0
REMOVED_IMAGE=false
REMOVED_DATA=false
REMOVED_CONFIG=false
FAILED_OPERATIONS=()

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

confirm() {
	local prompt="$1"
	local default="${2:-n}"

	if [ "$FORCE_MODE" = true ]; then
		return 0
	fi

	local yn_prompt
	if [ "$default" = "y" ]; then
		yn_prompt="[Y/n]"
	else
		yn_prompt="[y/N]"
	fi

	while true; do
		read -r -p "$(echo -e "${YELLOW}?${NC}") $prompt $yn_prompt " response
		response=${response:-$default}
		case "$response" in
			[Yy]* ) return 0;;
			[Nn]* ) return 1;;
			* ) echo "Please answer yes or no.";;
		esac
	done
}

parse_arguments() {
	while [[ $# -gt 0 ]]; do
		case $1 in
			-f|--force)
				FORCE_MODE=true
				shift
				;;
			-h|--help)
				show_help
				exit 0
				;;
			*)
				error "Unknown option: $1"
				show_help
				exit 1
				;;
		esac
	done
}

show_help() {
	cat << EOF
OpenCode Sandbox Uninstaller

Usage: ./uninstall.sh [OPTIONS]

Options:
  -f, --force    Skip all prompts and remove everything
  -h, --help     Show this help message

Interactive Mode (default):
  The script will prompt you for each component:
  - Running/stopped containers
  - Shell aliases (bash, zsh, fish)
  - Container image (Podman or Docker)
  - Data directories (~/.sandboxes/opencode/)
  - Configuration (~/.config/opencode/)

Force Mode:
  Removes all components without prompting.
  Use with caution - this will delete all data.

EOF
}

# Detect available container runtime (prefer Podman, fallback to Docker)
detect_container_runtime() {
	# Check for podman first (preferred)
	if command -v podman &>/dev/null; then
		CONTAINER_RUNTIME="podman"
		return 0
	fi

	# Fallback to docker
	if command -v docker &>/dev/null; then
		CONTAINER_RUNTIME="docker"
		return 0
	fi

	# Neither found
	return 1
}

check_container_runtime() {
	if ! detect_container_runtime; then
		warn "Neither Podman nor Docker is installed. Skipping container and image cleanup."
		return 1
	fi
	info "Using $CONTAINER_RUNTIME for cleanup"
	return 0
}

remove_containers() {
	if ! check_container_runtime; then
		return
	fi

	info "Checking for containers using $IMAGE_NAME..."

	local container_ids
	container_ids=$($CONTAINER_RUNTIME ps -a --filter "ancestor=$IMAGE_NAME" --format "{{.ID}}" 2>/dev/null)

	if [ -z "$container_ids" ]; then
		info "No containers found"
		return
	fi

	local container_count
	container_count=$(echo "$container_ids" | wc -l)
	info "Found $container_count container(s):"
	$CONTAINER_RUNTIME ps -a --filter "ancestor=$IMAGE_NAME" --format "table {{.ID}}\t{{.Status}}\t{{.Names}}"
	echo ""

	if confirm "Stop and remove these containers?" "y"; then
		for container_id in $container_ids; do
			info "Stopping container $container_id..."
			if $CONTAINER_RUNTIME stop "$container_id" &>/dev/null; then
				info "Stopped $container_id"
			else
				warn "Container $container_id may already be stopped"
			fi

			info "Removing container $container_id..."
			if $CONTAINER_RUNTIME rm "$container_id" &>/dev/null; then
				info "Removed $container_id"
				((REMOVED_CONTAINERS++))
			else
				error "Failed to remove container $container_id"
				FAILED_OPERATIONS+=("Remove container $container_id")
			fi
		done
	else
		info "Skipping container removal"
	fi
}

remove_alias_from_file() {
	local file="$1"
	local shell_name="$2"

	if [ ! -f "$file" ]; then
		return
	fi

	if grep -q "alias opencode=" "$file" 2>/dev/null; then
		info "Removing alias from $file..."
		sed -i '/# OpenCode sandbox alias/d' "$file"
		sed -i '/alias opencode=/d' "$file"
		info "$shell_name: alias removed from $file"
		((REMOVED_ALIASES++))
	fi
}

remove_aliases() {
	info "Checking for shell aliases..."

	local found_aliases=false

	if [ -f "$HOME/.bashrc" ] && grep -q "alias opencode=" "$HOME/.bashrc" 2>/dev/null; then
		found_aliases=true
	fi

	if [ -f "$HOME/.zshrc" ] && grep -q "alias opencode=" "$HOME/.zshrc" 2>/dev/null; then
		found_aliases=true
	fi

	if [ -f "$HOME/.config/fish/config.fish" ] && grep -q "alias opencode=" "$HOME/.config/fish/config.fish" 2>/dev/null; then
		found_aliases=true
	fi

	if [ "$found_aliases" = false ]; then
		info "No aliases found"
		return
	fi

	echo "Found 'opencode' alias in shell configuration files"
	echo ""

	if confirm "Remove shell aliases?" "y"; then
		remove_alias_from_file "$HOME/.bashrc" "bash"
		remove_alias_from_file "$HOME/.zshrc" "zsh"
		remove_alias_from_file "$HOME/.config/fish/config.fish" "fish"
	else
		info "Skipping alias removal"
	fi
}

remove_image() {
	if ! check_container_runtime; then
		return
	fi

	info "Checking for $IMAGE_NAME image..."

	if ! $CONTAINER_RUNTIME images "$IMAGE_NAME" --format "{{.Repository}}" | grep -q "^${IMAGE_NAME%:*}$"; then
		info "Image not found"
		return
	fi

	local image_size
	image_size=$($CONTAINER_RUNTIME images "$IMAGE_NAME" --format "{{.Size}}" 2>/dev/null)
	echo "Image: $IMAGE_NAME"
	echo "Size: $image_size"
	echo ""

	if confirm "Remove container image?" "y"; then
		info "Removing image $IMAGE_NAME..."
		if $CONTAINER_RUNTIME rmi "$IMAGE_NAME" &>/dev/null; then
			info "Image removed successfully"
			REMOVED_IMAGE=true
		else
			error "Failed to remove image"
			FAILED_OPERATIONS+=("Remove image $IMAGE_NAME")
		fi
	else
		info "Skipping image removal"
	fi
}

remove_data_dirs() {
	local data_dir="$HOME/.sandboxes/opencode"

	info "Checking for data directories..."

	if [ ! -d "$data_dir" ]; then
		info "Data directory not found"
		return
	fi

	local dir_size
	dir_size=$(du -sh "$data_dir" 2>/dev/null | cut -f1)

	echo "Data directory: $data_dir"
	echo "Size: $dir_size"
	echo "Contains: npm cache, opencode packages, cache, local data"
	echo ""
	warn "This will delete all cached npm packages and OpenCode data"
	echo ""

	if confirm "Remove data directories?" "n"; then
		info "Removing $data_dir..."
		if rm -rf "$data_dir"; then
			info "Data directories removed"
			REMOVED_DATA=true
		else
			error "Failed to remove data directories"
			FAILED_OPERATIONS+=("Remove $data_dir")
		fi
	else
		info "Skipping data directory removal"
	fi
}

remove_config() {
	local config_dir="$HOME/.config/opencode"

	info "Checking for configuration directory..."

	if [ ! -d "$config_dir" ]; then
		info "Configuration directory not found"
		return
	fi

	local dir_size
	dir_size=$(du -sh "$config_dir" 2>/dev/null | cut -f1)

	echo "Configuration directory: $config_dir"
	echo "Size: $dir_size"
	echo ""
	warn "This will delete all OpenCode settings and configuration"
	echo ""

	if confirm "Remove configuration directory?" "n"; then
		info "Removing $config_dir..."
		if rm -rf "$config_dir"; then
			info "Configuration directory removed"
			REMOVED_CONFIG=true
		else
			error "Failed to remove configuration directory"
			FAILED_OPERATIONS+=("Remove $config_dir")
		fi
	else
		info "Skipping configuration removal"
	fi
}

show_summary() {
	echo ""
	echo "=============================================="
	echo "  Uninstall Summary"
	echo "=============================================="
	echo ""

	if [ "$REMOVED_CONTAINERS" -gt 0 ]; then
		info "Removed $REMOVED_CONTAINERS container(s)"
	fi

	if [ "$REMOVED_ALIASES" -gt 0 ]; then
		info "Removed aliases from $REMOVED_ALIASES shell configuration file(s)"
	fi

	if [ "$REMOVED_IMAGE" = true ]; then
		info "Removed container image: $IMAGE_NAME"
	fi

	if [ "$REMOVED_DATA" = true ]; then
		info "Removed data directory: ~/.sandboxes/opencode/"
	fi

	if [ "$REMOVED_CONFIG" = true ]; then
		info "Removed configuration directory: ~/.config/opencode/"
	fi

	if [ "$REMOVED_CONTAINERS" -eq 0 ] && [ "$REMOVED_ALIASES" -eq 0 ] && \
	   [ "$REMOVED_IMAGE" = false ] && [ "$REMOVED_DATA" = false ] && \
	   [ "$REMOVED_CONFIG" = false ]; then
		warn "Nothing was removed"
	fi

	if [ ${#FAILED_OPERATIONS[@]} -gt 0 ]; then
		echo ""
		warn "Failed operations:"
		for op in "${FAILED_OPERATIONS[@]}"; do
			echo "  - $op"
		done
	fi

	echo ""

	if [ "$REMOVED_ALIASES" -gt 0 ]; then
		echo "Reload your shell to remove the 'opencode' alias:"
		command -v bash &>/dev/null && echo "  source ~/.bashrc"
		command -v zsh &>/dev/null && echo "  source ~/.zshrc"
		command -v fish &>/dev/null && echo "  source ~/.config/fish/config.fish"
		echo ""
	fi

	echo "=============================================="
	info "Uninstall complete!"
	echo "=============================================="
}

main() {
	parse_arguments "$@"

	echo "=============================================="
	echo "  OpenCode Sandbox Uninstaller"
	echo "=============================================="
	echo ""

	if [ "$FORCE_MODE" = true ]; then
		warn "Force mode enabled - all components will be removed without prompting"
		echo ""
	else
		info "Running in interactive mode"
		info "You will be prompted for each component"
		echo ""
		warn "Tip: You can backup data manually before proceeding:"
		echo "  tar -czf opencode-backup.tar.gz ~/.sandboxes/opencode ~/.config/opencode"
		echo ""
	fi

	remove_containers
	echo ""

	remove_aliases
	echo ""

	remove_image
	echo ""

	remove_data_dirs
	echo ""

	remove_config

	show_summary
}

main "$@"
