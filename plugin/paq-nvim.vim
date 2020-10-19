if exists('g:loaded_paq')
  finish
endif

command! PaqInstall lua require'paq-nvim'.install()
command! PaqUpdate  lua require'paq-nvim'.update()
command! PaqClean   lua require'paq-nvim'.clean()

let g:loaded_paq = 1

