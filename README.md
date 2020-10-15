# Paq

## TODO
- Write docs
- Installation instructions

Paq is a simple Neovim package manager written in Lua. Paq is also:

- __small__.  around 100 LOC
- __fast__. Paq won't mess with your path, and commands run concurrently. Call `:PaqUpdate` and carry on
- __simple__. Paq does one thing well: it downloads and updates packages


## Installation

...

## Usage

In your `init.vim`, you can write something like:

```
lua << EOF

packadd 'paq-nvim'
local paq = require'paq-nvim'.paq

paq 'itchyny/lightline.vim'
-- Use braces when passing options
paq{'lervag/vimtex', opt=true}
paq{'neoclide/coc.nvim', branch='release'} 

EOF
```


## Options

| Option | Type    |                              |
|--------|---------|------------------------------|
| opt    | boolean | Is the package optional?     |
| url    | string  | URL of the remote repository |
| branch | string  | Branch of the repository     |

