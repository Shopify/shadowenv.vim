#!/bin/sh
# Run the shadowenv.vim test suite under every editor available on this machine.
#
# Usage: test/run.sh
# Exits non-zero if any test fails under any editor.

set -u

repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
chmod +x "$repo/test/fake_shadowenv"

status=0
ran=0

run_one() {
  editor=$1
  shift
  results=$(mktemp)
  SHADOWENV_TEST_RESULTS="$results" "$editor" "$@" \
    -u NONE -i NONE --cmd "set rtp+=$repo" -S "$repo/test/hook_test.vim" \
    >/dev/null 2>&1
  code=$?
  echo "=== $editor ==="
  if [ -s "$results" ]; then
    cat "$results"
  else
    echo "no results written (editor exited $code)"
    status=1
  fi
  [ "$code" -eq 0 ] || status=1
  rm -f "$results"
  ran=$((ran + 1))
}

if command -v nvim >/dev/null 2>&1; then
  run_one nvim --headless
fi

# Prefer a real Vim over a vim that is just a Neovim alias.
for vim_candidate in /usr/bin/vim /usr/local/bin/vim "$(command -v vim 2>/dev/null || true)"; do
  [ -n "$vim_candidate" ] || continue
  [ -x "$vim_candidate" ] || continue
  if "$vim_candidate" --version 2>&1 | head -1 | grep -qi neovim; then
    continue
  fi
  # -N is required because -u NONE otherwise implies 'compatible', which
  # disables line continuations. Neovim has no such mode and rejects -N.
  run_one "$vim_candidate" --not-a-term -es -N
  break
done

if [ "$ran" -eq 0 ]; then
  echo "no vim or nvim found" >&2
  exit 1
fi

exit "$status"
