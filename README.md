# Paq

Paq is a Neovim package manager written in Lua.

## Features

- __Simple__: Easy to use and configure
- __Fast__:   Installs and updates packages concurrently using Nvim's event-loop
- __Small__:  Around 150 LOC


## Requirements

- git
- [Neovim](https://github.com/neovim/neovim) 0.4.4 (stable)

NOTE: Previous versions of Paq required Neovim 0.5.
That's still available in the branch `neovim-0.5`,
and some of it will be brought back once Neovim 0.5 becomes stable.


## Installation

Clone this repository.

For Unix-like systems:

```sh
git clone https://github.com/savq/paq-nvim.git \
    "${XDG_DATA_HOME:-$HOME/.local/share}"/nvim/site/pack/paqs/opt/paq-nvim
```

For Windows:
```
git clone https://github.com/savq/paq-nvim.git "$env:LOCALAPPDATA\nvim-data\site\pack\paqs\opt\paq-nvim"
```


## Usage

In your init.vim (or init.lua), you can write something like:

```lua
lua << EOF

vim.cmd 'packadd paq-nvim'         -- Load package
local paq = require'paq-nvim'.paq  -- Import module and bind `paq` function
paq{'savq/paq-nvim', opt=true}     -- Let Paq manage itself

-- Add your packages

paq 'neovim/nvim-lspconfig'
paq 'nvim-lua/completion-nvim'
paq 'nvim-lua/lsp_extensions.nvim'

paq{'lervag/vimtex', opt=true}     -- Use braces when passing options

paq{'dracula/vim', as='dracula'}   -- Use `as` to alias a package name (here `vim`)

EOF
```

Then, run `:PaqInstall`.

In general, to add packages to Paq's list, call `paq '<gh-username>/<repo>'`
inside a Lua chunk (or in a separate Lua module).

## Commands

- `PaqInstall`: Install all packages listed in your configuration.
- `PaqUpdate`: Update all packages already on your system (it won't implicitly install them).
- `PaqClean`: Remove all packages (in Paq's directory) that aren't listed on your configuration.


## Options

| Option | Type     |                                                           |
|--------|----------|-----------------------------------------------------------|
| as     | string   | Name to use for the package locally                       |
| branch | string   | Branch of the repository                                  |
| opt    | boolean  | Is the package optional?                                  |
| run    | string   | Shell command to run after install/update                 |
| run    | function | Lua function to run after install/update                  |
| url    | string   | URL of the remote repository, useful for non-GitHub repos |

For more details on each option, refer to the
[documentation](https://github.com/savq/paq-nvim/tree/master/doc/paq-nvim.txt).

NOTICE:
The `hook` option is deprecated, and will be removed in Paq 1.0. Use `run` instead.

## Related projects

Vim and Neovim have no shortage of package managers.
You can find a [comparison](https://github.com/savq/paq-nvim/wiki/Comparisons)
with [Packer.nvim](https://github.com/wbthomason/packer.nvim),
and a [migration guide](https://github.com/savq/paq-nvim/wiki/Migration)
from Vim8 plugin managers in the [wiki](https://github.com/savq/paq-nvim/wiki).
