# vim: set ts=4:
# Copyright 2022-present Jakub Jirutka <jakub@jirutka.cz>.
# Copyright 2025-present Michael Matta.
# SPDX-License-Identifier: MIT
#
# Configuration Wizard for zsh-shift-select
#
# This file contains all the interactive configuration wizard logic for the
# zsh-shift-select plugin. It is sourced on-demand when the user runs the
# 'zselect conf' command, keeping the main plugin lightweight.
#
# Responsibilities:
# - Interactive configuration menus
# - Clipboard backend configuration
# - Mouse replacement feature configuration
# - Keybinding customization
# - Configuration file management
# - Reset functionality
#
# Version: 0.2.5
# Homepage: <https://github.com/Michael-Matta1/zsh-shift-select>

# ==============================================================================
# Configuration Wizard Functions
# ==============================================================================

# Configuration file path
typeset -g _SHIFT_SELECT_CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/zsh-shift-select/config"

# Store the path to this plugin file for reset functionality
typeset -g _SHIFT_SELECT_PLUGIN_FILE="${(%):-%x}"

# Load user configuration if it exists
function shift-select::load-config() {
	if [[ -f "$_SHIFT_SELECT_CONFIG_FILE" ]]; then
		source "$_SHIFT_SELECT_CONFIG_FILE"
	fi
}

# Save configuration setting
function shift-select::save-config() {
	local key="$1"
	local value="$2"
	
	# Create config directory if it doesn't exist
	mkdir -p "${_SHIFT_SELECT_CONFIG_FILE:h}"
	
	# Create or update config file
	if [[ -f "$_SHIFT_SELECT_CONFIG_FILE" ]]; then
		# Update existing key or append if not found
		if grep -q "^${key}=" "$_SHIFT_SELECT_CONFIG_FILE" 2>/dev/null; then
			# Use a temporary file for sed compatibility across platforms
			local tmp_file="${_SHIFT_SELECT_CONFIG_FILE}.tmp"
			sed "s|^${key}=.*|${key}=\"${value}\"|" "$_SHIFT_SELECT_CONFIG_FILE" > "$tmp_file"
			mv "$tmp_file" "$_SHIFT_SELECT_CONFIG_FILE"
		else
			echo "${key}=\"${value}\"" >> "$_SHIFT_SELECT_CONFIG_FILE"
		fi
	else
		echo "${key}=\"${value}\"" > "$_SHIFT_SELECT_CONFIG_FILE"
	fi
}

# Save keybinding configuration
function shift-select::save-keybinding() {
	local action="$1"
	local keybinding="$2"
	
	shift-select::save-config "SHIFT_SELECT_KEY_${action}" "$keybinding"
}

# Load keybinding configurations
function shift-select::load-keybindings() {
	shift-select::load-config
	
	# Set current keybindings from config or use defaults
	SHIFT_SELECT_KEY_SELECT_ALL="${SHIFT_SELECT_KEY_SELECT_ALL:-^A}"
	SHIFT_SELECT_KEY_PASTE="${SHIFT_SELECT_KEY_PASTE:-^V}"
	SHIFT_SELECT_KEY_CUT="${SHIFT_SELECT_KEY_CUT:-^X}"
}

# Apply keybindings to the plugin
function shift-select::apply-keybindings() {
	# Unbind old keybindings first (if they exist)
	bindkey -M emacs -r '^A' 2>/dev/null
	bindkey -M emacs -r '^V' 2>/dev/null
	bindkey -M emacs -r '^X' 2>/dev/null
	bindkey -r '^X' 2>/dev/null
	
	# Apply new keybindings
	if [[ -n "$SHIFT_SELECT_KEY_SELECT_ALL" ]]; then
		bindkey -M emacs "$SHIFT_SELECT_KEY_SELECT_ALL" shift-select::select-all
	fi
	
	if [[ -n "$SHIFT_SELECT_KEY_PASTE" ]]; then
		bindkey -M emacs "$SHIFT_SELECT_KEY_PASTE" shift-select::paste-clipboard
		bindkey -M shift-select "$SHIFT_SELECT_KEY_PASTE" shift-select::paste-clipboard
	fi
	
	if [[ -n "$SHIFT_SELECT_KEY_CUT" ]]; then
		bindkey -M emacs "$SHIFT_SELECT_KEY_CUT" shift-select::cut-region
		bindkey -M shift-select "$SHIFT_SELECT_KEY_CUT" shift-select::cut-region
		bindkey "$SHIFT_SELECT_KEY_CUT" shift-select::cut-region
	fi
}

