[[ -z $ZALGZ_BASE_DIR ]] && {
    echo "zalgz error: Please set the ZALGZ_BASE_DIR environment variable"
    return 1
}

# Base directories for Zalgz
ZALGZ_PLUGIN_DIR="$ZALGZ_BASE_DIR/plugins"
ZALGZ_PLUGIN_DB="$ZALGZ_BASE_DIR/plugins.txt"
# Define a debugging level; set to 0 to disable debugging
ZALGZ_DEBUG_LEVEL=${ZALGZ_DEBUG_LEVEL:-1}

# Debug log function
_zalgz_debug() {
    local level="$1"
    shift
    # Check if debugging is enabled (ZALGZ_DEBUG_LEVEL > 0)
    if [[ $ZALGZ_DEBUG_LEVEL -ge $level ]]; then
        # Print the message with a "DEBUG:" prefix
        echo "DEBUG: $@"
    fi
}

# Check if an element exists in an array
_zalgs_in_array() {
    local needle="$1"
    shift
    local item
    for item in "$@"; do
        [[ "$item" == "$needle" ]] && return 0
    done
    return 1
}

_zalgz_load_plugin() {
    plugin_dir="$1"
    plugin_name="${1:t}"
    # source the first plugin file we find (iterating by specificity)
    for file in "$plugin_dir/${plugin_name}.plugin.zsh" \
                    "$plugin_dir/${plugin_name}.zsh-theme" \
                    "$plugin_dir/${plugin_name}.zsh" \
                    "$plugin_dir/plugin.zsh"; do
        _zalgz_debug 2 "Checking for init file $file"
        if [[ -f "$file" ]]; then
            source "$file"
            _zalgz_debug 2 "Found and loaded $file"
            _zalgz_debug 1 "Loaded plugin $plugin_name"
            return
        fi
    done
}

_zalgz_git_clone_and_checkout() {
    local plugin="$1"
    local git_ref="$2"
    local plugin_dir="$3"

    git clone "https://github.com/$plugin.git" "$plugin_dir"
    git -C "$plugin_dir" checkout --quiet "$git_ref"
}

