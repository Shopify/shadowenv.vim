" shadowenv.vim - support for shadowenv <https://shopify.github.io/shadowenv>
" Author:  Burke Libbey <burke.libbey@shopify.com>
" Version: 0.1

if exists('g:loaded_shadowenv')
  finish
endif
let g:loaded_shadowenv = 1

command! -nargs=0 ShadowenvHook call shadowenv#hook()

augroup shadowenv
  autocmd!
  autocmd BufWritePost *.lisp ShadowenvHook

  autocmd VimEnter * ShadowenvHook
  if exists('##DirChanged')
    autocmd DirChanged * ShadowenvHook
  else
    autocmd BufEnter * ShadowenvHook
  endif
augroup END
