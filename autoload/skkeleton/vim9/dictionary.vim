vim9script
# Dictionary handling, ported from denops/skkeleton/dictionary.ts.
#
# A Library owns one optional user dictionary and any number of global
# dictionaries.  Global dictionaries are lazy: constructing them only records
# the file name, the first query reads the file.  A user dictionary is read
# when it is constructed, because it is tiny and every query may have to write
# back to it.
#
# Note: the TypeScript version returns Promises everywhere because denops runs
#       in another process.  All the I/O here is local, so the functions are
#       plain synchronous ones and their names are capitalised the Vim9 way.

import './config.vim' as config
import './sources/skk_dictionary.vim' as skk_dictionary
import './sources/user_dictionary.vim' as user_dictionary

export const OkuriAriMarker = ';; okuri-ari entries.'
export const OkuriNasiMarker = ';; okuri-nasi entries.'

# --- Number conversion ---------------------------------------------------
# Ported from @geolonia/japanese-numeral (number2kanji) and cr-numeral
# (convertNumberToRoman).  Both are tiny pure functions, so they are written
# out here instead of adding a runtime dependency to a Vim plugin.

const zenkakuDigits = ['０', '１', '２', '３', '４', '５', '６', '７', '８', '９']
const kanjiDigits = ['〇', '一', '二', '三', '四', '五', '六', '七', '八', '九']

# Turn every ASCII digit of {n} into a fullwidth digit.
#
# Note: only digits are touched: "-" and "." survive for a negative number.
export def ToZenkaku(n: number): string
  return SubstituteDigits(string(n), zenkakuDigits)
enddef

# Turn every ASCII digit of {n} into a kanji digit (〇, 一, ...).
export def ToKanjiModern(n: number): string
  return SubstituteDigits(string(n), kanjiDigits)
enddef

def SubstituteDigits(str: string, table: list<string>): string
  var result = ''
  for i in range(strchars(str))
    var c = strcharpart(str, i, 1)
    if c >= '0' && c <= '9'
      result ..= table[str2nr(c)]
    else
      result ..= c
    endif
  endfor
  return result
enddef

# Numbers 11..99 with a non-zero last digit are written like "1一", the way
# kifu (棋譜, game records) write a move number.
export def ToKifu(n: number): string
  var x = n / 10
  var y = n % 10
  if 0 < x && x < 10 && 0 < y && y < 10
    return ToZenkaku(x) .. ToKanjiModern(y)
  endif
  return string(n)
enddef

# Convert {num} (less than 10000) to kanji.
def N2Kan(num: number): string
  var kanji = ''
  var number = num
  var units = [[1000, '千'], [100, '百'], [10, '十']]
  for [unit, char] in units
    var n = number / unit
    if n > 0
      number -= n * unit
      if n == 1
        kanji ..= char
      else
        kanji ..= kanjiDigits[n] .. char
      endif
    endif
  endfor
  if number > 0
    kanji ..= kanjiDigits[number]
  endif
  return kanji
enddef

# @geolonia/japanese-numeral's number2kanji(): 101 -> 百一, 12345 ->
# 一万二千三百四十五.
#
# Note: the library is documented for 0 <= n < 10^16; beyond that its helper
#       indexes past its digit table and returns garbage.  A dictionary
#       pattern can ask for any number the user typed, so the decimal form is
#       returned there instead of throwing in the middle of a conversion.
export def ToKanjiClassic(n: number): string
  if n < 0
    throw 'number2kanji: the attribute must be a non-negative integer'
  endif
  if n >= 10000000000000000
    return string(n)
  endif
  var number = n
  var kanji = ''
  for [unit, char] in [[1000000000000, '兆'], [100000000, '億'], [10000, '万']]
    var m = number / unit
    if m > 0
      number -= m * unit
      kanji ..= N2Kan(m) .. char
    endif
  endfor
  if number > 0
    kanji ..= N2Kan(number)
  endif
  return kanji == '' ? '〇' : kanji
enddef

# cr-numeral's convertNumberToRoman().
#
# Note: the library only knows symbols up to M, so 4000 is "MMMM" and larger
#       values just repeat M.  A number that the user typed can be huge, and
#       repeating M a billion times would freeze Vim, so from 100000 on the
#       decimal form is returned instead.  Numbers this big are not what the
#       #8 pattern is for.
export def ToRoman(n: number): string
  if n <= 0
    return 'Cannot convert Zero or negative numbers!!!'
  endif
  if n > 100000
    return string(n)
  endif
  var symbols = [
    'M', 'CM', 'D', 'CD', 'C', 'XC', 'L', 'XL', 'X', 'IX', 'V', 'IV', 'I',
  ]
  var values = [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1]
  var result = ''
  var remaining = n
  while remaining > 0
    var i = 0
    while remaining < values[i]
      i += 1
    endwhile
    result ..= symbols[i]
    remaining -= values[i]
  endwhile
  return result
enddef

