if exists('g:loaded_paq')
  finish
endif

command! PaqInstall lua require'paq'.install()
command! PaqUpdate  lua require'paq'.update()
command! PaqClean   lua require'paq'.clean()

let g:loaded_paq = 1