# Display the configuration menu
function shift-select::show-menu() {
	clear
	echo "╔════════════════════════════════════════════════════════════════╗"
	echo "║         ZSH Shift-Select Configuration Wizard                  ║"
	echo "╚════════════════════════════════════════════════════════════════╝"
	echo ""
	echo "Current Configuration:"
	echo "  Clipboard Integration: ${SHIFT_SELECT_CLIPBOARD_TYPE:-auto-detect}"
	echo "  Mouse Replacement:     ${SHIFT_SELECT_MOUSE_REPLACEMENT:-enabled}"
	echo ""
	echo "Available Options:"
	echo "  1) Configure Clipboard Integration"
	echo "  2) Configure Mouse Replacement"
	echo "  3) Configure Key Bindings"
	echo "  4) Reset to Default Configuration"
	echo "  5) View Current Configuration"
	echo "  6) Exit"
	echo ""
	echo -n "Select an option (1-6): "
}

# Configure clipboard integration
function shift-select::configure-clipboard() {
	clear
	echo "╔════════════════════════════════════════════════════════════════╗"
	echo "║            Clipboard Integration Configuration                 ║"
	echo "╚════════════════════════════════════════════════════════════════╝"
	echo ""
	echo "Select your preferred clipboard backend:"
	echo ""
	echo "  1) Wayland (wl-copy/wl-paste)"
	echo "  2) X11 (xclip)"
	echo "  3) Auto-detect (recommended)"
	echo "  4) Back to main menu"
	echo ""
	echo -n "Select an option (1-4): "
	
	read -r choice
	
	case "$choice" in
		1)
			shift-select::set-clipboard-backend "wayland"
			;;
		2)
			shift-select::set-clipboard-backend "x11"
			;;
		3)
			shift-select::set-clipboard-backend "auto"
			;;
		4)
			return
			;;
		*)
			echo ""
			echo "Invalid option. Press Enter to continue..."
			read -r
			shift-select::configure-clipboard
			;;
	esac
}

# Set clipboard backend and update plugin configuration
function shift-select::set-clipboard-backend() {
	local backend="$1"
	
	echo ""
	echo "Setting clipboard backend to: $backend"
	
	# Save to config file
	shift-select::save-config "SHIFT_SELECT_CLIPBOARD_TYPE" "$backend"
	
	# Apply the configuration immediately
	case "$backend" in
		wayland)
			if command -v wl-copy &>/dev/null; then
				_SHIFT_SELECT_CLIPBOARD_CMD="wl-copy"
				_SHIFT_SELECT_PRIMARY_CMD="wl-paste --primary"
				echo "✓ Wayland clipboard configured successfully"
			else
				echo "⚠ Warning: wl-copy not found. Please install wl-clipboard package."
			fi
			;;
		x11)
			if command -v xclip &>/dev/null; then
				_SHIFT_SELECT_CLIPBOARD_CMD="xclip -selection clipboard"
				_SHIFT_SELECT_PRIMARY_CMD="xclip -selection primary -o"
				echo "✓ X11 clipboard configured successfully"
			else
				echo "⚠ Warning: xclip not found. Please install xclip package."
			fi
			;;
		auto)
			shift-select::detect-clipboard
			echo "✓ Auto-detect mode enabled"
			;;
	esac
	
	# Update the global variable for display
	typeset -g SHIFT_SELECT_CLIPBOARD_TYPE="$backend"
	
	echo ""
	echo "Configuration saved. Press Enter to continue..."
	read -r
}

# Configure mouse replacement feature
function shift-select::configure-mouse-replacement() {
	clear
	echo "╔════════════════════════════════════════════════════════════════╗"
	echo "║            Mouse Replacement Configuration                     ║"
	echo "╚════════════════════════════════════════════════════════════════╝"
	echo ""
	echo "The Mouse Replacement feature allows you to:"
	echo "  • Select text with your mouse in the terminal"
	echo "  • Type to replace the selected text"
	echo "  • Delete selections with Backspace"
	echo "  • Paste over selections"
	echo ""
	echo "Current status: ${SHIFT_SELECT_MOUSE_REPLACEMENT:-enabled}"
	echo ""
	echo "Select an option:"
	echo ""
	echo "  1) Enable Mouse Replacement"
	echo "  2) Disable Mouse Replacement"
	echo "  3) Back to main menu"
	echo ""
	echo -n "Select an option (1-3): "
	
	read -r choice
	
	case "$choice" in
		1)
			shift-select::set-mouse-replacement "enabled"
			;;
		2)
			shift-select::set-mouse-replacement "disabled"
			;;
		3)
			return
			;;
		*)
			echo ""
			echo "Invalid option. Press Enter to continue..."
			read -r
			shift-select::configure-mouse-replacement
			;;
	esac
}

