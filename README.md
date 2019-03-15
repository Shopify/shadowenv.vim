# shadowenv.vim

Vim support for [Shadowenv](https://shopify.github.io/shadowenv), providing a way to load the
appropriate Shadowenv as you change directories.

## Bugs

Mainline Vim doesn't support the `DirChange` event that we use in NeoVim. As a workaround, we bind
to `BufEnter`.

## Install

Do what you normally do; it works with [Pathogen](https://github.com/tpope/vim-pathogen) and
therefore every normal Vim plugin workflow.
