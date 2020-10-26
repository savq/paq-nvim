# Paq

Paq is a Neovim package manager written in Lua.

## Features

- __Simple__: Easy to use and configure
- __Fast__:   Installs and updates packages concurrently using Nvim's event-loop
- __Small__:  Around 100 LOC


## Requirements

- git
- [Neovim](https://github.com/neovim/neovim) 0.5

## Installation

Clone this repository:

```sh
git clone https://github.com/savq/paq-nvim.git \
    "${XDG_DATA_HOME:-$HOME/.local/share}"/nvim/site/pack/paqs/opt/paq-nvim
```


## Usage

In your init.vim, you can write something like:
```lua
lua << EOF

vim.cmd 'packadd paq-nvim'         -- Load package
local paq = require'paq-nvim'.paq  -- Import module and bind `paq` function

paq 'neovim/nvim-lspconfig'
paq 'nvim-lua/completion-nvim'
paq 'nvim-lua/diagnostic-nvim'
paq 'tjdevries/lsp_extensions.nvim'

paq{'neoclide/coc.nvim', branch='release'} -- Use braces when passing options
paq{'lervag/vimtex', opt=true}

EOF
```
Then, run `:PaqInstall`.

In general, to add packages to Paq's list, call `paq '<gh-username>/<repo>'`
inside a Lua chunk (or in a separate Lua module).

Paq can also import packages from websites other than GitHub.com
using the `url` option (refer to the
[documentation](https://github.com/savq/paq-nvim/tree/master/doc/paq-nvim.txt)).

NOTE: Paq doesn't generate helptags.
To generate helptags after installing a plugin, just run `:helptags ALL`.


## Commands

- `PaqInstall`: Install all packages listed in your configuration.
- `PaqUpdate`: Update all packages already on your system (it won't implicitly install them).
- `PaqClean`: Remove all packages (in Paq's directory) that aren't listed on your configuration.


## Options

| Option | Type    |                              |
|--------|---------|------------------------------|
| branch | string  | Branch of the repository     |
| opt    | boolean | Is the package optional?     |
| url    | string  | URL of the remote repository |


## Moving from other package managers

The [docs](https://github.com/savq/paq-nvim/tree/master/doc/paq-nvim.txt)
include a section on moving from Vim-plug or Minpac to Paq.


## Contributing

Paq is small because my own needs as a Neovim user are pretty simple,
but that doesn't mean I'm against adding features.
If you find a bug, have questions or suggestions, write an issue!

You can read the [docs](https://github.com/savq/paq-nvim/tree/master/doc/paq-nvim.txt)
section on contributing for more information.

