# Paq

Paq is a simple package manager for neovim. It's usable, but still a work in progress.

### Features

- Less than 100 lines of Lua
- Works with non-GitHub plug-ins

### Usage

In your init.vim, you can write something like:

```
lua << EOF

paq 'lervag/vimtex'
paq 'itchyny/lightline.vim'
paq {'neoclide/coc.nvim', branch = 'release'} -- Call like a table when passing options

EOF
```

### Options

| Option | Type    | Description                                                |
|--------|---------|------------------------------------------------------------|
| opt    | boolean | Is the package optional?                                   |
| url    | string  | url of the remote repository (useful for non-GitHub repos) |
| branch | string  | branch of the repository                                   |

### TODO

- [ ] Use `jobs`
- [ ] Add rm/clean command

