vim9script
# Runtime configuration, ported from denops/skkeleton/config.ts.
#
# Note: the TypeScript version validates every key with unknownutil.  Vim9
#       script has no runtime type checker, so the checks below are kept by
#       hand.  They are there less for the types themselves than for catching a
#       misspelled key: a key the implementation never looks at would sit in
#       the dict doing nothing while the option it was supposed to set kept its
#       default.
#
# Note: the Deno-only sources understand options this implementation does not
#       (skkServer*, databasePath).  They are accepted and kept so that an
#       existing vimrc keeps working, but nothing here reads them.

import './util.vim' as util

export var Config: dict<any> = {
  acceptIllegalResult: false,
  completionBackend: 'native',
  completionRankFile: '',
  databasePath: '',
  debug: false,
  eggLikeNewline: false,
  globalDictionaries: [],
  globalKanaTableFiles: [],
  immediatelyCancel: true,
  immediatelyDictionaryRW: true,
  immediatelyOkuriConvert: true,
  kanaTable: 'rom',
  keepMode: false,
  keepState: false,
  lowercaseMap: {},
  markerHenkan: '▽',
  markerHenkanSelect: '▼',
  registerConvertResult: false,
  selectCandidateKeys: 'asdfjkl',
  setUndoPoint: true,
  showCandidatesCount: 4,
  skkServerHost: '127.0.0.1',
  skkServerPort: 1178,
  skkServerReqEnc: 'euc-jp',
  skkServerResEnc: 'euc-jp',
  skkServerTimeout: 5000,
  sources: ['skk_dictionary'],
  userDictionary: '~/.skkeleton',
}

const validators: dict<string> = {
  acceptIllegalResult: 'bool',
  completionBackend: 'string',
  completionRankFile: 'string',
  databasePath: 'string',
  debug: 'bool',
  eggLikeNewline: 'bool',
  globalDictionaries: 'pathEncodingList',
  globalKanaTableFiles: 'pathEncodingList',
  immediatelyCancel: 'bool',
  immediatelyDictionaryRW: 'bool',
  immediatelyOkuriConvert: 'bool',
  kanaTable: 'kanaTable',
  keepMode: 'bool',
  keepState: 'bool',
  lowercaseMap: 'stringRecord',
  markerHenkan: 'string',
  markerHenkanSelect: 'string',
  registerConvertResult: 'bool',
  selectCandidateKeys: 'selectCandidateKeys',
  setUndoPoint: 'bool',
  showCandidatesCount: 'number',
  skkServerHost: 'string',
  skkServerPort: 'number',
  skkServerReqEnc: 'encoding',
  skkServerResEnc: 'encoding',
  skkServerTimeout: 'number',
  sources: 'stringList',
  userDictionary: 'string',
}

# Encodings the Deno implementation knows, kept only so that the two options
# which take one are still checked against the same list.
const encodings: list<string> = [
  'utf-32', 'utf-16', 'utf-16be', 'utf-16le', 'binary', 'ascii', 'jis',
  'utf-8', 'euc-jp', 'sjis', 'unicode', 'auto',
]

const typeNames: dict<number> = {
  bool: v:t_bool,
  string: v:t_string,
  number: v:t_number,
}

def Check(name: string, kind: string, value: any): any
  if has_key(typeNames, kind)
    if type(value) != typeNames[kind]
      throw printf('`%s` must be a %s', name, kind)
    endif
    return value
  elseif kind == 'stringList'
    if type(value) != v:t_list || !empty(filter(copy(value), (_, v) => type(v) != v:t_string))
      throw printf('`%s` must be a list of strings', name)
    endif
    return value
  elseif kind == 'pathEncodingList'
    if type(value) != v:t_list
      throw printf('`%s` must be a list', name)
    endif
    for entry in value
      if type(entry) == v:t_string
        continue
      endif
      if type(entry) != v:t_list || len(entry) != 2 ||
          type(entry[0]) != v:t_string || type(entry[1]) != v:t_string
        throw printf("'%s' must be array of two string tuple", name)
      endif
    endfor
    return value
  elseif kind == 'stringRecord'
    if type(value) != v:t_dict || !empty(filter(copy(value), (_, v) => type(v) != v:t_string))
      throw printf('`%s` must be a record of strings', name)
    endif
    return value
  elseif kind == 'kanaTable'
    if type(value) != v:t_string
      throw printf('`%s` must be a string', name)
    endif
    try
      skkeleton#vim9#kana#GetKanaTable(value)
    catch
      throw printf("can't use undefined kanaTable: %s", value)
    endtry
    return value
  elseif kind == 'selectCandidateKeys'
    if type(value) != v:t_string || strchars(value) != 7 ||
        len(uniq(split(value, '\zs'))) != 7
      throw "'selectCandidateKeys' must contain 7 distinct characters"
    endif
    return value
  elseif kind == 'encoding'
    if type(value) != v:t_string || index(encodings, value) < 0
      throw printf('%s is invalid encoding', string(value))
    endif
    return value
  endif
  throw 'unknown validator: ' .. kind
enddef

# Expand "~" in every path so that the dictionary code never has to.
def Normalize(): void
  Config.globalDictionaries = mapnew(Config.globalDictionaries,
    (_, v) => type(v) == v:t_list
      ? [util.HomeExpand(v[0]), v[1]]
      : [util.HomeExpand(v), ''])
  Config.globalKanaTableFiles = mapnew(Config.globalKanaTableFiles,
    (_, v) => type(v) == v:t_list
      ? [util.HomeExpand(v[0]), v[1]]
      : util.HomeExpand(v))
  Config.userDictionary = util.HomeExpand(Config.userDictionary)
  Config.completionRankFile = util.HomeExpand(Config.completionRankFile)
  Config.databasePath = util.HomeExpand(Config.databasePath)
enddef

# Apply {newConfig} on top of the current configuration.
export def SetConfig(newConfig: dict<any>): void
  for [name, value] in items(newConfig)
    if !has_key(validators, name)
      throw printf('[skkeleton] Illegal option detected: unknown option: %s', name)
    endif
    try
      Config[name] = Check(name, validators[name], value)
    catch
      throw printf('[skkeleton] Illegal option detected: %s', v:exception)
    endtry
  endfor
  Normalize()
  # Note: asked through the autoload name rather than an import: kana.vim reads
  #       this file for kanaTable, and importing it back would make the two
  #       depend on each other.
  if exists('*skkeleton#vim9#kana#LoadKanaTableFiles')
    skkeleton#vim9#kana#LoadKanaTableFiles(Config.globalKanaTableFiles)
  else
    try
      skkeleton#vim9#kana#LoadKanaTableFiles(Config.globalKanaTableFiles)
    catch /E117:/
      # kana.vim is not installed yet; nothing to load the files into
    endtry
  endif
enddef
