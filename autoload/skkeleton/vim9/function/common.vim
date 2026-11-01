vim9script
# The key functions every state shares, ported from
# denops/skeleton/function/common.ts.

import '../config.vim' as config
import '../candidate.vim' as candidate_mod
import '../state.vim' as state_mod
import '../util.vim' as util

# Commit whatever is being composed.
export def Kakutei(context: any, key: string = ''): void
  var state = context.state
  if state.type == 'henkan'
    var snapshot = copy(state)
    var candidate = state.candidates[state.candidateIndex]
    var candidateMod = candidate_mod.ModifyCandidate(candidate, state.affix)
    if candidate != ''
      var lib = skkeleton#vim9#dictionary#Current()
      lib.RegisterHenkanResult(state.mode, state.word, candidate)
      context.SetLastCandidate({
        type: state.mode,
        word: state.word,
        candidate: candidate,
      })
    endif
    var okuriStr = state_mod.ApplyConverter(state.converter, state.okuriFeed)
    var ret = (candidateMod == '' ? 'error' : candidateMod) .. okuriStr
    context.KakuteiWithUndoPoint(ret)
    # Note: remember what is needed to take this kakutei back.
    context.RecordKakutei('henkan', ret, snapshot)
    # Note: a henkan which an undo has restored owes the cursor its place back,
    #       now that the replacement is known and its length with it.
    #       The text is written by the keys this handling returns, so the point
    #       rides along with them (see |skkeleton#restore_point()|).
    #       Whether it is used at all is decided once the handling is over: the
    #       same key can confirm a henkan and open a new one after it.
    context.SetRestorePoint(context.UsePointRestore(ret))
  elseif state.type == 'input'
    skkeleton#vim9#function#input#KakuteiFeed(context)
    var result = state.henkanFeed .. state.okuriFeed .. state.feed
    if type(state.converter) == v:t_func
      result = call(state.converter, [result])
    endif
    context.Kakutei(result)
  else
    echomsg 'initializing unknown phase state: ' .. string(state)
  endif
  skkeleton#vim9#function#mode#InitializeStateWithAbbrev(context, ['converter', 'table'])
enddef

# Remember a kakutei done by a completion engine so that kakuteiUndo can take
# it back as well.
#
# {inserted} is the string the engine has written to the buffer: the candidate
# without its annotation, followed by the okurigana for an okuriari candidate.
export def CompletionKakutei(context: any, henkanType: string, midasi: string, word: string, inserted: string): void
  # The buffer has been rewritten by the engine, so an older kakutei is stale.
  context.InvalidateKakutei()
  var state = context.state
  var candidateMod = candidate_mod.ModifyCandidate(word, '')
  if state.type != 'input' ||
      # Note: give it up when the engine has not told what it wrote: there is
      #       no way to know how much of the buffer the kakutei owns then.
      inserted == '' ||
      candidateMod == '' || stridx(inserted, candidateMod) != 0
    return
  endif
  # Note: the engine has already written, so unlike a kakutei out of a henkan
  #       there are no keys for the point to ride along with and Vim is told
  #       right away.
  #       Asked before the lookup below, because the buffer holds the text even
  #       when the candidate turns out not to be in the dictionary.
  var restore = context.UsePointRestore(inserted)
  # Note: the report can arrive after a key handling has started something else
  #       where the cursor now is -- a new henkan point, or a reading being
  #       typed on -- and the cursor belongs to that.
  var onThisReading = state.mode != 'direct' && state.henkanFeed == midasi
  if !empty(restore) && (!context.HasPendingInput() || onThisReading)
    skkeleton#restore_point(restore.lnum, restore.col)
  endif
  # Note: the completion has never been in a henkan state, so the candidates
  #       are looked up instead of being restored from a snapshot.
  #       This happens after the learning, hence the confirmed candidate comes
  #       first and is the one to select.
  var lib = skkeleton#vim9#dictionary#Current()
  var candidates = lib.GetHenkanResult(henkanType, midasi)
  var candidateIndex = index(candidates, word)
  if candidateIndex < 0
    return
  endif
  var restored = copy(state)
  restored.type = 'henkan'
  restored.mode = henkanType
  restored.affix = ''
  restored.word = midasi
  restored.candidates = candidates
  restored.candidateIndex = candidateIndex
  restored.feed = ''
  # Note: the completion may have extended the reading which has been typed,
  #       so take it from the midasi of the candidate.
  restored.henkanFeed = henkanType == 'okuriari'
    ? strcharpart(midasi, 0, strchars(midasi) - 1)
    : midasi
  restored.okuriFeed = strcharpart(inserted, strchars(candidateMod))
  restored.previousFeed = false
  context.RecordKakutei('completion', inserted, restored)
