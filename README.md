# Paq

Paq is a Neovim package manager written in Lua.

## Features

- __Simple__: Easy to use and configure
- __Fast__:   Installs and updates packages concurrently using Nvim's event-loop
- __Small__:  Around 100 LOC


## Installation

Clone this repository:

```
git clone https://github.com/savq/paq-nvim.git \
    "${XDG_DATA_HOME:-$HOME/.local/share}"/nvim/site/pack/paqs/opt/paq-nvim
```


## Usage

In your init.vim, you can write something like:
```
lua << EOF

packadd 'paq-nvim'                 -- Load the paq-nvim package
local paq = require'paq-nvim'.paq  -- Import the module and bind the `paq` function

paq 'neovim/nvim-lspconfig'
paq 'nvim-lua/completion-nvim'
paq 'nvim-lua/diagnostic-nvim'
paq 'tjdevries/lsp_extensions.nvim'

paq{'lervag/vimtex', opt=true}
paq{'neoclide/coc.nvim', branch='release'} 

EOF
```
Then, run `:PaqInstall`.

In general, to add packages to Paq's list, use `paq '<gh-username>/<repo>'`
inside a Lua chunk (or in a Lua module).

Paq can also import packages from websites other than GitHub.com
(refer to the documentation).

Remember to use braces when passing options.
Also keep in mind that Paq doesn't generate helptags automatically.
To generate helptags after installing a plugin,
just run `:helptags ALL`.


## Commands

- `PaqInstall`: Install all plugins listed in your configuration.
- `PaqUpdate`: Update all packages already on your system (it won't implicitly install them).
- `PaqClean`: Remove all packages that aren't listed on your configuration^(\*).

\*If you have plugins that aren't managed by Paq,
you probably shouldn't put them on Paq's directory.


## Options

| Option | Type    |                              |
|--------|---------|------------------------------|
| branch | string  | Branch of the repository     |
| opt    | boolean | Is the package optional?     |
| url    | string  | URL of the remote repository |


## Transitioning from other package managers

The [docs](https://github.com/savq/paq-nvim/tree/master/doc/paq-nvim.txt)
include a section on transitioning from other package managers.


## Contributing

Paq is small because my own needs as a neovim user are pretty simple,
but that doesn't mean I'm against adding features.
Read the [docs](https://github.com/savq/paq-nvim/tree/master/doc/paq-nvim.txt)
section on contributing for more information.