# Set mouse replacement mode and update plugin configuration
function shift-select::set-mouse-replacement() {
	local mode="$1"
	
	echo ""
	echo "Setting mouse replacement to: $mode"
	
	# Save to config file
	shift-select::save-config "SHIFT_SELECT_MOUSE_REPLACEMENT" "$mode"
	
	# Update the global variable for display
	typeset -g SHIFT_SELECT_MOUSE_REPLACEMENT="$mode"
	
	# Apply the configuration immediately by rebinding keys
	shift-select::apply-mouse-replacement-config
	
	if [[ "$mode" == "enabled" ]]; then
		echo "✓ Mouse replacement enabled"
		echo "  You can now select text with your mouse and type to replace it"
	else
		echo "✓ Mouse replacement disabled"
		echo "  Mouse selections will no longer be replaced when typing"
	fi
	
	echo ""
	echo "Configuration saved. Press Enter to continue..."
	read -r
}

# Configure Select All keybinding
function shift-select::configure-select-all() {
	clear
	echo "╔════════════════════════════════════════════════════════════════╗"
	echo "║              Configure Select All Keybinding                   ║"
	echo "╚════════════════════════════════════════════════════════════════╝"
	echo ""
	echo "Current keybinding: $SHIFT_SELECT_KEY_SELECT_ALL"
	echo ""
	echo "Select a keybinding for Select All:"
	echo ""
	echo "  1) Ctrl + A (^A)"
	echo "  2) Ctrl + Shift + A (^[[65;6u)"
	echo "  3) Advanced Option (Enter custom keybinding)"
	echo "  4) Back to Key Bindings menu"
	echo ""
	echo -n "Select an option (1-4): "
	
	read -r choice
	
	case "$choice" in
		1)
			shift-select::set-keybinding "SELECT_ALL" "^A"
			;;
		2)
			shift-select::set-keybinding "SELECT_ALL" "^[[65;6u"
			;;
		3)
			echo ""
			echo "Enter your custom keybinding (e.g., ^A, ^[[200~):"
			echo -n "> "
			read -r custom_key
			if [[ -n "$custom_key" ]]; then
				shift-select::set-keybinding "SELECT_ALL" "$custom_key"
			else
				echo ""
				echo "Invalid keybinding. Press Enter to continue..."
				read -r
				shift-select::configure-select-all
			fi
			;;
		4)
			return
			;;
		*)
			echo ""
			echo "Invalid option. Press Enter to continue..."
			read -r
			shift-select::configure-select-all
			;;
	esac
}

# Configure Paste keybinding
function shift-select::configure-paste() {
	clear
	echo "╔════════════════════════════════════════════════════════════════╗"
	echo "║                Configure Paste Keybinding                      ║"
	echo "╚════════════════════════════════════════════════════════════════╝"
	echo ""
	echo "Current keybinding: $SHIFT_SELECT_KEY_PASTE"
	echo ""
	echo "Select a keybinding for Paste:"
	echo ""
	echo "  1) Ctrl + V (^V)"
	echo "  2) Ctrl + Shift + V (^[[86;6u)"
	echo "  3) Advanced Option (Enter custom keybinding)"
	echo "  4) Back to Key Bindings menu"
	echo ""
	echo -n "Select an option (1-4): "
	
	read -r choice
	
	case "$choice" in
		1)
			shift-select::set-keybinding "PASTE" "^V"
			;;
		2)
			shift-select::set-keybinding "PASTE" "^[[86;6u"
			;;
		3)
			echo ""
			echo "Enter your custom keybinding (e.g., ^V, ^[[200~):"
			echo -n "> "
			read -r custom_key
			if [[ -n "$custom_key" ]]; then
				shift-select::set-keybinding "PASTE" "$custom_key"
			else
				echo ""
				echo "Invalid keybinding. Press Enter to continue..."
				read -r
				shift-select::configure-paste
			fi
			;;
		4)
			return
			;;
		*)
			echo ""
			echo "Invalid option. Press Enter to continue..."
			read -r
			shift-select::configure-paste
			;;
	esac
}