# Daiji (大字, formal kanji used on money): 101 -> 佰壱.
export def ToDaiji(n: number): string
  var result = ToKanjiClassic(n)
  for [from, to] in [
    ['一', '壱'], ['二', '弐'], ['三', '参'], ['四', '肆'], ['五', '伍'],
    ['六', '陸'], ['七', '漆'], ['八', '捌'], ['九', '玖'], ['〇', '零'],
    ['十', '拾'], ['百', '佰'], ['千', '阡'], ['万', '萬'],
  ]
    result = substitute(result, from, to, 'g')
  endfor
  return result
enddef

# Split {str} the way JavaScript's String.split(/(#[0-9]?)/g) does: the
# separators themselves are kept as items and both ends are kept even when
# empty.
def SplitPattern(str: string): list<string>
  return SplitKeepSeparator(str, '#[0-9]\=')
enddef

# Same as SplitPattern() for String.split(/([0-9]+)/g).
def SplitEntry(str: string): list<string>
  return SplitKeepSeparator(str, '[0-9]\+')
enddef

def SplitKeepSeparator(str: string, pattern: string): list<string>
  var items: list<string> = []
  var before = ''
  var pos = 0
  while true
    var found = matchstrpos(str, pattern, pos)
    if found[1] < 0
      break
    endif
    before ..= strpart(str, pos, found[1] - pos)
    items->add(before)
    items->add(found[0])
    before = ''
    pos = found[2]
  endwhile
  items->add(before .. strpart(str, pos))
  return items
enddef

# Expand "#", "#1", "#2", "#3", "#5", "#8", "#9" placeholders in a candidate
# with the numbers the user typed.  "#0", "#4", "#6" and "#7" mean "the raw
# number".
export def ConvertNumber(pattern: string, entry: string): string
  var keys = SplitPattern(pattern)
  var values = SplitEntry(entry)
  var count = len(keys) < len(values) ? len(keys) : len(values)
  var result = ''
  for i in range(count)
    var key = keys[i]
    var value = values[i]
    if key == '#9'
      result ..= ToKifu(str2nr(value))
    elseif key == '#1'
      result ..= ToZenkaku(str2nr(value))
    elseif key == '#2'
      result ..= ToKanjiModern(str2nr(value))
    elseif key == '#3'
      result ..= ToKanjiClassic(str2nr(value))
    elseif key == '#8'
      result ..= ToRoman(str2nr(value))
    elseif key == '#5'
      result ..= ToDaiji(str2nr(value))
    elseif key == '#' || key == '#0' || key == '#4' || key == '#6' ||
        key == '#7'
      result ..= value
    else
      result ..= key
    endif
  endfor
  return result
enddef

# --- Number conversion wrapper -------------------------------------------
# A dictionary can hold patterns like "#1番" instead of "101番".  The wrapper
# looks the pattern up with the numbers replaced by "#", then fills the typed
# numbers back in.
export class NumberConvertWrapper
  var inner: any

  def new(this.inner)
  enddef

  def GetHenkanResult(type: string, word: string): list<string>
    var realWord = substitute(word, '[0-9]\+', '#', 'g')
    var candidates = this.inner.GetHenkanResult(type, realWord)
    if word ==# realWord
      return copy(candidates)
    endif
    # Note: the TypeScript version unshifts on the list the inner dictionary
    #       returned, which mutates that dictionary's own candidate list.  A
    #       copy is used here so a repeated query sees the file contents.
    var result = this.inner.GetHenkanResult(type, word) + candidates
    var converted: list<string> = []
    for candidate in result
      converted->add(ConvertNumber(candidate, word))
    endfor
    return converted
  enddef

  def GetCompletionResult(prefix: string, feed: string): list<list<any>>
    var realPrefix = substitute(prefix, '[0-9]\+', '#', 'g')
    var candidates = this.inner.GetCompletionResult(realPrefix, feed)
    if prefix ==# realPrefix
      return candidates
    endif
    var result = this.inner.GetCompletionResult(prefix, feed) + candidates
    var converted: list<list<any>> = []
    for [kana, cs] in result
      var kanas: list<string> = []
      for candidate in cs
        kanas->add(ConvertNumber(candidate, prefix))
      endfor
      converted->add([kana, kanas])
    endfor
    return converted
  enddef
endclass

export def WrapDictionary(dict: any): NumberConvertWrapper
  return NumberConvertWrapper.new(dict)
enddef

export def IsHenkanType(type: string): bool
  return type ==# 'okuriari' || type ==# 'okurinasi'
enddef

