vim9script
# Mode switching, ported from denops/skeleton/function/mode.ts and
# denops/skeleton/mode.ts.

import '../config.vim' as config
import '../kana.vim' as kana
import '../kana/hira_kata.vim' as hira_kata
import '../kana/hira_hankata.vim' as hira_hankata
import '../state.vim' as state_mod

# Change the skkeleton mode and let the world know.
export def ModeChange(context: any, mode: string): void
  context.SetMode(mode)
  g:skkeleton#mode = mode
  try
    doautocmd <nomodeline> User skkeleton-mode-changed
  catch
    # Note: an autocmd may throw and there is nothing here to do about it;
    #       the mode has changed either way.
  endtry
  if config.Config.keepMode
    g:skkeleton#last_mode = mode
  endif
enddef

# Reset to a fresh state, leaving abbrev mode behind first.
export def InitializeStateWithAbbrev(context: any, ignore: list<string> = []): void
  var ignored = copy(ignore)
  if context.mode == 'abbrev'
    ModeChange(context, 'hira')
    # Note: abbrev filters the table down to the henkan key, so the table and
    #       the converter that goes with it have to come back.
    ignored = filter(ignored, (_, key) => key != 'converter' && key != 'table')
  endif
  state_mod.InitializeState(context.state, ignored)
enddef

export def Abbrev(context: any, key: string = ''): void
  if context.state.type != 'input' || context.state.mode != 'direct'
    return
  endif
  skkeleton#vim9#function#input#HenkanPoint(context)
  var s = context.state
  var HenkanFirst = function('skkeleton#vim9#function#henkan#HenkanFirst')
  var table: list<list<any>> = []
  for entry in s.table
    if type(entry[1]) == v:t_func && entry[1] == HenkanFirst
      table->add(entry)
    endif
  endfor
  s.table = table
  s.directInput = true
  ModeChange(context, 'abbrev')
enddef

export def Hirakana(context: any, key: string = ''): void
  if context.state.type != 'input'
    return
  endif
  var state = context.state
  if state.mode != 'direct'
    skkeleton#vim9#function#common#Kakutei(context)
  endif
  kana.SetCurrentKanaTable(config.Config.kanaTable)
  state = context.state
  if state.type == 'input'
    state.converter = 0
  endif
  state_mod.InitializeState(state, ['converter'])
  ModeChange(context, 'hira')
enddef

export def Katakana(context: any, key: string = ''): void
  if context.state.type != 'input'
    return
  endif
  var state = context.state
  if state.mode == 'direct'
    if type(state.converter) == v:t_func
      state.converter = 0
      ModeChange(context, 'hira')
    else
      state.converter = function('skkeleton#vim9#kana#hira_kata#HiraToKata')
      ModeChange(context, 'kata')
    endif
    return
  endif
  skkeleton#vim9#function#input#KakuteiFeed(context)
  var kanaText = state.henkanFeed .. state.okuriFeed
  var result = kanaText
  if type(state.converter) != v:t_func
    result = hira_kata.HiraToKata(kanaText)
    if config.Config.registerConvertResult
      var lib = skkeleton#vim9#dictionary#Current()
      lib.RegisterHenkanResult('okurinasi', kanaText, result)
      context.SetLastCandidate({
        type: 'okurinasi',
        word: kanaText,
        candidate: result,
      })
    endif
  endif
  context.KakuteiWithUndoPoint(result)
  state_mod.InitializeState(state, ['converter'])
enddef

export def Hankatakana(context: any, key: string = ''): void
  if context.state.type != 'input'
    return
  endif
  var state = context.state
  if state.mode == 'direct'
    if type(state.converter) == v:t_func &&
        state.converter == function('skkeleton#vim9#kana#hira_hankata#HiraToHanKata')
      state.converter = 0
      ModeChange(context, 'hira')
    else
      if kana.CurrentKanaTable() == 'zen'
        kana.SetCurrentKanaTable(config.Config.kanaTable)
        state.table = kana.GetKanaTable()
      endif
      state.converter = function('skkeleton#vim9#kana#hira_hankata#HiraToHanKata')
      ModeChange(context, 'hankata')
    endif
    return
  endif
  skkeleton#vim9#function#input#KakuteiFeed(context)
  var kanaText = state.henkanFeed .. state.okuriFeed
  var result = kanaText
  if type(state.converter) != v:t_func ||
      state.converter != function('skkeleton#vim9#kana#hira_hankata#HiraToHanKata')
    result = hira_hankata.HiraToHanKata(kanaText)
    if config.Config.registerConvertResult
      var lib = skkeleton#vim9#dictionary#Current()
      lib.RegisterHenkanResult('okurinasi', kanaText, result)
      context.SetLastCandidate({
        type: 'okurinasi',
        word: kanaText,
        candidate: result,
      })
    endif
  endif
  context.KakuteiWithUndoPoint(result)
  state_mod.InitializeState(state, ['converter'])
enddef

export def Zenkaku(context: any, key: string = ''): void
  if context.state.type != 'input'
    return
  endif
  var state = context.state
  if state.mode != 'direct'
    skkeleton#vim9#function#common#Kakutei(context)
  endif
  kana.SetCurrentKanaTable('zen')
  state = context.state
  state.table = kana.GetKanaTable()
  ModeChange(context, 'zenkaku')
enddef
