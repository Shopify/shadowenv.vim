" shadowenv.vim - support for shadowenv <https://shopify.github.io/shadowenv>
" Author:  Burke Libbey <burke.libbey@shopify.com>
" Version: 0.1

let s:shadowenv_binary = get(g:, 'shadowenv_binary', 'shadowenv')

function! shadowenv#hook() abort
  if !executable(s:shadowenv_binary)
    echoerr 'No shadowenv executable: add it to your PATH or set g:shadowenv_binary'
    return
  endif

  let l:contents = system(s:shadowenv_binary . " hook --porcelain 2>/dev/null")

  " Fields separated by 0x1F; records separated by 0x1E.
  " example message:
  "   0x02 0x1F F O O 0x1F b a r 0x1E
  "   ^         ^          ^
  "   export    FOO=       bar
  for l:instruction in split(l:contents, "\x1E")
    let l:operands = split(l:instruction, "\x1F", 1)
    let l:opcode = l:operands[0]

    if l:opcode == "\x01" " SET_UNEXPORTED
      " ignored
    elseif l:opcode == "\x02" " SET_EXPORTED
      execute('let $'.l:operands[1].' = l:operands[2]')
    elseif l:opcode == "\x03" " UNSET
      execute('unlet $'.l:operands[1])
    else
      echoerr 'unrecognized shadowenv opcode: '.l:opcode
      return
    endif
  endfor
endfunction
