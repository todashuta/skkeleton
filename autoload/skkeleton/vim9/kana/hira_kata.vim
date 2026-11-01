vim9script
# Hiragana to katakana, ported from denops/skeleton/kana/hira_kata.ts.

import './hira_kata_table.vim' as table

export def HiraToKata(input: string): string
  var result = ''
  for c in split(input, '\zs')
    result ..= has_key(table.KatakanaTable, c) ? table.KatakanaTable[c] : c
  endfor
  return result
enddef
