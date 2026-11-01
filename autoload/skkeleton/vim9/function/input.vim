vim9script
# Kana input, henkan points and the key handling around them, ported from
# denops/skeleton/function/input.ts.

import '../config.vim' as config
import '../state.vim' as state_mod

# Find the table entries whose key starts with {prefix}.
#
# Note: filter() is in place in Vim9 script, and the table is shared by every
#       state, so copying it before filtering would be one allocation per key
#       press; walking the list once and collecting is cheaper than either.
def FilterPrefix(table: list<list<any>>, prefix: string): list<list<any>>
  var found: list<list<any>> = []
  for entry in table
    if stridx(entry[0], prefix) == 0
      found->add(entry)
    endif
  endfor
  return found
enddef

def HasPrefixEntry(table: list<list<any>>, prefix: string): bool
  for entry in table
    if stridx(entry[0], prefix) == 0
      return true
    endif
  endfor
  return false
enddef

# Remove the last character of {str}.
#
# Note: strpart() would cut a byte, which turns a kana into mojibake; the
#       TypeScript version slices by code unit and a kana is one of those.
def RemoveLastChar(str: string): string
  return strcharpart(str, 0, strchars(str) - 1)
enddef

# Commit the feed as a kana when the table says it is one.
export def KakuteiFeed(context: any, key: string = ''): void
  if context.state.type != 'input'
    return
  endif
  var inputState = context.state
  var queueAsKana: any = 0
  for entry in inputState.table
    if entry[0] == inputState.feed
      queueAsKana = entry[1]
      break
    endif
  endfor
  if type(queueAsKana) == v:t_list
    KakuteiKana(context, inputState, queueAsKana[0], '')
  endif
enddef

export def KakuteiKana(context: any, state: dict<any>, kana: string, feed: string): void
  if state.mode == 'direct'
    var text = kana
    if type(state.converter) == v:t_func
      text = call(state.converter, [text])
    endif
    # Note: goes through the context, which counts it as written after a
    #       kakutei the same key has just done: a vowel confirms a candidate
    #       and leaves its kana right behind it, with no pre-edit to tell.
    context.Kakutei(text)
  elseif state.mode == 'okurinasi'
    state.henkanFeed ..= kana
  elseif state.mode == 'okuriari'
    if feed != '' && state.previousFeed
      state.henkanFeed ..= kana
    else
      state.okuriFeed ..= kana
    endif
    state.previousFeed = false
  endif
  state.feed = feed
enddef

def DoKakutei(context: any, kana: string, feed: string): void
  var state = context.state
  if state.type != 'input'
    return
  endif
  KakuteiKana(context, state, kana, feed)
  if state.mode == 'okuriari' && feed == ''
    if state.okuriFeed[-1] == 'っ'
      # Note: "使っ" has not been converted yet on purpose; immediate okuri
      #       conversion is what turns it into ▽使* at once, and with it off
      #       the reading keeps being typed.
      if config.Config.immediatelyOkuriConvert
        skkeleton#vim9#function#henkan#HenkanFirst(context, '')
      endif
    else
      skkeleton#vim9#function#henkan#HenkanFirst(context, '')
    endif
  endif
enddef

# Accept a table result: a [to, feed] pair or a function to call.
export def AcceptResult(context: any, result: any, feed: string): void
  if type(result) == v:t_list
    DoKakutei(context, result[0], result[1])
  else
    var state = context.state
    state.feed = ''
    call(result, [context, feed])
  endif
enddef

export def KanaInput(context: any, char: string): void
  context.state.type = 'input'
  var state = context.state

  # Note: an argument cannot be assigned in Vim9 script, hence the copy.
  var key = char
  var lower = has_key(config.Config.lowercaseMap, key)
    ? config.Config.lowercaseMap[key]
    : tolower(key)
  if !state.directInput && key != lower
    var withShift = '<s-' .. lower .. '>'
    if HasPrefixEntry(state.table, state.feed .. withShift)
      key = withShift
    else
      HenkanPoint(context)
      KanaInput(context, lower)
      return
    endif
  endif

  var next = state.feed .. key
  var found = FilterPrefix(state.table, next)

  if len(found) == 1 && found[0][0] == next
    # An exact match commits at once.
    AcceptResult(context, found[0][1], next)
  elseif !empty(found)
    # Something can still follow, so the feed keeps growing.
    state.feed = next
  elseif state.feed != ''
    # Nothing follows any more: commit what can be committed and try {char}
    # again on top of it.
    var current: any = 0
    for entry in state.table
      if entry[0] == state.feed
        current = entry[1]
        break
      endif
    endfor
    if type(current) == v:t_list
      AcceptResult(context, current, next)
    elseif config.Config.acceptIllegalResult
      KakuteiKana(context, state, state.feed, '')
    else
      state.feed = ''
    endif
    KanaInput(context, key)
  else
    # Not in the table at all: let it through as it is.
    KakuteiKana(context, state, char, '')
  endif
enddef

export def HenkanPoint(context: any, key: string = ''): void
  if context.state.type != 'input'
    return
  endif
  var state = context.state
  var found = FilterPrefix(state.table, state.feed)
  # Note: a henkan point with an empty reading would only open an empty
  #       henkan, so the first ";" is dropped.
  if state.mode == 'okurinasi' && strlen(state.henkanFeed) == 0
    return
  endif
  if state.mode == 'direct'
    if empty(found)
      context.Kakutei(state.feed)
      state.feed = ''
    endif
    context.KakuteiWithUndoPoint('')
    state.mode = 'okurinasi'
  elseif state.mode == 'okurinasi'
    if state.feed == '' || empty(found)
      state.feed = ''
    elseif found[0][0] == state.feed
      var result = found[0][1]
      if type(result) == v:t_list
        state.henkanFeed ..= result[0]
      endif
      state.feed = ''
    else
      state.previousFeed = true
    endif
    state.mode = 'okuriari'
  endif
enddef

export def DeleteChar(context: any, key: string = ''): void
  if context.state.type != 'input'
    return
  endif
  var state = context.state
  if state.feed != ''
    state.feed = RemoveLastChar(state.feed)
  elseif state.mode == 'okuriari'
    if state.okuriFeed != ''
      state.okuriFeed = RemoveLastChar(state.okuriFeed)
    else
      state.mode = 'okurinasi'
    endif
  elseif state.mode == 'okurinasi'
    if state.henkanFeed != ''
      state.henkanFeed = RemoveLastChar(state.henkanFeed)
    else
      skkeleton#vim9#function#mode#InitializeStateWithAbbrev(context, ['converter'])
    endif
  else
    context.Kakutei("\b")
  endif
enddef

export def Prefix(context: any, key: string): void
  if context.state.type != 'input'
    return
  endif
  if !context.state.directInput &&
      strlen(context.state.henkanFeed) > 0 &&
      index(['okurinasi', 'okuriari'], context.state.mode) >= 0
    AcceptResult(context, ['>', ''], '')
    context.state.affix = 'prefix'
    skkeleton#vim9#function#henkan#HenkanFirst(context, key)
    return
  endif
  KanaInput(context, key)
enddef
