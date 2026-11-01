vim9script
# Key to function resolution per state, ported from
# denops/skeleton/keymap.ts.

import '../config.vim' as config
import '../functions.vim' as functions

var keyMaps: dict<dict<any>> = {}
var initialized: bool = false

def Init(): void
  if initialized
    return
  endif
  keyMaps = {
    input: {
      default: 'kanaInput',
      map: {
        '<bs>': 'deleteChar',
        '<c-g>': 'cancel',
        '<c-h>': 'deleteChar',
        '<cr>': 'newline',
        '<esc>': 'escape',
        '<nl>': 'kakutei',
        '<c-q>': 'hankatakana',
        '>': 'prefix',
      },
    },
    henkan: {
      default: 'henkanInput',
      map: {
        '<c-g>': 'cancel',
        '<cr>': 'newline',
        '<nl>': 'kakutei',
        '<space>': 'henkanForward',
        'x': 'henkanBackward',
        'X': 'purgeCandidate',
        '>': 'suffix',
      },
    },
  }
  initialized = true
enddef

# Note: kanaInput and henkanInput are the two functions a state falls back to,
#       and the TypeScript version keeps them out of the named registry because
#       nothing else refers to them; Vim9 script can build their Funcrefs from
#       the autoload names instead.
def ResolveKeyMapFunc(name: string): func
  if name == 'kanaInput'
    return function('skkeleton#vim9#function#input#KanaInput')
  elseif name == 'henkanInput'
    return function('skkeleton#vim9#function#henkan#HenkanInput')
  endif
  return functions.Resolve(name)
enddef

# Turn a normalized key notation into the character Vim will send.
export def NotationToKey(notation: string): string
  return has_key(g:skkeleton#notation#notation_to_key, notation)
    ? g:skkeleton#notation#notation_to_key[notation]
    : notation
enddef

export def HandleKey(context: any, key: string): void
  if context.state.type == 'escape'
    return
  endif
  Init()
  if !has_key(keyMaps, context.state.type)
    throw 'Illegal State: ' .. context.state.type
  endif
  var keyMap = keyMaps[context.state.type]
  if config.Config.debug
    echomsg 'handleKey: ' .. key
  endif
  var name = has_key(keyMap.map, key) ? keyMap.map[key] : keyMap.default
  var F = ResolveKeyMapFunc(name)
  call(F, [context, NotationToKey(key)])
enddef

export def RegisterKeyMap(state: string, key: string, funcName: string): void
  Init()
  if config.Config.debug
    echomsg printf('registerKeyMap: state = %s key = %s func = %s', state, key, funcName)
  endif
  if !has_key(keyMaps, state)
    throw 'unknown state: ' .. state
  endif
  if funcName == ''
    if has_key(keyMaps[state].map, key)
      unlet keyMaps[state].map[key]
    endif
    return
  endif
  if !functions.Exists(funcName)
    throw 'unknown function: ' .. funcName
  endif
  keyMaps[state].map[key] = funcName
enddef
