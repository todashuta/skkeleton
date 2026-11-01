vim9script
# The entry points Vim calls for every key press, ported from
# denops/skeleton/main.ts.
#
# The TypeScript version is a denops plugin and answers over RPC; this one is
# called right away, so everything here is synchronous.

import './context.vim' as context_mod
import './config.vim' as config
import './kana.vim' as kana
import './functions.vim' as functions

var context: any = 0
var initialized: bool = false

def EndsWith(str: string, suffix: string): bool
  var length = strlen(suffix)
  return strlen(str) >= length && strpart(str, strlen(str) - length) ==# suffix
enddef

export def GetContext(): any
  Init()
  return context
enddef

export def Init(force: bool = false): void
  if force
    initialized = false
  endif
  if initialized
    return
  endif
  context = context_mod.Context.new()
  try
    doautocmd <nomodeline> User skkeleton-initialize-pre
  catch
    # Note: the TypeScript version logs and carries on; an autocmd throwing is
    #       the user's business, not a reason to refuse to start.
  endtry
  try
    doautocmd <nomodeline> User skkeleton-initialize-post
  catch
  endtry
  initialized = true
enddef

# The confirm key comes from Vim as part of the completion backend definition
# (|skkeleton#register_completion_backend()|).
def HandleCompleteKey(completed: bool, confirmKey: string, notation: string): string
  if notation == '<cr>'
    if completed && config.Config.eggLikeNewline && confirmKey != ''
      return confirmKey
    endif
  endif
  return ''
enddef