enddef

# Put the cursor right after the confirmed string, which is where the undo
# deletes it by feeding backspaces.
#
# A mis-conversion is usually noticed after typing on, so the cursor having
# moved past the kakutei must not give up on it: ask Vim to walk back to it,
# leaving whatever has been typed since then alone.  Vim only moves when the
# confirmed string is still where it was written, so an edit which has
# rewritten or displaced it takes the undo out of reach instead of deleting the
# wrong text.
#
# The cursor never having left is the common case and is answered here, without
# a round-trip to Vim.
def LocateKakutei(context: any, last: dict<any>): bool
  if context.IsRightAfterKakutei(last)
    return true
  endif
  var before = strpart(last.bufferText, 0,
    strlen(last.bufferText) - strlen(last.kakutei))
  return skkeleton#locate_kakutei(last.bufnr, last.lnum, before, last.kakutei)
enddef

# Take the last kakutei back into the candidate selection state.
export def KakuteiUndo(context: any, key: string = ''): void
  var state = context.state
  var last = context.TakeBackableKakutei()
  if empty(last) || state.type != 'input' || state.mode != 'direct' ||
      state.feed != ''
    return
  endif
  if !LocateKakutei(context, last)
    return
  endif
  if config.Config.debug
    echomsg printf('kakuteiUndo: take back a %s kakutei', last.type)
  endif
  context.Kakutei(repeat("\b", util.GraphemeLength(last.kakutei)))
  context.SetState(copy(last.state))
  # Note: prevInput still tells where the cursor was when the undo was asked
  #       for, which is where the kakutei picking another candidate puts it
  #       back.
  context.RecordPointRestore(last.kakutei, last.bufferText)
  context.InvalidateKakutei()
  if context.mode != last.mode
    skkeleton#vim9#function#mode#ModeChange(context, last.mode)
  endif
  # Show the candidate list again when it was shown at the kakutei (the popup
  # is closed on every key press).
  if context.state.candidateIndex >= config.Config.showCandidatesCount
    skkeleton#vim9#function#henkan#ShowCandidates(context, context.state)
  endif
enddef

# The confirm key always returns to hiragana input, but an internal kakutei
# does not have to: that is why this is separate from kakutei().
export def KakuteiKey(context: any, key: string = ''): void
  var state = context.state
  # Note: a confirm key with nothing to confirm disables skkeleton, which ddskk
  #       does as well.
  if state.type == 'input' && state.mode == 'direct' && state.feed == ''
    skkeleton#vim9#function#mode#Hirakana(context)
    return
  endif
  Kakutei(context)
enddef

export def Newline(context: any, key: string = ''): void
  var insertNewline = !(config.Config.eggLikeNewline &&
    (context.state.type == 'henkan' ||
      (context.state.type == 'input' && context.state.mode != 'direct')))
  Kakutei(context)
  if insertNewline
    context.Kakutei("\n")
  endif
enddef

export def Cancel(context: any, key: string = ''): void
  var state = context.state
  if state.type == 'input' && state.mode == 'direct' && context.vimMode == 'c'
    context.Kakutei("\<C-c>")
  endif
  if config.Config.immediatelyCancel
    skkeleton#vim9#function#mode#InitializeStateWithAbbrev(context)
    return
  endif
  if state.type == 'input'
    skkeleton#vim9#function#mode#InitializeStateWithAbbrev(context)
  elseif state.type == 'henkan'
    context.state.type = 'input'
  endif
enddef

export def PurgeCandidate(context: any, key: string = ''): void
  var state = context.state
  var henkanType: string
  var word: string
  var candidate: string
  if state.type == 'input'
    henkanType = context.lastCandidate.type
    word = context.lastCandidate.word
    candidate = context.lastCandidate.candidate
  elseif state.type == 'henkan'
    henkanType = state.mode
    word = state.word
    candidate = state.candidates[state.candidateIndex]
  else
    echomsg 'purgeCandidate: reach illegal state'
    return
  endif
  if word == ''
    return
  endif
  var msg = printf('Really purge? %s /%s/', word, candidate)
  if confirm(msg, "&Yes\n&No\n", 2) == 1
    var lib = skkeleton#vim9#dictionary#Current()
    lib.PurgeCandidate(henkanType, word, candidate)
    state_mod.InitializeState(state)
    context.lastCandidate.word = ''
    # Note: taking the kakutei back would restore a henkan state with the
    #       purged candidate selected, so it must not be undoable any more.
    context.InvalidateKakutei()
  endif
enddef
