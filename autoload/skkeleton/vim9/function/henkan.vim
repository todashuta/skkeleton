vim9script
# Henkan (conversion) state handling, ported from
# denops/skeleton/function/henkan.ts.

import '../config.vim' as config
import '../candidate.vim' as candidate_mod
import '../okuri.vim' as okuri

# Whether henkanFirst() is already running.
#
# Note: a user can map henkanFirst to a key on its own; the kana input it falls
#       back to would find the same key again and recurse forever.  The
#       TypeScript version uses a Mutex for this; Vim9 script runs this code on
#       one thread, so a flag says the same thing and does not have to be
#       awaited.
var henkanFirstLocked: bool = false

export def HenkanFirst(context: any, key: string): void
  if context.state.type != 'input'
    return
  endif

  skkeleton#vim9#function#input#KakuteiFeed(context)

  if context.state.mode == 'direct'
    if henkanFirstLocked
      context.Kakutei(key)
    else
      henkanFirstLocked = true
      try
        skkeleton#vim9#function#input#KanaInput(context, key)
      finally
        henkanFirstLocked = false
      endtry
    endif
    return
  endif

  if context.state.henkanFeed == ''
    return
  endif

  var state = context.state
  state.type = 'henkan'
  state.candidates = []
  state.candidateIndex = -1

  var lib = skkeleton#vim9#dictionary#Current()
  var word = state.mode == 'okurinasi'
    ? state.henkanFeed
    : okuri.GetOkuriStr(state.henkanFeed, state.okuriFeed)
  state.word = word
  # Note: a reading typed by hand may carry the affix marker itself (">prefix"
  #       and "suffix>"), which is only known here because henkanPoint() does
  #       not set the affix.
  if state.affix == '' && !state.directInput &&
      index(['okurinasi', 'okuriari'], state.mode) >= 0
    if state.henkanFeed =~# '>$'
      state.affix = 'prefix'
    elseif state.henkanFeed =~# '^>'
      state.affix = 'suffix'
    endif
  endif
  state.candidates = lib.GetHenkanResult(state.mode, word)
  HenkanForward(context)
enddef

export def HenkanForward(context: any, key: string = ''): void
  var state = context.state
  if state.type != 'henkan'
    return
  endif
  var oldCandidateIndex = state.candidateIndex
  # Note: once the candidate window is open, the keys printed next to the
  #       candidates select one of them directly, so a plain "next" has to skip
  #       the whole page the window is showing.
  if state.candidateIndex >= config.Config.showCandidatesCount
    state.candidateIndex += 7
  else
    state.candidateIndex += 1
  endif
  if len(state.candidates) <= state.candidateIndex
    if skkeleton#vim9#function#dictionary#RegisterWord(context)
      return
    endif
    state.candidateIndex = oldCandidateIndex
    if state.candidateIndex == -1
      context.state.type = 'input'
    endif
  endif
  if state.candidateIndex >= config.Config.showCandidatesCount
    ShowCandidates(context, state)
  endif
enddef

export def HenkanBackward(context: any, key: string = ''): void
  var state = context.state
  if state.type != 'henkan'
    return
  endif
  if state.candidateIndex >= config.Config.showCandidatesCount
    state.candidateIndex = max([
      state.candidateIndex - 7,
      config.Config.showCandidatesCount - 1,
    ])
  else
    state.candidateIndex -= 1
  endif
  if state.candidateIndex < 0
    context.state.type = 'input'
    return
  endif
  if state.candidateIndex >= config.Config.showCandidatesCount
    ShowCandidates(context, state)
  endif
enddef

# Show the page of candidates the current index is on.
export def ShowCandidates(context: any, state: dict<any>): void
  var idx = state.candidateIndex
  var candidates = state.candidates[idx : idx + 6]
  var list = mapnew(candidates, (i, c) =>
    config.Config.selectCandidateKeys[i] .. ': ' ..
      candidate_mod.ModifyCandidate(c, state.affix))
  skkeleton#popup#open(list)
enddef

export def HenkanInput(context: any, key: string): void
  var state = context.state
  if state.candidateIndex >= config.Config.showCandidatesCount
    var candIdx = stridx(config.Config.selectCandidateKeys, key)
    if candIdx != -1
      if state.candidateIndex + candIdx < len(state.candidates)
        state.candidateIndex += candIdx
        skkeleton#vim9#function#common#Kakutei(context)
      endif
      return
    endif
  endif

  skkeleton#vim9#function#common#Kakutei(context)
  var notation = has_key(g:skkeleton#notation#notation_to_key, key)
    ? g:skkeleton#notation#notation_to_key[key]
    : key
  skkeleton#vim9#function#keymap#HandleKey(context, notation)
enddef

export def Suffix(context: any, key: string = ''): void
  if context.state.type != 'henkan'
    return
  endif

  skkeleton#vim9#function#common#Kakutei(context)
  skkeleton#vim9#function#input#HenkanPoint(context)
  skkeleton#vim9#function#input#AcceptResult(context, ['>', ''], '')
  context.state.affix = 'suffix'
enddef
