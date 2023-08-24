# Zalgz Plugin System

Zalgz is a home-grown plugin system for zsh that enables users to manage
plugins from a central location. It provides functionalities such as plugin
initialization, installation, listing, trying out, and updating.

## Requirements

- **Environment Variable**: Make sure to set the `ZALGZ_BASE_DIR`
  environment variable to the base directory where plugins are to be
  managed.

## Features

- **Initialization**: Loads all available plugins from the configured
  plugin directory.
- **Installation**: Installs specific plugins from GitHub repositories.
- **Listing**: Lists all installed plugins.
- **Trying Out Plugins**: Tries a specific plugin by temporarily cloning
  and loading it.
- **Updating**: Updates all or specific plugins.
- **Debugging**: Supports configurable debug levels for tracing.

The list of installed plugins is saved to plugins.txt and can be edited by
hand or by using `zalgz install`. Plugins from plugins.txt will be loaded
during `zalgz init`, cloning them to the `plugins/` directory if needed.

## Usage

Below are the primary subcommands and options provided by Zalgz:

### Initializing Plugins

```
zalgz init
```

This command initializes all plugins.

### Installing a Specific Plugin

```
zalgz install <repo/plugin>
```

This command installs a specific plugin and saves it to `plugins.txt`.

### Removing a Plugin

Edit plugins.txt and remove the associated plugin directory from
`plugins/`. (TODO: add a `remove` subcommand.)

### Updating Plugins

```
zalgz update <target>
```

This command updates plugins. `<target>` can be either a package name
(repo/plugin) or the special word "all," which will update all packages.

### Listing Installed Plugins

```
zalgz list
```

This command prints installed plugins.

### Trying Out a Plugin (Temporary Installation)

```
zalgz try <repo/plugin>
```

This command installs the plugin to a temp directory and loads it in the
current session only.

### Help

```
zalgz help <subcommand>
```

Show help information for a specific subcommand.

## Completion

Zalgz also includes a completion function that provides autocomplete
suggestions for various subcommands.

## Debugging

Set the `ZALGZ_DEBUG_LEVEL` environment variable to control the debug
level. It defaults to `0`. Set to `0` to disable debugging.

## Contributing

Contributions to the Zalgz plugin system are welcome! Feel free to raise
issues or submit pull requests.