# --- Library -------------------------------------------------------------
# Merge {candidates} into the per-kana collector.
#
# Note: a dict<list<string>> cannot remember the order its keys were added in,
#       which the TypeScript version relies on (Map keeps insertion order).
#       Hence parallel order/index/value/seen lists: the order of the first
#       appearance must survive because it is the order the caller sees.
def Gather(
  order: list<string>,
  index: dict<number>,
  values: list<list<string>>,
  seen: list<dict<bool>>,
  candidates: list<list<any>>,
): void
  for [kana, cs] in candidates
    var i: number
    if has_key(index, kana)
      i = index[kana]
    else
      i = len(order)
      index[kana] = i
      order->add(kana)
      values->add([])
      seen->add({})
    endif
    for candidate in cs
      if !has_key(seen[i], candidate)
        seen[i][candidate] = true
        values[i]->add(candidate)
      endif
    endfor
  endfor
enddef

export class Library
  var dictionaries: list<any> = []
  var userDictionary: any = v:null

  def new(dictionaries: list<any>, userDictionary: any)
    this.userDictionary = userDictionary
    this.dictionaries = []
    # Note: the user dictionary is always first: its candidates are what the
    #       user typed last and they must win over the global ones.
    if type(userDictionary) != v:t_none
      this.dictionaries = [WrapDictionary(userDictionary)]
    endif
    this.dictionaries += dictionaries
  enddef

  def GetHenkanResult(type: string, word: string): list<string>
    if config.Config.immediatelyDictionaryRW
      this.Load()
    endif
    var merged: list<string> = []
    var seen: dict<bool> = {}
    for dic in this.dictionaries
      for candidate in dic.GetHenkanResult(type, word)
        if !has_key(seen, candidate)
          seen[candidate] = true
          merged->add(candidate)
        endif
      endfor
    endfor
    return merged
  enddef

  def GetCompletionResult(prefix: string, feed: string): list<list<any>>
    if config.Config.immediatelyDictionaryRW
      this.Load()
    endif
    var order: list<string> = []
    var index: dict<number> = {}
    var values: list<list<string>> = []
    var seen: list<dict<bool>> = []
    if prefix == ''
      return []
    elseif strchars(prefix) == 1
      # Note: a one character prefix has nothing to complete yet; every
      #       candidate of that reading is shown, like the TypeScript
      #       implementation does.
      for dic in this.dictionaries
        Gather(order, index, values, seen, [[prefix, dic.GetHenkanResult('okurinasi', prefix)]])
      endfor
    else
      for dic in this.dictionaries
        Gather(order, index, values, seen, dic.GetCompletionResult(prefix, feed))
      endfor
    endif
    var result: list<list<any>> = []
    for i in range(len(order))
      result->add([order[i], values[i]])
    endfor
    return result
  enddef

  def GetRanks(prefix: string): list<list<any>>
    if type(this.userDictionary) == v:t_none
      return []
    endif
    return this.userDictionary.GetRanks(prefix)
  enddef

  def RegisterHenkanResult(type: string, word: string, candidate: string): void
    if type(this.userDictionary) == v:t_none
      return
    endif
    this.userDictionary.RegisterHenkanResult(type, word, candidate)
    if config.Config.immediatelyDictionaryRW
      this.userDictionary.Save()
    endif
  enddef

  def PurgeCandidate(type: string, word: string, candidate: string): void
    if type(this.userDictionary) == v:t_none
      return
    endif
    this.userDictionary.PurgeCandidate(type, word, candidate)
    if config.Config.immediatelyDictionaryRW
      this.userDictionary.Save()
    endif
  enddef

  def Load(): void
    if type(this.userDictionary) == v:t_none
      return
    endif
    this.userDictionary.Load()
  enddef

  def Save(): void
    if type(this.userDictionary) == v:t_none
      return
    endif
    this.userDictionary.Save()
  enddef
endclass

# --- Construction --------------------------------------------------------
# Build a Library from the configured user dictionary and the named global
# dictionary sources.
export def New(sources: list<string>): Library
  var userDictionary = user_dictionary.GetUserDictionary()
  var dictionaries: list<any> = []
  for name in sources
    if name ==# 'skk_dictionary'
      for dic in skk_dictionary.GetDictionaries()
        dictionaries->add(WrapDictionary(dic))
      endfor
    elseif name ==# 'user_dictionary'
      # Note: the user dictionary is already in the library; naming it as a
      #       source would only add the same candidates twice.
      continue
    elseif name ==# 'skk_server' || name ==# 'deno_kv' ||
        name ==# 'google_japanese_input'
      # Note: Deno-only sources; there is no Vim9 counterpart.
      continue
    else
      echomsg printf('[skkeleton] Invalid source name: %s', name)
    endif
  endfor
  return Library.new(dictionaries, userDictionary)
enddef

# The library every caller shares, built on first use.
#
# Note: lazy for the same reason the TypeScript version uses a LazyCell: being
#       loaded does not mean the user is going to type Japanese, and the
#       dictionary can be tens of megabytes.
var currentLibrary: any = v:null

export def Current(force: bool = false): any
  if force
    currentLibrary = v:null
  endif
  if type(currentLibrary) == v:t_none
    currentLibrary = New(config.Config.sources)
  endif
  return currentLibrary
enddef

export def ResetCurrent(): void
  currentLibrary = v:null
enddef
