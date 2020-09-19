# Paq

Paq is a simple package manager for neovim. It's usable, but still a work in progress.

### Features

- Less than 100 lines of Lua
- Works with non-GitHub plug-ins

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

- [ ] Use `jobs`
- [ ] Add rm/clean command
- [ ] Write docs
- [ ] Rewrite this readme

