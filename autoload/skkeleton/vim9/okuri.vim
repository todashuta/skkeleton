vim9script
# Okurigana handling, ported from denops/skeleton/okuri.ts.

import './okuri_table.vim' as table

# Build the dictionary midasi of an okuriari reading.
#
# Note: an okurigana starting with a sokuon ("送っ") is looked up as if a "t"
#       had been typed: almost every word taking one before the okurigana does
#       so with a ta-row kana.  This is what libskk does too, and the reasoning
#       is written up at https://blog.atusy.net/2023/08/01/skk-azik-and-sokuon-okuri/
export def GetOkuriStr(word: string, okuri: string): string
  if okuri == 'っ'
    return word .. 't'
  endif
  var first = matchstr(okuri, '[^っ]')
  var alpha = has_key(table.OkuriTable, first) ? table.OkuriTable[first] : ''
  return word .. alpha
enddef

# Split {text} at every position but the last, longest first.
export def OkuriSplits(text: string): list<list<string>>
  if text == ''
    return []
  endif
  var chars = split(text, '\zs')
  var result: list<list<string>> = []
  var i = len(chars) - 1
  while i >= 1
    result->add([join(chars[0 : i - 1], ''), join(chars[i :], '')])
    i -= 1
  endwhile
  return result
enddef
