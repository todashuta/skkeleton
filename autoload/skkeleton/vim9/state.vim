vim9script
# The input/henkan state, ported from denops/skkeleton/state.ts.
#
# Note: the TypeScript version models the three states as a union of object
#       types.  Vim9 script has no union type, so one dict holds every field and
#       `type` says which of them mean something.  A dict rather than a class:
#       the code assigns whole states around (`context.state = restored`), and
#       the fields are read on every key press through a dict anyway.

import './config.vim' as config
import './candidate.vim' as candidate
import './kana.vim' as kana

# A fresh state in direct input mode.
export def NewInputState(): dict<any>
  return {
    type: 'input',
    mode: 'direct',
    affix: '',
    directInput: false,
    table: kana.GetKanaTable(),
    converter: 0,
    feed: '',
    henkanFeed: '',
    okuriFeed: '',
    previousFeed: false,
    word: '',
    candidates: [],
    candidateIndex: 0,
  }
enddef

# Reset {state} to a fresh input state, keeping the fields listed in {ignore}.
#
# Note: this mirrors Object.assign(state, defaults, ignored) in the TypeScript
#       version: everything goes back to its default except what the caller
#       wants to survive (the converter and the table are what a mode change
#       keeps).
export def InitializeState(state: dict<any>, ignore: list<string> = []): dict<any>
  var def = NewInputState()
  for key in ignore
    if has_key(state, key)
      def[key] = state[key]
    endif
  endfor
  extend(state, def, 'force')
  return state
enddef

# Apply {converter} (a Funcref) to {str}, or return it as it is.
export def ApplyConverter(converter: any, str: string): string
  if type(converter) == v:t_func
    return call(converter, [str])
  endif
  return str
enddef

export def InputStateToString(state: dict<any>): string
  var ret = ''
  if state.mode != 'direct'
    ret = config.Config.markerHenkan .. state.henkanFeed
  endif
  if state.mode == 'okuriari'
    if state.previousFeed
      # Note: the reading before the henkan point was already committed, so
      #       the marker sits in front of the whole feed.
      return ret .. state.feed .. '*'
    endif
    ret ..= '*' .. state.okuriFeed
  endif
  ret = ApplyConverter(state.converter, ret)
  return ret .. state.feed
enddef

export def HenkanStateToString(state: dict<any>): string
  var candidateWord = candidate.ModifyCandidate(
    state.candidates[state.candidateIndex], state.affix)
  if candidateWord == ''
    candidateWord = 'error'
  endif
  var okuriStr = ApplyConverter(state.converter, state.okuriFeed)
  return config.Config.markerHenkanSelect .. candidateWord .. okuriStr
enddef

export def ToString(state: dict<any>): string
  if state.type == 'input'
    return InputStateToString(state)
  elseif state.type == 'henkan'
    return HenkanStateToString(state)
  elseif state.type == 'escape'
    return "\<Esc>"
  endif
  return ''
enddef