# Subcommand to load all plugins (cloning if necessary)
_zalgz_init_plugins() {
    [[ -f "$ZALGZ_PLUGIN_DB" ]] || touch "$ZALGZ_PLUGIN_DB"
    while read -r plugin git_ref; do
        [[ "$plugin" == \#* ]] && continue
        plugin_dir="$ZALGZ_PLUGIN_DIR/$plugin"
        if [[ ! -d "$plugin_dir" ]]; then
            _zalgz_git_clone_and_checkout "$plugin" "$git_ref" "$plugin_dir"
        fi
        _zalgz_load_plugin "$plugin_dir"
    done < "$ZALGZ_PLUGIN_DB"
}

# Subcommand to install and load a specific plugin
_zalgz_install() {
    plugin="$1"
    flag="$2"
    if [[ -z "$plugin" ]]; then
        _zalgz_help install
        return
    fi
    # Get the default branch from the remote repository
    git_ref=$(git ls-remote --symref "https://github.com/$plugin.git" HEAD \
                  | grep 'ref:' \
                  | sed 's|ref: refs/heads/\([^[:space:]]*\).*HEAD.*|origin/\1|')
    if [[ "$flag" != "-t" ]]; then
        echo "Adding $plugin $git_ref to plugins.txt"
        echo "$plugin $git_ref" >> "$ZALGZ_PLUGIN_DB"
    fi
    _zalgz_git_clone_and_checkout "$plugin" "$git_ref" "$ZALGZ_PLUGIN_DIR/$plugin"
    _zalgz_load_plugin "$ZALGZ_PLUGIN_DIR/$plugin"
}

_zalgz_list_plugins() {
    while read -r plugin git_ref; do
        [[ "$plugin" == \#* ]] && continue
        echo "$plugin $git_ref"
    done < "$ZALGZ_PLUGIN_DIR"
}

_zalgz_try() {
    plugin="$1"
    if [[ -z "$plugin" ]]; then
        _zalgz_help try
        return
    fi

    # Create a temporary directory for the plugin
    tmp_dir=$(mktemp -d)
    if [[ -z "$tmp_dir" ]]; then
        echo "Failed to create temporary directory."
        return
    fi

    # Store the current plugin directory and override it with the temporary one
    prev_plugin_dir="$ZALGZ_PLUGIN_DIR"
    export ZALGZ_PLUGIN_DIR="$tmp_dir"

    # Call the install function
    _zalgz_install "$plugin" -t

    # Restore the original plugin directory
    export ZALGZ_PLUGIN_DIR="$prev_plugin_dir"

    echo "Plugin $plugin has been cloned to the temporary directory $tmp_dir."
}

# Subcommand to update all or specific plugins
_zalgz_update() {
    target="$1"
    while read -r plugin git_ref; do
        if [[ "$target" == "all" || "$target" == "$plugin" ]]; then
            plugin_dir="$ZALGZ_PLUGIN_DIR/$plugin"
            git -C "$plugin_dir" remote update
            git -C "$plugin_dir" reset --hard "$git_ref"
        fi
    done < "$ZALGZ_PLUGIN_DB"
    echo "Plugins updated. Start a new shell to load updates."
}

_zalgz_help() {
    local subcommand="$1"

    if [ -z "$subcommand" ]; then
        echo "zalgz <subcommand> [options]"
        echo
        echo "Available subcommands:"
        echo "   init        Initialize plugins"
        echo "   install     Install a specific plugin"
        echo "   update      Update plugins"
        echo "   try         Try a plugin (temp install)"
        echo "   help"
    else
        case "$subcommand" in
            init)
                echo "Usage: zalgz init"
                echo
                echo "Initialize all plugins"
                ;;
            install)
                echo "Usage: zalgz install <repo/plugin>"
                echo
                echo "Install a specific plugin and save it to plugins.txt"
                ;;
            update)
                echo "Usage: zalgz update <target>"
                echo
                echo "Update plugins. <target> can be either a package"
                echo "name (repo/plugin) or the special word \"all\", which"
                echo "will update all packages."
                ;;
            list)
                echo "Usage: zalgz list"
                echo
                echo "Prints installed plugins."
                ;;
            try)
                echo "Usage: zalgz try <repo/plugin>"
                echo
                echo "Installs the plugin to a temp directory and loads it"
                echo "in the current session only."
                ;;
            help)
                echo "Usage: zalgz help <subcommand>"
                echo
                echo "Show help information for a specific subcommand."
                ;;
            *)
                echo "Unknown subcommand: $subcommand"
                echo
                echo "Use 'zalgz help' for a list of available subcommands."
                ;;
        esac
    fi
}

# Main command with subcommand handling
zalgz() {
    case "$1" in
        init) _zalgz_init_plugins ;;
        install) _zalgz_install "$2" ;;
        update) _zalgz_update "$2" ;;
        list) _zalgz_list_plugins ;;
        try) _zalgz_try "$2" ;;
        help)
            shift
            _zalgz_help $*
            ;;
        *) echo "Invalid subcommand. Use 'init', 'install', or 'update'." ;;
    esac
}

_zalgz_completion() {
    if (( CURRENT == 2 )); then
        _zalgz_complete_main_subcommands && return
    fi

    case "$words[2]" in
        update)
            if (( CURRENT == 3 )); then
                _zalgz_complete_update_subcommands && return
            fi
            ;;
        help)
            if (( CURRENT == 3 )); then
                _zalgz_complete_main_subcommands && return
            fi
            ;;
    esac
}

_zalgz_complete_main_subcommands() {
    local -a main_subcommands
    main_subcommands=("init" "install" "update" "list" "try" "help")
    _describe -t main_subcommands "main subcommands" main_subcommands
}

_zalgz_complete_update_subcommands() {
    local -a plugins
    plugins=("all") # Include the special token "all"
    while read -r plugin _; do
        plugins+=("${plugin}")
    done < "$ZALGZ_PLUGIN_DB"
    _describe -t update_subcommands "update subcommands" plugins
}

# Associating the completion function with zalgz command
compdef _zalgz_completion zalgz
