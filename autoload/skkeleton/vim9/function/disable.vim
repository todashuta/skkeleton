vim9script
# Leaving insert mode / stopping skkeleton, ported from
# denops/skeleton/function/disable.ts.

import '../config.vim' as config
import '../state.vim' as state_mod

export def Disable(context: any, key: string = ''): void
  skkeleton#vim9#function#common#Kakutei(context)
  skkeleton#disable()
  state_mod.InitializeState(context.state)
enddef

export def Escape(context: any, key: string = ''): void
  if config.Config.keepState
    # Note: with keepState the escape only puts skkeleton to sleep; coming back
    #       into insert mode is what wakes it up again.
    execute 'autocmd skkeleton InsertEnter <buffer> ++once call skkeleton#handle("enable", {})'
  endif
  Disable(context)
  context.state.type = 'escape'
enddef
