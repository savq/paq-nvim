# Paq

Paq is a Neovim package manager written in Lua.


## Features

- __Simple__: Easy to use and configure
- __Fast__:   Installs and updates packages concurrently using Neovim's event-loop
- __Small__:  Around 250 LOC


## Requirements

- git
- [Neovim](https://github.com/neovim/neovim) 0.4.4 (stable)


## Installation

Clone this repository.

For Unix-like systems:

```sh
git clone --depth=1 https://github.com/savq/paq-nvim.git \
    "${XDG_DATA_HOME:-$HOME/.local/share}"/nvim/site/pack/paqs/start/paq-nvim
```

For Windows:
```
git clone https://github.com/savq/paq-nvim.git "$env:LOCALAPPDATA\nvim-data\site\pack\paqs\start\paq-nvim"
```

## Bootstrapping 

Add the following snippet before your first usage of `paq-nvim` if you want to automatically
install `paq-nvim`.

```lua
local fn = vim.fn

local install_path = fn.stdpath('data') .. '/site/pack/paqs/start/paq-nvim'

if fn.empty(fn.glob(install_path)) > 0 then
  fn.system({'git', 'clone', '--depth=1', 'https://github.com/savq/paq-nvim.git', install_path})
end
```

## Usage

In your init.lua, `require` the `"paq"` module with a list of packages, like:

```lua
require "paq" {
    "savq/paq-nvim";                  -- Let Paq manage itself

    "neovim/nvim-lspconfig";          -- Mind the semi-colons
    "hrsh7th/nvim-compe";

    {"lervag/vimtex", opt=true};      -- Use braces when passing options
}
```

Then, source your configuration (using `:source %` or `:luafile %`) and run `:PaqInstall`.


**NOTICE:**
Calling the `paq` function per package is deprecated. Users should now pass a list to the `'paq'` module instead.


## Commands

- `PaqInstall`: Install all packages listed in your configuration.
- `PaqUpdate`: Update all packages already on your system (it won't implicitly install them).
- `PaqClean`: Remove all packages (in Paq's directory) that aren't listed on your configuration.
- `PaqSync`: Execute the three operations listed above.


## Options

| Option | Type     |                                                           |
|--------|----------|-----------------------------------------------------------|
| as     | string   | Name to use for the package locally                       |
| branch | string   | Branch of the repository                                  |
| opt    | boolean  | Optional packages are not loaded on startup               |
| pin    | boolean  | Pinned packages are not updated                           |
| run    | string   | Shell command to run after install/update                 |
| run    | function | Lua function to run after install/update                  |
| url    | string   | URL of the remote repository, useful for non-GitHub repos |
| file   | string   | Path to a local directory, useful for testing plugins     |

For more details on each option, refer to the
[documentation](https://github.com/savq/paq-nvim/tree/master/doc/paq-nvim.txt).

**NOTICE:**
The `hook` option is deprecated, and will be removed in Paq 1.0. Use `run` instead.


## Related projects

You can find a [comparison](https://github.com/savq/paq-nvim/wiki/Comparisons)
with other package managers in the [wiki](https://github.com/savq/paq-nvim/wiki).
