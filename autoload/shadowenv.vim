" shadowenv.vim - support for shadowenv <https://shopify.github.io/shadowenv>
" Author:  Burke Libbey <burke.libbey@shopify.com>
" Version: 0.1

let s:shadowenv_binary = get(g:, 'shadowenv_binary', 'shadowenv')

" Variable names arrive from a .shadowenv.d lisp program, which can produce any
" text, so they must be applied as data. Building an ex-command out of a name
" (`execute('let $'.name.' = ...')`) re-parses the name as part of that command:
" `let $` needs a valid identifier, and | and " are meaningful to the ex parser,
" so a name containing either is interpreted instead of used.
"
" setenv() takes the name as a value, so nothing is re-parsed. It needs Vim
" 8.1.1091 or any Neovim; older Vim falls back to applying only names that are
" valid POSIX environment variable identifiers.
let s:has_setenv = exists('*setenv')

function! s:warn(msg) abort
  echohl WarningMsg
  echomsg 'shadowenv: ' . a:msg
  echohl None
endfunction

" True only for names that survive interpolation into an ex-command unchanged,
" i.e. POSIX environment variable identifiers. This gates the pre-8.1.1091
" fallback below, so it must reject anything the ex parser treats specially.
function! shadowenv#is_safe_name(name) abort
  return a:name =~# '^[A-Za-z_][A-Za-z0-9_]*$'
endfunction

function! s:set_var(name, value) abort
  if s:has_setenv
    call setenv(a:name, a:value)
  elseif shadowenv#is_safe_name(a:name)
    execute 'let $' . a:name . ' = a:value'
  else
    call s:warn('refusing to set variable with unsupported name; upgrade to Vim 8.1.1091 or newer')
  endif
endfunction

function! s:unset_var(name) abort
  if s:has_setenv
    call setenv(a:name, v:null)
  elseif shadowenv#is_safe_name(a:name)
    execute 'unlet! $' . a:name
  else
    call s:warn('refusing to unset variable with unsupported name; upgrade to Vim 8.1.1091 or newer')
  endif
endfunction

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
      " A name may itself contain 0x1E/0x1F on shadowenv 3.5.2 and earlier,
      " which truncates this record and forges others. Skip a short record
      " rather than raising E684, which would drop every later variable.
      if len(l:operands) < 3
        call s:warn('ignoring malformed SET_EXPORTED record')
        continue
      endif
      call s:set_var(l:operands[1], l:operands[2])
    elseif l:opcode == "\x03" " UNSET
      if len(l:operands) < 2
        call s:warn('ignoring malformed UNSET record')
        continue
      endif
      call s:unset_var(l:operands[1])
    else
      echoerr 'unrecognized shadowenv opcode: '.l:opcode
      return
    endif
  endfor
endfunction
