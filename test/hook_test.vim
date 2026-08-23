" Regression tests for shadowenv#hook()'s handling of the porcelain protocol.
"
" The environment variable *names* in a porcelain stream come from a
" .shadowenv.d lisp program, which can produce any text. These tests pin the
" invariant that a name is only ever applied as data, never re-parsed as part
" of an ex-command.
"
" Run with test/run.sh (works under both Vim and Neovim).

let s:repo = expand('<sfile>:p:h:h')
let s:tmp = tempname()
call mkdir(s:tmp, 'p')
let s:payload_file = s:tmp . '/payload'

" Point the plugin at the test double. This must happen before the autoload
" script is sourced, which is why it is at the top of the file.
let $SHADOWENV_FAKE_OUTPUT = s:payload_file
let g:shadowenv_binary = s:repo . '/test/fake_shadowenv'

let s:results = []
let s:failures = 0

function! s:ok(cond, name) abort
  if a:cond
    call add(s:results, 'PASS ' . a:name)
  else
    call add(s:results, 'FAIL ' . a:name)
    let s:failures += 1
  endif
endfunction

function! s:rec_set(name, value) abort
  return "\x02" . "\x1F" . a:name . "\x1F" . a:value . "\x1E"
endfunction

function! s:rec_unset(name) abort
  return "\x03" . "\x1F" . a:name . "\x1F" . "\x1E"
endfunction

" Write records as the exact bytes the real binary would emit: no trailing
" newline, since the protocol is delimiter-framed.
function! s:emit(records) abort
  call writefile([join(a:records, '')], s:payload_file, 'b')
endfunction

" Returns an empty string on success, or the exception if the hook threw.
function! s:run_hook() abort
  try
    call shadowenv#hook()
    return ''
  catch
    return v:exception
  endtry
endfunction

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" A name the ex parser would treat specially must not be re-parsed.
"
" Interpolated into `let $... = `, the name below ends the assignment early and
" the rest is read as further ex-commands.
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
unlet! g:shadowenv_test_evaluated
call s:emit([s:rec_set('X = "" | let g:shadowenv_test_evaluated = 1 | "', 'y')])
let s:exc = s:run_hook()
call s:ok(!exists('g:shadowenv_test_evaluated'), 'name with a separator in a SET record is not re-parsed')

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Same, for the UNSET opcode. $SHADOWENV_TEST_EXISTING is pre-set so the
" leading `unlet $NAME` succeeds and parsing continues past the separator.
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
unlet! g:shadowenv_test_unset_evaluated
let $SHADOWENV_TEST_EXISTING = 'x'
call s:emit([s:rec_unset('SHADOWENV_TEST_EXISTING | let g:shadowenv_test_unset_evaluated = 1')])
let s:exc = s:run_hook()
call s:ok(!exists('g:shadowenv_test_unset_evaluated'), 'name with a separator in an UNSET record is not re-parsed')

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" The ordinary path still works: a well-formed name is applied.
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
let $SHADOWENV_TEST_PLAIN = ''
call s:emit([s:rec_set('SHADOWENV_TEST_PLAIN', 'applied')])
let s:exc = s:run_hook()
call s:ok(s:exc ==# '', 'well-formed SET does not throw')
call s:ok($SHADOWENV_TEST_PLAIN ==# 'applied', 'well-formed SET is applied')

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" UNSET removes the variable.
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
let $SHADOWENV_TEST_REMOVE_ME = 'here'
call s:emit([s:rec_unset('SHADOWENV_TEST_REMOVE_ME')])
let s:exc = s:run_hook()
call s:ok(s:exc ==# '', 'well-formed UNSET does not throw')
call s:ok($SHADOWENV_TEST_REMOVE_ME ==# '', 'well-formed UNSET clears the variable')

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" A truncated SET record (only two fields) must not abort the whole stream.
"
" shadowenv <= 3.5.2 can emit a name containing 0x1E/0x1F, which truncates the
" record it appears in. Reading operands[2] on such a record raises E684 and
" silently drops every remaining variable.
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
let $SHADOWENV_TEST_AFTER_TRUNCATED = ''
call s:emit(["\x02" . "\x1F" . 'TRUNCATED' . "\x1E",
      \ s:rec_set('SHADOWENV_TEST_AFTER_TRUNCATED', 'still_applied')])
let s:exc = s:run_hook()
call s:ok(s:exc ==# '', 'truncated record does not throw: ' . s:exc)
call s:ok($SHADOWENV_TEST_AFTER_TRUNCATED ==# 'still_applied',
      \ 'records after a truncated record are still applied')

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" The name predicate gating the pre-8.1.1091 fallback. Neither Vim 9 nor any
" Neovim takes that branch, so assert the predicate directly: if it ever
" accepts a metacharacter, old Vim starts re-parsing names again.
"
" Assert it exists first. Calling a missing function while sourcing makes Vim
" skip the rest of the loop body without failing anything, which would let the
" cases below vanish silently.
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
call s:ok(exists('*shadowenv#is_safe_name'), 'shadowenv#is_safe_name is defined')

for s:good in ['FOO', '_FOO', 'F', 'foo_BAR9', '_']
  call s:ok(shadowenv#is_safe_name(s:good), 'accepts identifier: ' . s:good)
endfor

for s:bad in ['X = "" | let g:x = 1 | "', 'FOO | echo', 'FOO=BAR', 'FOO BAR',
      \ '9FOO', '', 'FOO-BAR', 'FOO$(id)', 'FOO`id`', 'FOO;id', 'FOO''x',
      \ "FOO\nBAR", "FOO\x1EBAR", "FOO\x1FBAR", 'FOO"BAR', 'FOO#x', 'FOO.BAR']
  call s:ok(!shadowenv#is_safe_name(s:bad),
        \ 'rejects non-identifier: ' . strtrans(s:bad))
endfor

call add(s:results, s:failures == 0 ? 'RESULT ok' : 'RESULT ' . s:failures . ' failed')

" Vim's silent mode swallows :echo, so report through a file the runner names.
call writefile(s:results, empty($SHADOWENV_TEST_RESULTS)
      \ ? s:tmp . '/results' : $SHADOWENV_TEST_RESULTS)

if s:failures == 0
  qall!
else
  cquit
endif
