# vim: set ts=4:
# Copyright 2022-present Jakub Jirutka <jakub@jirutka.cz>.
# Copyright 2025-present Michael Matta.
# SPDX-License-Identifier: MIT
#
# Emacs shift-select mode for Zsh - select text in the command line using Shift
# as in many text editors, browsers and other GUI programs.
#
# This is the main plugin file containing only the core functionality:
# - Clipboard integration (Wayland/X11)
# - Shift-select text selection mode
# - Mouse selection support
# - Cut/Copy/Paste operations
# - Keybinding management
#
# The configuration wizard is kept separate in zselect-wizard.zsh and is
# loaded on-demand when the user runs 'zselect conf'.
#
# Version: 0.2.5
# Homepage: <https://github.com/Michael-Matta1/zsh-shift-select>
# Original: <https://github.com/jirutka/zsh-shift-select>

# Detect clipboard tool based on display server
typeset -g _SHIFT_SELECT_CLIPBOARD_CMD
typeset -g _SHIFT_SELECT_PRIMARY_CMD
typeset -g _SHIFT_SELECT_LAST_PRIMARY=""
typeset -g _SHIFT_SELECT_ACTIVE_SELECTION=""
typeset -g _SHIFT_SELECT_LAST_BUFFER=""

# Configuration file path
typeset -g _SHIFT_SELECT_CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/zsh-shift-select/config"

# Store the directory where this plugin is located (for lazy-loading the wizard)
typeset -g _SHIFT_SELECT_PLUGIN_DIR="${0:A:h}"

# Load user configuration if it exists
function shift-select::load-config() {
	if [[ -f "$_SHIFT_SELECT_CONFIG_FILE" ]]; then
		source "$_SHIFT_SELECT_CONFIG_FILE"
	fi
}

function shift-select::detect-clipboard() {
	if command -v wl-copy &>/dev/null && [[ -n "$WAYLAND_DISPLAY" ]]; then
		# Wayland
		_SHIFT_SELECT_CLIPBOARD_CMD="wl-copy"
		_SHIFT_SELECT_PRIMARY_CMD="wl-paste --primary"
	elif command -v xclip &>/dev/null && [[ -n "$DISPLAY" ]]; then
		# X11
		_SHIFT_SELECT_CLIPBOARD_CMD="xclip -selection clipboard"
		_SHIFT_SELECT_PRIMARY_CMD="xclip -selection primary -o"
	else
		# Fallback: no clipboard support
		_SHIFT_SELECT_CLIPBOARD_CMD=""
		_SHIFT_SELECT_PRIMARY_CMD=""
	fi
}

# Get text from primary selection (mouse selection)
function shift-select::get-primary() {
	if [[ -z "$_SHIFT_SELECT_PRIMARY_CMD" ]]; then
		return 1
	fi
	local result
	if [[ "$_SHIFT_SELECT_PRIMARY_CMD" == wl-paste* ]]; then
		result=$(wl-paste --primary 2>/dev/null)
	else
		result=$(xclip -selection primary -o 2>/dev/null)
	fi
	if [[ -n "$result" ]]; then
		echo "$result"
		return 0
	fi
	return 1
}

# Get text from clipboard
function shift-select::get-clipboard() {
	if [[ -z "$_SHIFT_SELECT_CLIPBOARD_CMD" ]]; then
		return 1
	fi
	local result
	if [[ "$_SHIFT_SELECT_CLIPBOARD_CMD" == wl-copy* ]]; then
		result=$(wl-paste 2>/dev/null)
	else
		result=$(xclip -selection clipboard -o 2>/dev/null)
	fi
	if [[ -n "$result" ]]; then
		echo "$result"
		return 0
	fi
	return 1
}

# Copy text to clipboard
function shift-select::copy-to-clipboard() {
	local text="$1"
	if [[ -z "$_SHIFT_SELECT_CLIPBOARD_CMD" ]]; then
		return 1
	fi
	
	if [[ "$_SHIFT_SELECT_CLIPBOARD_CMD" == wl-copy* ]]; then
		print -rn "$text" | wl-copy
	else
		print -rn "$text" | xclip -selection clipboard -in
	fi
}