# Configure Cut keybinding
function shift-select::configure-cut() {
	clear
	echo "╔════════════════════════════════════════════════════════════════╗"
	echo "║                 Configure Cut Keybinding                       ║"
	echo "╚════════════════════════════════════════════════════════════════╝"
	echo ""
	echo "Current keybinding: $SHIFT_SELECT_KEY_CUT"
	echo ""
	echo "Select a keybinding for Cut:"
	echo ""
	echo "  1) Ctrl + X (^X)"
	echo "  2) Ctrl + Shift + X (^[[88;6u)"
	echo "  3) Advanced Option (Enter custom keybinding)"
	echo "  4) Back to Key Bindings menu"
	echo ""
	echo -n "Select an option (1-4): "
	
	read -r choice
	
	case "$choice" in
		1)
			shift-select::set-keybinding "CUT" "^X"
			;;
		2)
			shift-select::set-keybinding "CUT" "^[[88;6u"
			;;
		3)
			echo ""
			echo "Enter your custom keybinding (e.g., ^X, ^[[200~):"
			echo -n "> "
			read -r custom_key
			if [[ -n "$custom_key" ]]; then
				shift-select::set-keybinding "CUT" "$custom_key"
			else
				echo ""
				echo "Invalid keybinding. Press Enter to continue..."
				read -r
				shift-select::configure-cut
			fi
			;;
		4)
			return
			;;
		*)
			echo ""
			echo "Invalid option. Press Enter to continue..."
			read -r
			shift-select::configure-cut
			;;
	esac
}

# Set keybinding and apply it
function shift-select::set-keybinding() {
	local action="$1"
	local keybinding="$2"
	
	echo ""
	echo "Setting $action keybinding to: $keybinding"
	
	# Save to config file
	shift-select::save-keybinding "$action" "$keybinding"
	
	# Update the global variable
	case "$action" in
		SELECT_ALL)
			typeset -g SHIFT_SELECT_KEY_SELECT_ALL="$keybinding"
			;;
		PASTE)
			typeset -g SHIFT_SELECT_KEY_PASTE="$keybinding"
			;;
		CUT)
			typeset -g SHIFT_SELECT_KEY_CUT="$keybinding"
			;;
	esac
	
	# Apply the keybindings immediately
	shift-select::apply-keybindings
	
	echo "✓ Keybinding configured successfully"
	echo ""
	echo "Configuration saved. Press Enter to continue..."
	read -r
}

# Reset keybindings to defaults
function shift-select::reset-keybindings() {
	clear
	echo "╔════════════════════════════════════════════════════════════════╗"
	echo "║             Reset Keybindings to Defaults                      ║"
	echo "╚════════════════════════════════════════════════════════════════╝"
	echo ""
	echo "This will restore all keybindings to their default values:"
	echo ""
	echo "  • Select All: Ctrl + A (^A)"
	echo "  • Paste:      Ctrl + V (^V)"
	echo "  • Cut:        Ctrl + X (^X)"
	echo ""
	echo -n "Are you sure? (y/N): "
	
	read -r confirm
	
	if [[ "$confirm" =~ ^[Yy]$ ]]; then
		echo ""
		
		# Reset to defaults
		typeset -g SHIFT_SELECT_KEY_SELECT_ALL="^A"
		typeset -g SHIFT_SELECT_KEY_PASTE="^V"
		typeset -g SHIFT_SELECT_KEY_CUT="^X"
		
		# Save to config
		shift-select::save-keybinding "SELECT_ALL" "^A"
		shift-select::save-keybinding "PASTE" "^V"
		shift-select::save-keybinding "CUT" "^X"
		
		# Apply keybindings
		shift-select::apply-keybindings
		
		echo "✓ All keybindings have been reset to defaults"
		echo ""
		echo "Press Enter to continue..."
		read -r
	else
		echo ""
		echo "Reset cancelled."
		echo "Press Enter to continue..."
		read -r
	fi
}

# Configure keybindings
function shift-select::configure-keybindings() {
	while true; do
		clear
		echo "╔════════════════════════════════════════════════════════════════╗"
		echo "║              Key Bindings Configuration                        ║"
		echo "╚════════════════════════════════════════════════════════════════╝"
		echo ""
		echo "Current Key Bindings:"
		echo "  Select All: $SHIFT_SELECT_KEY_SELECT_ALL"
		echo "  Paste:      $SHIFT_SELECT_KEY_PASTE"
		echo "  Cut:        $SHIFT_SELECT_KEY_CUT"
		echo ""
		echo "Select an action to configure:"
		echo ""
		echo "  1) Select All"
		echo "  2) Paste"
		echo "  3) Cut"
		echo "  4) Reset to Default Keybindings"
		echo "  5) Back to main menu"
		echo ""
		echo -n "Select an option (1-5): "
		
		read -r choice
		
		case "$choice" in
			1)
				shift-select::configure-select-all
				;;
			2)
				shift-select::configure-paste
				;;
			3)
				shift-select::configure-cut
				;;
			4)
				shift-select::reset-keybindings
				;;
			5)
				return
				;;
			*)
				echo ""
				echo "Invalid option. Press Enter to continue..."
				read -r
				;;
		esac
	done
}

