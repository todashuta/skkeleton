vim9script
# Registering a word into the user dictionary, ported from
# denops/skeleton/function/dictionary.ts.

import '../config.vim' as config

const cmapKeys = ['<Esc>', '<C-g>']

# Ask for a word and confirm it as the only candidate of the current reading.
#
# Returns whether a word has been registered.
export def RegisterWord(context: any): bool
  var state = context.state
  skkeleton#internal#map#save('c')
  for k in cmapKeys
    execute printf('cnoremap <buffer> <silent> %s __skkeleton_return__<CR>', k)
  endfor
  # Note: virtualedit keeps the cursor at the line end, where a henkan of a
  #       word ending the line would otherwise slip.
  var saveVirtualedit = &l:virtualedit
  setlocal virtualedit=all
  try
    var base = '[辞書登録] ' .. state.henkanFeed
    var okuri = state.mode == 'okuriari' ? '*' .. state.okuriFeed : ''
    execute 'autocmd CmdlineEnter * ++once call skkeleton#map()'
    var input = input(base .. okuri .. ': ')
    if input == '' || stridx(input, '__skkeleton_return__') >= 0
      execute "echo '' | redraw"
      return false
    endif
    state.candidates = [input]
    state.candidateIndex = 0
    skkeleton#vim9#function#common#Kakutei(context)
    # Note: a kakutei from the dictionary registration is not worth taking
    #       back: it would only restore a henkan state holding the candidate
    #       just registered.
    context.InvalidateKakutei()
    return true
  catch
    if config.Config.debug
      echomsg 'registerWord interrupted: ' .. v:exception
    endif
  finally
    try
      doautocmd <nomodeline> User skkeleton-enable-pre
    catch
    endtry
    skkeleton#map()
    g:skkeleton#enabled = true
    redrawstatus
    &l:virtualedit = saveVirtualedit
    skkeleton#vim9#function#mode#ModeChange(context, context.mode)
    try
      doautocmd <nomodeline> User skkeleton-enable-post
    catch
    endtry
  endtry
  return false
enddef