def KeyList(opts: dict<any>): list<string>
  var list: list<string> = []
  for key in get(opts, 'key', [''])
    var notation = get(g:skkeleton#notation#notation_to_key, key, key)
    list->add(get(g:skkeleton#notation#key_to_notation, notation, key))
  endfor
  return list
enddef

# Run the keys of this handling and return the keys Vim has to feed.
def HandleKeys(opts: dict<any>, vimStatus: dict<any>): string
  var keyList = KeyList(opts)
  var completeInfo = get(vimStatus, 'completeInfo', {})
  var completeConfirmKey = get(vimStatus, 'completeConfirmKey', '')
  var ctx = context
  if get(completeInfo, 'pum_visible', false)
    if config.Config.debug
      echomsg 'input after complete'
    endif
    var notation = join(keyList, '')
    var handled = HandleCompleteKey(
      get(completeInfo, 'selected', -1) >= 0, completeConfirmKey, notation)
    if handled != ''
      skkeleton#vim9#function#mode#InitializeStateWithAbbrev(ctx, ['converter'])
      ctx.preEdit.Output('')
      return handled
    endif
  endif
  var before = ctx.mode
  var funcName = get(opts, 'function', '')
  if funcName != ''
    var F = functions.Resolve(funcName)
    for key in keyList
      call(F, [ctx, key])
    endfor
  else
    for key in keyList
      skkeleton#vim9#function#keymap#HandleKey(ctx, key)
    endfor
  endif
  var output = ctx.preEdit.Output(ctx.ToString())
  # Note: a key which only changes the mode leaves nothing to type, but Vim
  #       does not redraw the statusline without an input; a space and a
  #       backspace is the smallest thing that does it.
  if output == '' && before != ctx.mode
    return " \b"
  endif
  return output
enddef

def BuildResult(result: string): dict<any>
  var ctx = context
  var state = ctx.state
  # Note: asked for once and then forgotten, so that it does not travel along
  #       with every following key handling.
  #       Dropped when the handling has left something pending: an uppercase key
  #       confirms a henkan and opens a new one after it in one go, and the
  #       cursor belongs to the one it has opened.
  var restore = ctx.HasPendingInput() ? {} : ctx.restorePoint
  ctx.SetRestorePoint({})
  var phase = ''
  if state.type == 'input'
    if state.mode == 'okurinasi'
      phase = 'input:okurinasi'
    elseif state.mode == 'okuriari'
      phase = 'input:okuriari'
    else
      phase = 'input'
    endif
  else
    phase = state.type
  endif
  return {
    state: {
      henkanFeed: state.type == 'input' ? state.henkanFeed : '',
      phase: phase,
    },
    result: result,
    restoreLnum: empty(restore) ? 0 : restore.lnum,
    restoreCol: empty(restore) ? 0 : restore.col,
  }
enddef

def Enable(opts: dict<any>, vimStatus: dict<any>): string
  var oldState = context.state
  if mode() ==# 'R'
    echomsg "skkeleton doesn't allowed in replace mode"
    return ''
  endif
  if oldState.type != 'escape' &&
      !(oldState.type == 'input' && oldState.mode == 'direct') &&
      !empty(vimStatus)
    return HandleKeys(opts, vimStatus)
  endif
  # Note: must be set before the context is created, the new state reads it.
  kana.SetCurrentKanaTable(config.Config.kanaTable)
  context = context_mod.Context.new()
  var ctx = context
  try
    doautocmd <nomodeline> User skkeleton-enable-pre
  catch
  endtry
  skkeleton#internal#option#save_and_set()
  skkeleton#map()
  g:skkeleton#enabled = true
  var lastMode = get(g:, 'skkeleton#last_mode', 'hira')
  if lastMode == 'hankata'
    skkeleton#vim9#function#mode#Hankatakana(ctx)
  elseif lastMode == 'kata'
    skkeleton#vim9#function#mode#Katakana(ctx)
  elseif lastMode == 'zenkaku'
    skkeleton#vim9#function#mode#Zenkaku(ctx)
  elseif lastMode == 'abbrev'
    skkeleton#vim9#function#mode#Abbrev(ctx)
  else
    skkeleton#vim9#function#mode#Hirakana(ctx)
  endif
  try
    doautocmd <nomodeline> User skkeleton-enable-post
  catch
  endtry
  return ''
enddef

def Disable(opts: dict<any>, vimStatus: dict<any>): string
  var ctx = context
  var state = ctx.state
  # Note: plugin/skkeleton.vim defines the mappings with empty opts, so those do
  #       not come through here.
  if (state.type != 'input' || state.mode != 'direct') && !empty(vimStatus)
    return HandleKeys(opts, vimStatus)
  endif
  skkeleton#vim9#function#disable#Disable(ctx)
  return ctx.preEdit.Output(ctx.ToString())
enddef

# The one function Vim calls for every key press and for enable/disable.
export def Handle(func: string, opts: dict<any>, vimStatus: dict<any>): dict<any>
  Init()
  var ctx = context
  ctx.SetStatus(
    get(vimStatus, 'mode', ''),
    get(vimStatus, 'prevInput', ''),
    get(vimStatus, 'bufnr', -1),
    get(vimStatus, 'lnum', -1))
  # Note: a column |skkeleton-functions-kakuteiUndo| has remembered is only good
  #       while skkeleton is still writing where the undo happened.  Once there
  #       is nothing pending -- the reading taken all the way back with cancel,
  #       say -- nobody is going to confirm anything there, and the column must
  #       not move the cursor on some unrelated kakutei later on.
  if !ctx.HasPendingInput()
    ctx.ForgetPointRestore()
  endif
  # only now is it known where a kakutei has been written to the buffer
  var resolved = ctx.ResolvePendingKakutei()
  # Note: a completion engine writing its preview into the buffer is a mismatch,
  #       and the reading it is about to complete is very much still pending.
  if ctx.vimMode != 't' && !EndsWith(ctx.prevInput, ctx.ToString())
    if !resolved
      ctx.InvalidateKakutei()
    endif
    skkeleton#vim9#function#mode#InitializeStateWithAbbrev(ctx, ['converter'])
    ctx.preEdit.Output('')
  endif
  if func == 'handleKey'
    return BuildResult(HandleKeys(opts, vimStatus))
  elseif func == 'setState' || func == 'enable'
    return BuildResult(Enable(opts, vimStatus))
  elseif func == 'disable'
    return BuildResult(Disable(opts, vimStatus))
  elseif func == 'toggle'
    var noMode = get(g:, 'skkeleton#mode', '') == ''
    var disabled = noMode || !get(g:, 'skkeleton#enabled', false)
    return BuildResult(disabled ? Enable(opts, vimStatus) : Disable(opts, vimStatus))
  endif
  throw 'Unsupported function: ' .. func
enddef

# Forget everything: called when insert mode is left for good.
export def Reset(): void
  context = context_mod.Context.new()
enddef

export def GetPreEdit(): string
  Init()
  return context.ToString()
enddef

export def GetPrefix(): string
  Init()
  var state = context.state
  if state.type != 'input'
    return ''
  endif
  return state.henkanFeed
enddef

export def GetConfig(): dict<any>
  return config.Config
enddef

export def SetConfig(newConfig: dict<any>): void
  config.SetConfig(newConfig)
enddef

# Completion support -----------------------------------------------------------

export def GetCandidates(reading: string, henkanType: string = 'okurinasi'): list<string>
  Init()
  var lib = skkeleton#vim9#dictionary#Current()
  return lib.GetHenkanResult(henkanType, reading)
enddef

# Look several readings up at once.
#
# Note: the lookup stays sequential on purpose: skk_server, which one of the
#       backends talks to over a single TCP connection, reads one request at a
#       time.  The gain here is one round trip instead of one per reading, and
#       this implementation has none of those left to save.
export def GetCandidatesBatch(midashis: list<string>, henkanType: string = 'okuriari'): dict<any>
  Init()
  var lib = skkeleton#vim9#dictionary#Current()
  var results: dict<list<string>> = {}
  for midasi in midashis
    results[midasi] = lib.GetHenkanResult(henkanType, midasi)
  endfor
  return results
enddef

export def GetCompletionResult(): list<list<any>>
  Init()
  var state = context.state
  if state.type != 'input'
    return []
  endif
  var lib = skkeleton#vim9#dictionary#Current()
  return lib.GetCompletionResult(state.henkanFeed, state.feed)
enddef

export def GetCompletionResultWithRanks(): dict<any>
  Init()
  var state = context.state
  if state.type != 'input'
    return {candidates: [], ranks: []}
  endif
  var lib = skkeleton#vim9#dictionary#Current()
  return {
    candidates: lib.GetCompletionResult(state.henkanFeed, state.feed),
    ranks: lib.GetRanks(state.henkanFeed),
  }
enddef

export def GetRanks(): list<list<any>>
  Init()
  var state = context.state
  if state.type != 'input'
    return []
  endif
  var lib = skkeleton#vim9#dictionary#Current()
  return lib.GetRanks(state.henkanFeed)
enddef

export def GetCompleteItems(): list<dict<any>>
  Init()
  var state = context.state
  if state.type != 'input'
    return []
  endif
  var lib = skkeleton#vim9#dictionary#Current()
  var candidates = lib.GetCompletionResult(state.henkanFeed, state.feed)
  var ranks = lib.GetRanks(state.henkanFeed)
  var GetOkuriariCandidates = (midasi: string) =>
    lib.GetHenkanResult('okuriari', midasi)
  return skkeleton#vim9#completion#BuildCompleteItems(
    candidates, ranks, state.henkanFeed, GetOkuriariCandidates)
enddef

# Note: This is compatible with the completion source interface.
export def RegisterHenkanResult(midasi: string, word: string): void
  CompleteCallback(midasi, word)
enddef

# {inserted} is what the completion engine has written to the buffer.  It is
# optional for compatibility, but a source that omits it cannot be taken back
# by |skkeleton-functions-kakuteiUndo|.
export def CompleteCallback(
  midasi: string, word: string,
  henkanType: string = 'okurinasi', inserted: string = ''): void
  Init()
  var lib = skkeleton#vim9#dictionary#Current()
  lib.RegisterHenkanResult(henkanType, midasi, word)
  var ctx = context
  ctx.SetLastCandidate({type: henkanType, word: midasi, candidate: word})
  skkeleton#vim9#function#common#CompletionKakutei(
    ctx, henkanType, midasi, word, inserted)
enddef