# Initialize clipboard detection
shift-select::detect-clipboard

# Move cursor to the end of the buffer.
# This is an alternative to builtin end-of-buffer-or-history.
function end-of-buffer() {
	CURSOR=${#BUFFER}
	zle end-of-line -w  # trigger syntax highlighting redraw
}
zle -N end-of-buffer

# Move cursor to the beginning of the buffer.
# This is an alternative to builtin beginning-of-buffer-or-history.
function beginning-of-buffer() {
	CURSOR=0
	zle beginning-of-line -w  # trigger syntax highlighting redraw
}
zle -N beginning-of-buffer

# Select all text in the buffer (Ctrl+A)
function shift-select::select-all() {
	MARK=0
	CURSOR=${#BUFFER}
	REGION_ACTIVE=1
	zle -K shift-select
}
zle -N shift-select::select-all

# Kill the selected region and switch back to the main keymap.
function shift-select::kill-region() {
	zle kill-region -w
	zle -K main
}
zle -N shift-select::kill-region

# Delete mouse selection or perform normal backspace
function shift-select::delete-mouse-or-backspace() {
	local mouse_sel=$(shift-select::get-primary)
	
	# Check if PRIMARY has changed (new selection was made)
	if [[ -n "$mouse_sel" && "$mouse_sel" != "$_SHIFT_SELECT_LAST_PRIMARY" ]]; then
		# This is a NEW selection - mark it as active
		_SHIFT_SELECT_ACTIVE_SELECTION="$mouse_sel"
		_SHIFT_SELECT_LAST_PRIMARY="$mouse_sel"
	fi
	
	# Only delete if we have an ACTIVE mouse selection that exists in the buffer
	if [[ -n "$_SHIFT_SELECT_ACTIVE_SELECTION" && "$BUFFER" == *"$_SHIFT_SELECT_ACTIVE_SELECTION"* ]]; then
		# Find and delete the mouse-selected text from buffer
		local before="${BUFFER%%$_SHIFT_SELECT_ACTIVE_SELECTION*}"
		local after="${BUFFER#*$_SHIFT_SELECT_ACTIVE_SELECTION}"
		BUFFER="${before}${after}"
		CURSOR=${#before}
		# Clear the active selection after deleting
		_SHIFT_SELECT_ACTIVE_SELECTION=""
		_SHIFT_SELECT_LAST_BUFFER="$BUFFER"
		return
	fi
	
	# No active mouse selection - perform normal backspace
	zle backward-delete-char -w
}
zle -N shift-select::delete-mouse-or-backspace

# Deactivate the selection region, switch back to the main keymap and process
# the typed keys again.
function shift-select::deselect-and-input() {
	zle deactivate-region -w
	# Switch back to the main keymap (emacs).
	zle -K main
	# Push the typed keys back to the input stack, i.e. process them again,
	# but now with the main keymap.
	zle -U "$KEYS"
}
zle -N shift-select::deselect-and-input

# Replace selection with typed character (like text editors)
function shift-select::replace-selection() {
	if (( REGION_ACTIVE )); then
		# Delete the keyboard-selected text
		zle kill-region -w
		# Switch back to main keymap and insert character
		zle -K main
		zle -U "$KEYS"
		return
	fi
	
	# No selection - just insert character normally
	zle self-insert -w
}
zle -N shift-select::replace-selection

# Check for mouse selection and handle character input
# This detects fresh mouse selections and replaces them when typing
function shift-select::handle-char() {
	local mouse_sel=$(shift-select::get-primary)
	
	# Check if PRIMARY has changed (new selection was made)
	if [[ -n "$mouse_sel" && "$mouse_sel" != "$_SHIFT_SELECT_LAST_PRIMARY" ]]; then
		# This is a NEW selection - mark it as active ONLY if it exists in current buffer
		if [[ "$BUFFER" == *"$mouse_sel"* ]]; then
			_SHIFT_SELECT_ACTIVE_SELECTION="$mouse_sel"
		fi
		_SHIFT_SELECT_LAST_PRIMARY="$mouse_sel"
	fi
	
	# Check if we have an ACTIVE mouse selection that exists in buffer
	if [[ -n "$_SHIFT_SELECT_ACTIVE_SELECTION" && "$BUFFER" == *"$_SHIFT_SELECT_ACTIVE_SELECTION"* ]]; then
		# Find and delete the mouse-selected text from buffer
		local before="${BUFFER%%$_SHIFT_SELECT_ACTIVE_SELECTION*}"
		local after="${BUFFER#*$_SHIFT_SELECT_ACTIVE_SELECTION}"
		BUFFER="${before}${after}"
		CURSOR=${#before}
		# Clear the active selection after replacing it ONCE
		_SHIFT_SELECT_ACTIVE_SELECTION=""
	fi
	
	# Insert the typed character
	zle self-insert -w
	
	# Update buffer tracking after character insertion
	_SHIFT_SELECT_LAST_BUFFER="$BUFFER"
}
zle -N shift-select::handle-char

# Monitor PRIMARY selection changes to track active selections
function shift-select::update-active-selection() {
	local current_primary=$(shift-select::get-primary)
	
	# Update last known PRIMARY value for reference
	if [[ -n "$current_primary" ]]; then
		_SHIFT_SELECT_LAST_PRIMARY="$current_primary"
	fi
}

# Hook that runs on every ZLE widget call
function shift-select::zle-line-pre-redraw() {
	shift-select::update-active-selection
}

# Register the hook
autoload -Uz add-zle-hook-widget
add-zle-hook-widget line-pre-redraw shift-select::zle-line-pre-redraw

# Copy the selected region to clipboard and deactivate selection.
function shift-select::copy-region() {
	if (( REGION_ACTIVE )); then
		# If zsh has a selection, copy it
		local start=$(( MARK < CURSOR ? MARK : CURSOR ))
		local length=$(( MARK > CURSOR ? MARK - CURSOR : CURSOR - MARK ))
		local selected="${BUFFER:$start:$length}"
		shift-select::copy-to-clipboard "$selected"
		_SHIFT_SELECT_LAST_PRIMARY="$selected"
		_SHIFT_SELECT_ACTIVE_SELECTION=""
		zle deactivate-region -w
		zle -K main
	else
		# No zsh selection - copy from PRIMARY to clipboard
		local primary_sel=$(shift-select::get-primary)
		if [[ -n "$primary_sel" ]]; then
			shift-select::copy-to-clipboard "$primary_sel"
			_SHIFT_SELECT_LAST_PRIMARY="$primary_sel"
			# After manual copy, clear active selection so it won't be auto-replaced
			_SHIFT_SELECT_ACTIVE_SELECTION=""
		fi
	fi
}
zle -N shift-select::copy-region

# Cut the selected region to clipboard and delete it.
function shift-select::cut-region() {
	if (( REGION_ACTIVE )); then
		# If zsh has a selection, cut it (copy and delete)
		local start=$(( MARK < CURSOR ? MARK : CURSOR ))
		local length=$(( MARK > CURSOR ? MARK - CURSOR : CURSOR - MARK ))
		local selected="${BUFFER:$start:$length}"
		shift-select::copy-to-clipboard "$selected"
		_SHIFT_SELECT_LAST_PRIMARY="$selected"
		_SHIFT_SELECT_ACTIVE_SELECTION=""
		# Delete the selected text
		zle kill-region -w
		zle -K main
	else
		# No zsh selection - try to cut mouse selection from buffer
		local mouse_sel=$(shift-select::get-primary)
		
		# Check if PRIMARY has changed (new selection was made)
		if [[ -n "$mouse_sel" && "$mouse_sel" != "$_SHIFT_SELECT_LAST_PRIMARY" ]]; then
			_SHIFT_SELECT_ACTIVE_SELECTION="$mouse_sel"
			_SHIFT_SELECT_LAST_PRIMARY="$mouse_sel"
		fi
		
		if [[ -n "$_SHIFT_SELECT_ACTIVE_SELECTION" && "$BUFFER" == *"$_SHIFT_SELECT_ACTIVE_SELECTION"* ]]; then
			# Copy to clipboard
			shift-select::copy-to-clipboard "$_SHIFT_SELECT_ACTIVE_SELECTION"
			
			# Find and delete it from the buffer
			local before="${BUFFER%%$_SHIFT_SELECT_ACTIVE_SELECTION*}"
			local after="${BUFFER#*$_SHIFT_SELECT_ACTIVE_SELECTION}"
			BUFFER="${before}${after}"
			CURSOR=${#before}
			
			# Clear active selection
			_SHIFT_SELECT_ACTIVE_SELECTION=""
		fi
	fi
}
zle -N shift-select::cut-region

# Custom bracketed paste that replaces selected text
function shift-select::bracketed-paste-replace() {
	# Check if there's an active keyboard selection
	if (( REGION_ACTIVE )); then
		# Delete the selected region first
		zle kill-region -w
		REGION_ACTIVE=0
		zle -K main
	else
		# Check for fresh mouse selection
		local mouse_sel=$(shift-select::get-primary)
		
		# Check if PRIMARY has changed (new selection was made)
		if [[ -n "$mouse_sel" && "$mouse_sel" != "$_SHIFT_SELECT_LAST_PRIMARY" ]]; then
			# This is a NEW selection - mark it as active ONLY if it exists in current buffer
			if [[ "$BUFFER" == *"$mouse_sel"* ]]; then
				_SHIFT_SELECT_ACTIVE_SELECTION="$mouse_sel"
			fi
			_SHIFT_SELECT_LAST_PRIMARY="$mouse_sel"
		fi
		
		# Replace active mouse selection if it exists in buffer
		if [[ -n "$_SHIFT_SELECT_ACTIVE_SELECTION" && "$BUFFER" == *"$_SHIFT_SELECT_ACTIVE_SELECTION"* ]]; then
			local before="${BUFFER%%$_SHIFT_SELECT_ACTIVE_SELECTION*}"
			local after="${BUFFER#*$_SHIFT_SELECT_ACTIVE_SELECTION}"
			BUFFER="${before}${after}"
			CURSOR=${#before}
			# Clear the active selection after replacing
			_SHIFT_SELECT_ACTIVE_SELECTION=""
		fi
	fi
	
	# Now perform the default bracketed paste at the current cursor position
	zle .bracketed-paste
	
	# Update buffer tracking and clear active selection after paste
	_SHIFT_SELECT_LAST_BUFFER="$BUFFER"
	# Clear active selection to prevent replacement after pasting
	_SHIFT_SELECT_ACTIVE_SELECTION=""
}
zle -N shift-select::bracketed-paste-replace

# Manual paste function for Ctrl+V
function shift-select::paste-clipboard() {
	# Get clipboard content first
	local clipboard_content=$(shift-select::get-clipboard)
	
	# Check if there's an active keyboard selection
	if (( REGION_ACTIVE )); then
		# Delete the selected region first
		zle kill-region -w
		REGION_ACTIVE=0
		zle -K main
	fi
	
	# NEVER replace mouse selections on paste - they may have been visually deselected
	
	# Insert clipboard content
	if [[ -n "$clipboard_content" ]]; then
		LBUFFER="${LBUFFER}${clipboard_content}"
	fi
	
	# Update buffer tracking and clear active selection after paste
	_SHIFT_SELECT_LAST_BUFFER="$BUFFER"
	# Clear active selection to prevent replacement after pasting
	_SHIFT_SELECT_ACTIVE_SELECTION=""
}
zle -N shift-select::paste-clipboard


# If the selection region is not active, set the mark at the cursor position,
# switch to the shift-select keymap, and call $WIDGET without 'shift-select::'
# prefix. This function must be used only for shift-select::<widget> widgets.
function shift-select::select-and-invoke() {
	if (( !REGION_ACTIVE )); then
		zle set-mark-command -w
		zle -K shift-select
	fi
	zle ${WIDGET#shift-select::} -w
}

function {
	emulate -L zsh

	# Create a new keymap for the shift-selection mode.
	bindkey -N shift-select

	# Bind all possible key sequences to deselect-and-input, i.e. it will be used
	# as a fallback for "unbound" key sequences.
	bindkey -M shift-select -R '^@'-'^?' shift-select::deselect-and-input
	
	# Override printable characters (space to ~) to replace selection instead
	bindkey -M shift-select -R ' '-'~' shift-select::replace-selection
	
	# Note: Mouse selection handlers (handle-char, delete-mouse-or-backspace, bracketed-paste-replace)
	# are bound conditionally by shift-select::apply-mouse-replacement-config() during initialization

	local kcap seq seq_mac widget

	# Bind Shift keys in the emacs and shift-select keymaps.
	for	kcap   seq          seq_mac    widget (             # key name
		kLFT   '^[[1;2D'    x          backward-char        # Shift + LeftArrow
		kRIT   '^[[1;2C'    x          forward-char         # Shift + RightArrow
		kri    '^[[1;2A'    x          up-line              # Shift + UpArrow
		kind   '^[[1;2B'    x          down-line            # Shift + DownArrow
		kHOM   '^[[1;2H'    x          beginning-of-line    # Shift + Home
		x      '^[[97;6u'   x          beginning-of-line    # Shift + Ctrl + A
		kEND   '^[[1;2F'    x          end-of-line          # Shift + End
		x      '^[[101;6u'  x          end-of-line          # Shift + Ctrl + E
		x      '^[[1;6D'    '^[[1;4D'  backward-word        # Shift + Ctrl/Option + LeftArrow
		x      '^[[1;6C'    '^[[1;4C'  forward-word         # Shift + Ctrl/Option + RightArrow
		x      '^[[1;6H'    '^[[1;4H'  beginning-of-buffer  # Shift + Ctrl/Option + Home
		x      '^[[1;6F'    '^[[1;4F'  end-of-buffer        # Shift + Ctrl/Option + End
	); do
		# Use alternative sequence (Option instead of Ctrl) on macOS, if defined.
		[[ "$OSTYPE" = darwin* && "$seq_mac" != x ]] && seq=$seq_mac

		zle -N shift-select::$widget shift-select::select-and-invoke
		bindkey -M emacs ${terminfo[$kcap]:-$seq} shift-select::$widget
		bindkey -M shift-select ${terminfo[$kcap]:-$seq} shift-select::$widget
	done

	# Bind keys in the shift-select keymap.
	for	kcap   seq        widget (                          # key name
		kdch1  '^[[3~'    shift-select::kill-region         # Delete
		bs     '^?'       shift-select::kill-region         # Backspace
		x      '^[[67;6u' shift-select::copy-region         # Ctrl+Shift+C
		x      '^X'       shift-select::cut-region          # Ctrl+X
		x      '^V'       shift-select::paste-clipboard     # Ctrl+V
	); do
		bindkey -M shift-select ${terminfo[$kcap]:-$seq} $widget
	done
	
	# Note: Backspace in emacs keymap is bound conditionally by shift-select::apply-mouse-replacement-config()
	# (either to shift-select::delete-mouse-or-backspace or backward-delete-char)
	
	# Bind Ctrl+A to select all in emacs keymap
	bindkey -M emacs '^A' shift-select::select-all
	
	# Bind Ctrl+V for paste in emacs keymap
	bindkey -M emacs '^V' shift-select::paste-clipboard
	
	# Also bind Ctrl+Shift+C and Ctrl+X in emacs keymap for mouse selections
	bindkey -M emacs '^[[67;6u' shift-select::copy-region
	bindkey -M emacs '^X' shift-select::cut-region
	
	# Ensure Ctrl+X is bound in main keymap as well
	bindkey '^X' shift-select::cut-region
	
	# Note: Bracketed paste in emacs keymap is bound conditionally by shift-select::apply-mouse-replacement-config()
	# (either to shift-select::bracketed-paste-replace or bracketed-paste)
	
	# Bracketed paste in shift-select keymap always uses replace behavior
	bindkey -M shift-select '^[[200~' shift-select::bracketed-paste-replace
}

# ==============================================================================
# Mouse Replacement Configuration
# ==============================================================================

# Apply mouse replacement configuration based on user preference
# This function allows enabling/disabling the mouse selection replacement feature
function shift-select::apply-mouse-replacement-config() {
	# Get current setting (default to enabled if not set)
	local mode="${SHIFT_SELECT_MOUSE_REPLACEMENT:-enabled}"
	
	if [[ "$mode" == "enabled" ]]; then
		# Bind mouse-related handlers in emacs keymap
		bindkey -M emacs -R ' '-'~' shift-select::handle-char
		bindkey -M emacs '^?' shift-select::delete-mouse-or-backspace
		bindkey -M emacs '^[[200~' shift-select::bracketed-paste-replace
	else
		# Unbind mouse handlers - restore default behavior
		# Use self-insert for printable characters (space to ~)
		bindkey -M emacs -R ' '-'~' self-insert
		# Restore default backspace behavior
		bindkey -M emacs '^?' backward-delete-char
		# Restore default bracketed paste
		bindkey -M emacs '^[[200~' bracketed-paste
	fi
}

# ==============================================================================
# Configuration Wizard Command
# ==============================================================================

# The zselect command provides access to the configuration wizard.
# The wizard is loaded on-demand from zselect-wizard.zsh when needed.
function zselect() {
	case "$1" in
		conf|config)
			# Lazy-load the configuration wizard
			local wizard_file="$_SHIFT_SELECT_PLUGIN_DIR/zselect-wizard.zsh"
			if [[ -f "$wizard_file" ]]; then
				source "$wizard_file"
				shift-select::config-wizard
			else
				echo "Error: Configuration wizard file not found at: $wizard_file"
				echo "Please ensure zselect-wizard.zsh is in the same directory as the plugin."
				return 1
			fi
			;;
		*)
			echo "zselect - zsh-shift-select plugin command"
			echo ""
			echo "Usage: zselect <subcommand>"
			echo ""
			echo "Subcommands:"
			echo "  conf, config    Open the interactive configuration wizard"
			echo ""
			;;
	esac
}

# ==============================================================================
# Plugin Initialization
# ==============================================================================

# Initialize clipboard detection
shift-select::detect-clipboard

# Load user configuration if it exists
shift-select::load-config

# Apply user's clipboard preference if set
if [[ -n "$SHIFT_SELECT_CLIPBOARD_TYPE" ]]; then
	case "$SHIFT_SELECT_CLIPBOARD_TYPE" in
		wayland)
			_SHIFT_SELECT_CLIPBOARD_CMD="wl-copy"
			_SHIFT_SELECT_PRIMARY_CMD="wl-paste --primary"
			if ! command -v wl-copy &>/dev/null; then
				echo "Warning: wl-copy not found. Falling back to auto-detect."
				shift-select::detect-clipboard
			fi
			;;
		x11)
			_SHIFT_SELECT_CLIPBOARD_CMD="xclip -selection clipboard"
			_SHIFT_SELECT_PRIMARY_CMD="xclip -selection primary -o"
			if ! command -v xclip &>/dev/null; then
				echo "Warning: xclip not found. Falling back to auto-detect."
				shift-select::detect-clipboard
			fi
			;;
		# auto is already handled by the initial detect-clipboard call
	esac
fi

# Apply mouse replacement configuration (enabled by default)
shift-select::apply-mouse-replacement-config

# Register the ZLE hook for tracking active selections
autoload -Uz add-zle-hook-widget
add-zle-hook-widget line-pre-redraw shift-select::zle-line-pre-redraw