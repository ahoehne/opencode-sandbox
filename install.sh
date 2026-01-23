#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="opencode-sandbox:latest"
CONTAINER_RUNTIME=""

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

detect_container_runtime() {
	# Check for podman first (preferred)
	if command -v podman &>/dev/null; then
		CONTAINER_RUNTIME="podman"
		local version_output
		version_output=$(podman --version 2>&1)
		info "Found: $version_output"
		return 0
	fi

	# Fallback to docker
	if command -v docker &>/dev/null; then
		CONTAINER_RUNTIME="docker"
		local version_output
		version_output=$(docker --version 2>&1)
		info "Found: $version_output"
		return 0
	fi

	error "Neither Podman nor Docker found. Please install one:\n" \
	  "Podman: https://podman.io/getting-started/installation\n" \
	  "Docker: https://docs.docker.com/get-docker/"
}

check_runtime_prerequisites() {
	if [ "$CONTAINER_RUNTIME" = "podman" ]; then
		if ! systemctl --user is-active podman.socket &>/dev/null; then
			error "Podman socket is not active. Enable it with:\n" \
			  "systemctl --user enable --now podman.socket\n" \
			  "Then run this installer again."
		fi
		info "Podman socket is active"
	elif [ "$CONTAINER_RUNTIME" = "docker" ]; then
		if ! docker info &>/dev/null; then
			error "Docker daemon is not running or not accessible.\n" \
			  "Ensure Docker is running and you have permission to use it:\n" \
			  "sudo systemctl enable --now docker\n" \
			  "sudo usermod -aG docker \$USER  # Then log out and back in"
		fi
		info "Docker daemon is accessible"
	fi
}

get_security_flags() {
	local runtime="$1"
	local shell_type="$2"

	local user_flag
	if [ "$shell_type" = "fish" ]; then
		user_flag='--user (id -u):(id -g)'
	else
		# shellcheck disable=SC2016
		user_flag='--user $(id -u):$(id -g)'
	fi

	local common_flags="--network host --read-only --tmpfs /tmp:rw,exec,size=1g --security-opt=no-new-privileges --cap-drop=ALL"

  # Podman supports --userns=keep-id, Docker does not
	if [ "$runtime" = "podman" ]; then
		echo "--userns=keep-id $user_flag $common_flags"
	else
		echo "$user_flag $common_flags"
	fi
}

get_volume_mounts() {
	local shell_type="$1"
	local home_var

	if [ "$shell_type" = "fish" ]; then
		home_var="\$HOME"
	else
		home_var="\$HOME"
	fi

	# SELinux :Z label is safe on non-SELinux systems
	echo "-v \"${home_var}/.sandboxes/opencode/.npm:/home/opencodeuser/.npm:Z\" -v \"${home_var}/.sandboxes/opencode/.opencode:/home/opencodeuser/.opencode:Z\" -v \"${home_var}/.sandboxes/opencode/.cache:/home/opencodeuser/.cache:Z\" -v \"${home_var}/.sandboxes/opencode/.local:/home/opencodeuser/.local:Z\" -v \"${home_var}/.sandboxes/opencode/.cargo:/home/opencodeuser/.cargo:Z\" -v \"${home_var}/.config/opencode:/home/opencodeuser/.config/opencode:Z\" -v \"\$PWD:/workspace:Z\" -w /workspace"
}

generate_alias() {
	local runtime="$1"
	local shell_type="$2"

	local security_flags
	security_flags=$(get_security_flags "$runtime" "$shell_type")

	local volume_mounts
	volume_mounts=$(get_volume_mounts "$shell_type")

	echo "alias opencode='${runtime} run -it --rm ${security_flags} ${volume_mounts} ${IMAGE_NAME}'"
}