# Reset configuration to defaults
function shift-select::reset-config() {
	clear
	echo "╔════════════════════════════════════════════════════════════════╗"
	echo "║              Reset Configuration to Defaults                   ║"
	echo "╚════════════════════════════════════════════════════════════════╝"
	echo ""
	echo "This will:"
	echo "  • Delete your custom configuration file"
	echo "  • Reset clipboard integration to auto-detect mode"
	echo "  • Reset mouse replacement to enabled"
	echo "  • Restore all default plugin behavior"
	echo ""
	echo -n "Are you sure? (y/N): "
	
	read -r confirm
	
	if [[ "$confirm" =~ ^[Yy]$ ]]; then
		# Remove config file
		if [[ -f "$_SHIFT_SELECT_CONFIG_FILE" ]]; then
			rm "$_SHIFT_SELECT_CONFIG_FILE"
			echo ""
			echo "✓ Configuration file deleted"
		fi
		
		# Reset to auto-detect
		shift-select::detect-clipboard
		unset SHIFT_SELECT_CLIPBOARD_TYPE
		
		# Reset mouse replacement to enabled (default)
		typeset -g SHIFT_SELECT_MOUSE_REPLACEMENT="enabled"
		shift-select::apply-mouse-replacement-config
		
		echo "✓ Configuration reset to defaults"
		echo ""
		echo "Press Enter to continue..."
		read -r
	else
		echo ""
		echo "Reset cancelled."
		echo "Press Enter to continue..."
		read -r
	fi
}

# View current configuration
function shift-select::view-config() {
	clear
	echo "╔════════════════════════════════════════════════════════════════╗"
	echo "║                Current Configuration                           ║"
	echo "╚════════════════════════════════════════════════════════════════╝"
	echo ""
	
	if [[ -f "$_SHIFT_SELECT_CONFIG_FILE" ]]; then
		echo "Configuration file: $_SHIFT_SELECT_CONFIG_FILE"
		echo ""
		echo "Settings:"
		echo "─────────────────────────────────────────────────────────────"
		cat "$_SHIFT_SELECT_CONFIG_FILE"
		echo "─────────────────────────────────────────────────────────────"
	else
		echo "No custom configuration file found."
		echo "Using default settings (auto-detect mode)."
	fi
	
	echo ""
	echo "Active Settings:"
	echo "  Clipboard Type:     ${SHIFT_SELECT_CLIPBOARD_TYPE:-auto-detect}"
	echo "  Clipboard Cmd:      ${_SHIFT_SELECT_CLIPBOARD_CMD:-none}"
	echo "  Primary Cmd:        ${_SHIFT_SELECT_PRIMARY_CMD:-none}"
	echo "  Mouse Replacement:  ${SHIFT_SELECT_MOUSE_REPLACEMENT:-enabled}"
	echo ""
	echo "Key Bindings:"
	echo "  Select All:         ${SHIFT_SELECT_KEY_SELECT_ALL:-^A}"
	echo "  Paste:              ${SHIFT_SELECT_KEY_PASTE:-^V}"
	echo "  Cut:                ${SHIFT_SELECT_KEY_CUT:-^X}"
	echo ""
	echo "Plugin file: $_SHIFT_SELECT_PLUGIN_FILE"
	echo ""
	echo "Press Enter to continue..."
	read -r
}

# Main configuration wizard function
function shift-select::config-wizard() {
	# Load current config
	shift-select::load-config
	
	# Set display variables
	typeset -g SHIFT_SELECT_CLIPBOARD_TYPE="${SHIFT_SELECT_CLIPBOARD_TYPE:-auto-detect}"
	typeset -g SHIFT_SELECT_MOUSE_REPLACEMENT="${SHIFT_SELECT_MOUSE_REPLACEMENT:-enabled}"
	
	# Load keybinding configurations
	shift-select::load-keybindings
	
	while true; do
		shift-select::show-menu
		read -r choice
		
		case "$choice" in
			1)
				shift-select::configure-clipboard
				;;
			2)
				shift-select::configure-mouse-replacement
				;;
			3)
				shift-select::configure-keybindings
				;;
			4)
				shift-select::reset-config
				;;
			5)
				shift-select::view-config
				;;
			6)
				echo ""
				echo "Exiting configuration wizard..."
				break
				;;
			*)
				echo ""
				echo "Invalid option. Press Enter to continue..."
				read -r
				;;
		esac
	done
}
