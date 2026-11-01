vim9script
# Kana tables and how a typed key turns into kana, ported from
# denops/skeleton/kana.ts.

import './config.vim' as config
import './util.vim' as util
import './functions.vim' as functions
import './kana/rom_hira.vim' as rom_hira
import './kana/rom_zen.vim' as rom_zen

var tables: dict<list<list<any>>> = {}
var tablesInitialized: bool = false
var currentKanaTable: string = 'rom'

# Turn a registered result into what a table holds: [to, feed] or a Funcref.
#
# Note: the generated tables hold the function names, not Funcrefs, because a
#       Funcref cannot be written to a file.  Resolving here keeps the rest of
#       the code asking only "is this a list or a function".
def AsKanaResult(result: any): any
  if type(result) == v:t_string
    return functions.Resolve(result)
  elseif type(result) == v:t_list && len(result) >= 1 &&
      type(result[0]) == v:t_string
    return [result[0], len(result) > 1 ? result[1] : '']
  elseif type(result) == v:t_number
    return 0
  endif
  throw 'Illegal result: ' .. string(result)
enddef

def ResolveTable(table: list<list<any>>): list<list<any>>
  var resolved: list<list<any>> = []
  for entry in table
    if type(entry[1]) == v:t_string
      resolved->add([entry[0], functions.Resolve(entry[1])])
    else
      resolved->add(entry)
    endif
  endfor
  return resolved
enddef

def EnsureTables(): void
  if tablesInitialized
    return
  endif
  tables = {
    rom: ResolveTable(rom_hira.RomToHira),
    zen: ResolveTable(rom_zen.RomToZen),
  }
  tablesInitialized = true
enddef

export def GetKanaTable(name: string = ''): list<list<any>>
  EnsureTables()
  var key = name == '' ? currentKanaTable : name
  if !has_key(tables, key)
    throw 'undefined table: ' .. key
  endif
  return tables[key]
enddef

export def CurrentKanaTable(): string
  return currentKanaTable
enddef

export def SetCurrentKanaTable(name: string): void
  currentKanaTable = name
enddef

# Add {rawTable} (a dict from a vimrc) on top of the table named {name}.
export def RegisterKanaTable(name: string, rawTable: dict<any>, create: bool = false): void
  if config.Config.debug
    echomsg printf('skkeleton: new kana table: name: %s, table: %s', name, string(rawTable))
  endif
  var table: list<list<any>> = []
  for [kana, result] in items(rawTable)
    var key = kana
    # Note: the TypeScript version keys upper case letters as <s-x> because
    #       that is how they arrive from a mapping; a plain "A" in a table
    #       would never be looked up.
    if kana != tolower(kana)
      key = '<s-' .. tolower(kana) .. '>'
    endif
    table->add([key, AsKanaResult(result)])
  endfor
  InjectKanaTable(name, table, create)
enddef

export def LoadKanaTableFiles(payload: list<any>): void
  var table: list<list<any>> = []
  for v in payload
    var path: string
    var encoding: string
    if type(v) == v:t_list
      path = v[0]
      encoding = v[1]
    else
      path = v
      encoding = ''
    endif
    table += ReadKanaTableFile(path, encoding)
  endfor
  InjectKanaTable('rom', table)
enddef

export def LoadKanaTableFile(tableName: string, path: string, encoding: string, create: bool): void
  InjectKanaTable(tableName, ReadKanaTableFile(path, encoding), create)
enddef

# Read one "from,to" per line file into table entries.
#
# Note: a line without a comma still means something to the TypeScript version
#       (an empty result), so split() is asked to keep empty fields instead of
#       dropping them.
def ReadKanaTableFile(path: string, encoding: string): list<list<any>>
  var table: list<list<any>> = []
  var file = util.ReadFileWithEncoding(path, encoding)
  for line in split(file, "\n")
    if line =~# '^#'
      continue
    endif
    if trim(line) == ''
      continue
    endif
    var parts = split(line, ',', true)
    table->add([parts[0], [len(parts) > 1 ? parts[1] : '', '']])
  endfor
  return table
enddef

# Merge {table} into the table named {name}, first entry winning.
def InjectKanaTable(name: string, table: list<list<any>>, create: bool = false): void
  EnsureTables()
  if !has_key(tables, name) && !create
    throw 'table ' .. name .. ' is not found.'
  endif
  var existing = has_key(tables, name) ? tables[name] : []
  var merged: list<list<any>> = []
  var seen: dict<bool> = {}
  for entry in table + existing
    if has_key(seen, entry[0])
      continue
    endif
    seen[entry[0]] = true
    # Note: a null result means "this key does nothing here"; the TypeScript
    #       version drops the entry rather than keeping a hole in the table.
    if entry[1] is 0
      continue
    endif
    merged->add(entry)
  endfor
  sort(merged, (a, b) => a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0)
  tables[name] = merged
enddef