build_image() {
	local host_uid
	local host_gid
	host_uid=$(id -u)
	host_gid=$(id -g)

	info "Building opencode-sandbox image using $CONTAINER_RUNTIME..."
	info "Using UID:GID ${host_uid}:${host_gid} from host user"

	cd "$SCRIPT_DIR"
	if $CONTAINER_RUNTIME build \
		--build-arg USER_UID="${host_uid}" \
		--build-arg USER_GID="${host_gid}" \
		-t "$IMAGE_NAME" .; then
	info "Image built successfully"
else
	error "Failed to build image"
	fi
}

create_directories() {
	info "Creating required directories..."
	mkdir -p "$HOME/.config/opencode" \
		"$HOME/.sandboxes/opencode/.npm" \
		"$HOME/.sandboxes/opencode/.cache" \
		"$HOME/.sandboxes/opencode/.opencode" \
		"$HOME/.sandboxes/opencode/.local" \
		"$HOME/.sandboxes/opencode/.cargo"
	info "Directories created"
}

install_alias() {
	local file="$1"
	local alias_line="$2"
	local shell_name="$3"
	local updated=0

	if [ ! -f "$file" ]; then
		touch "$file"
	fi

	if grep -q "alias opencode=" "$file" 2>/dev/null; then
		sed -i '/# OpenCode sandbox alias/d' "$file"
		sed -i '/alias opencode=/d' "$file"
		updated=1
	fi

	{
		echo ""
		echo "# OpenCode sandbox alias (runtime: $CONTAINER_RUNTIME)"
		echo "$alias_line"
	} >> "$file"

	if [ "$updated" -eq 1 ]; then
		info "$shell_name: alias updated in $file"
	else
		info "$shell_name: alias added to $file"
	fi
}

install_bash_alias() {
	if command -v bash &>/dev/null; then
		local bashrc="$HOME/.bashrc"
		# shellcheck disable=SC2155
		local alias_line=$(generate_alias "$CONTAINER_RUNTIME" "bash")
		install_alias "$bashrc" "$alias_line" "bash"
	fi
}

install_zsh_alias() {
	if command -v zsh &>/dev/null; then
		local zshrc="$HOME/.zshrc"
		# shellcheck disable=SC2155
		local alias_line=$(generate_alias "$CONTAINER_RUNTIME" "zsh")
		install_alias "$zshrc" "$alias_line" "zsh"
	fi
}

install_fish_alias() {
	if command -v fish &>/dev/null; then
		local fish_config="$HOME/.config/fish/config.fish"
		mkdir -p "$(dirname "$fish_config")"
		# shellcheck disable=SC2155
		local alias_line=$(generate_alias "$CONTAINER_RUNTIME" "fish")
		install_alias "$fish_config" "$alias_line" "fish"
	fi
}

install_aliases() {
	info "Installing shell aliases for $CONTAINER_RUNTIME..."
	local installed=0

	if command -v bash &>/dev/null; then
		install_bash_alias
		((installed++)) || true
	fi

	if command -v zsh &>/dev/null; then
		install_zsh_alias
		((installed++)) || true
	fi

	if command -v fish &>/dev/null; then
		install_fish_alias
		((installed++)) || true
	fi

	if [ "$installed" -eq 0 ]; then
		warn "No supported shells found (bash, zsh, fish)"
	else
		info "Aliases installed for $installed shell(s)"
	fi
}

show_reload_message() {
	echo "Reload your shell or run:"
	command -v bash &>/dev/null && echo "  source ~/.bashrc"
	command -v zsh &>/dev/null && echo "  source ~/.zshrc"
	command -v fish &>/dev/null && echo "  source ~/.config/fish/config.fish"
}

main() {
	echo "=============================================="
	echo "  OpenCode Sandbox Installer"
	echo "=============================================="
	echo ""

	detect_container_runtime
	check_runtime_prerequisites
	build_image
	create_directories
	install_aliases

	echo ""
	echo "=============================================="
	info "Installation complete! (using $CONTAINER_RUNTIME)"
	echo ""
	show_reload_message
	echo ""
	echo " Then navigate to a project and run: opencode"
	echo "=============================================="
}

main "$@"
