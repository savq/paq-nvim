# Paq

Paq is a simple Neovim package manager written in Lua.


### Features

- __small__ 100 LOC
- __fast__ Commands run concurrently. Call `:PaqUpdate` and carry on
- __simple__ Paq does one thing well: it downloads and updates packages


### Usage

In your `init.vim`, you can write something like:

```
lua << EOF

paq 'itchyny/lightline.vim'
-- Use braces when passing options
paq{'lervag/vimtex', opt=true}
paq{'neoclide/coc.nvim', branch='release'} 

EOF
```


### Options

| Option | Type    |                              |
|--------|---------|------------------------------|
| opt    | boolean | Is the package optional?     |
| url    | string  | URL of the remote repository |
| branch | string  | Branch of the repository     |

### TODO

- [ ] Write docs
    - helptags
- [ ] Commands

