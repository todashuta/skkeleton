# Skkeleton

skkeleton is a Vim/Neovim plugin that provides a Japanese input environment
called SKK.

It's heavily inspired by [ddskk](https://github.com/skk-dev/ddskk) and
[eskk.vim](https://github.com/vim-skk/eskk.vim).

# Demo

![movie](https://user-images.githubusercontent.com/36663503/131238795-89866efb-6064-4832-b0cf-132fbab1da94.gif)

## Completion with [ddc.vim](https://github.com/Shougo/ddc.vim)

![movie](https://user-images.githubusercontent.com/36663503/133924624-112837d4-8951-4f49-b2c1-554c10a09480.gif)

# Documentation

See [doc](https://github.com/vim-skk/skkeleton/tree/main/doc/skkeleton.jax)

# Vim9 script implementation

This branch replaces the Deno/denops engine with Vim9 script. The engine
(state machine, kana input, henkan, dictionaries, completion) lives in
`autoload/skkeleton/vim9/` and runs inside Vim, so neither Deno nor
[denops.vim](https://github.com/vim-denops/denops.vim) is needed.

- Required: Vim 9.2 or above (Vim9 classes and the namespaced `:import`)
- Not ported: the Deno-only sources (`skk_server`, `deno_kv`,
  `google_japanese_input`) and the ddc.vim sources under
  `denops/@ddc-sources/`. `skk_dictionary` and the user dictionary are.
- The TypeScript implementation under `denops/` is kept as the reference: the
  two are diffed by `test/vim9/run.sh` (generate `test/vim9/expected.json`
  with `tools/gen/gen_expected.ts` first) and by `test/run_dictionary.sh`.

Neovim is not supported by this implementation (Vim9 classes and `:import`).

# Requirements of the Deno implementation

The TypeScript implementation under `denops/` is using
[denops.vim](https://github.com/vim-denops/denops.vim). Required Deno 1.42.0+.

# License

zlib license
