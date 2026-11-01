vim9script
# Hiragana to half-width katakana, ported from
# denops/skeleton/kana/hira_hankata.ts.

import './hira_kata.vim' as hira_kata
import './hira_hankata_table.vim' as table

export def HiraToHanKata(input: string): string
  var katakana = hira_kata.HiraToKata(input)
  var result = ''
  for c in split(katakana, '\zs')
    result ..= has_key(table.HanKataTable, c) ? table.HanKataTable[c] : c
  endfor
  return result
enddef
