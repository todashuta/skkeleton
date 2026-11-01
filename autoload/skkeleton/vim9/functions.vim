vim9script
# Registry from the names the TypeScript implementation knows functions by to
# the autoload names this implementation defines them at.
#
# Note: keymaps and kana tables refer to functions by name, sometimes from a
#       vimrc (|skkeleton#register_keymap()|, |skkeleton#register_kanatable()|).
#       Keeping the names in one dict is what lets the rest of the code ask for
#       a function without importing the file that defines it, which would make
#       common.vim and henkan.vim import each other.
export const Names: dict<string> = {
  # common
  kakutei: 'skkeleton#vim9#function#common#KakuteiKey',
  kakuteiUndo: 'skkeleton#vim9#function#common#KakuteiUndo',
  newline: 'skkeleton#vim9#function#common#Newline',
  cancel: 'skkeleton#vim9#function#common#Cancel',
  purgeCandidate: 'skkeleton#vim9#function#common#PurgeCandidate',
  # disable
  disable: 'skkeleton#vim9#function#disable#Disable',
  escape: 'skkeleton#vim9#function#disable#Escape',
  # henkan
  henkanFirst: 'skkeleton#vim9#function#henkan#HenkanFirst',
  henkanForward: 'skkeleton#vim9#function#henkan#HenkanForward',
  henkanBackward: 'skkeleton#vim9#function#henkan#HenkanBackward',
  henkanInput: 'skkeleton#vim9#function#henkan#HenkanInput',
  suffix: 'skkeleton#vim9#function#henkan#Suffix',
  # input
  kakuteiFeed: 'skkeleton#vim9#function#input#KakuteiFeed',
  henkanPoint: 'skkeleton#vim9#function#input#HenkanPoint',
  deleteChar: 'skkeleton#vim9#function#input#DeleteChar',
  prefix: 'skkeleton#vim9#function#input#Prefix',
  # mode
  abbrev: 'skkeleton#vim9#function#mode#Abbrev',
  hirakana: 'skkeleton#vim9#function#mode#Hirakana',
  katakana: 'skkeleton#vim9#function#mode#Katakana',
  hankatakana: 'skkeleton#vim9#function#mode#Hankatakana',
  zenkaku: 'skkeleton#vim9#function#mode#Zenkaku',
}

# Turn a registered name into a Funcref.
#
# Note: a user-registered function (one passed to skkeleton#register_keymap())
#       is a plain Vim function name and not in the registry, so it is looked
#       up as it is before giving up.
export def Resolve(name: string): func
  if has_key(Names, name)
    return function(Names[name])
  endif
  if exists('*' .. name)
    return function(name)
  endif
  throw printf('[skkeleton] unknown function: %s', name)
enddef

# Whether {name} names a function skkeleton can call.
export def Exists(name: string): bool
  return has_key(Names, name) || exists('*' .. name)
enddef
