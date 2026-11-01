vim9script
# The user dictionary (~/.skkeleton) and candidate ranks, ported from
# denops/skkeleton/sources/user_dictionary.ts.
#
# The file uses the same SKK-JISYO text format as the global ones, but it is
# also written back: registering a word prepends the candidate to the reading
# and saving rewrites the whole file.  The okuri-ari section must be sorted in
# *descending* order and the okuri-nasi section in ascending order, which is
# what SKK implementations expect.
#
# Note: the TypeScript version keeps everything in Maps, where insertion order
#       is part of the API.  A Vim dict does not remember insertion order, so
#       the readings are kept in parallel key lists; the order decides the
#       order of candidates the completion menu shows.

import '../config.vim' as config
import '../util.vim' as util
import '../kana.vim' as kana

# Note: the TypeScript version exports these from dictionary.ts.  They are
#       repeated here because the sources must not import dictionary.vim (that
#       file imports the sources to build a Library, and a static cycle makes
#       the loading order matter).  The strings are part of the on-disk SKK
#       format and never change.
export const OkuriAriMarker = ';; okuri-ari entries.'
export const OkuriNasiMarker = ';; okuri-nasi entries.'

# Candidates whose first character is "[" are 送りありエントリブロック
# markers ("[わる/]"), not words to confirm.
#
# Note: the TypeScript version filters these only for henkan; a completion
#       that lists readings would show them.  They are filtered everywhere
#       here because a marker is never something to select.
def Filter(candidates: list<string>): list<string>
  var result: list<string> = []
  for candidate in candidates
    if strpart(candidate, 0, 1) !=# '['
      result->add(candidate)
    endif
  endfor
  return result
enddef

# Parse "/[わる/]悪/[わるs/]/" into its candidates, the way the TypeScript
# version's matchAll(/\[[^\]]+\]|[^/]+/g) does.  Bracket groups are kept as
# they are (Filter() decides about them later) and slashes separate items.
def ParseCandidates(rest: string): list<string>
  var items: list<string> = []
  var length = strlen(rest)
  var pos = 0
  while pos < length
    var char = strpart(rest, pos, 1)
    if char ==# '/'
      pos += 1
      continue
    endif
    if char ==# '['
      var close = stridx(rest, ']', pos + 1)
      # Note: the regular expression needs at least one character between the
      #       brackets; "[]" is a plain candidate.
      if close > pos + 1
        items->add(strpart(rest, pos, close - pos + 1))
        pos = close + 1
        continue
      endif
    endif
    # A run without slashes.  "[" is only special at the start of a run: the
    # TypeScript version's [^/]+ happily swallows it in the middle.
    var start = pos
    while pos < length && strpart(rest, pos, 1) !=# '/'
      pos += 1
    endwhile
    items->add(strpart(rest, start, pos - start))
  endwhile
  return items
enddef

# Ranks are timestamps, oldest first.  A number is enough: only their order
# matters, and the rank file stores the candidates sorted by it.
#
# Note: reltime() is used instead of localtime() so two registrations in the
#       same second still get distinct ranks.  The +1 guard covers a
#       registration that lands in the same microsecond as the previous one.
var lastRank: number = 0

def RankNow(): number
  var now = float2nr(reltimefloat(reltime()) * 1000000.0)
  if now <= lastRank
    now = lastRank + 1
  endif
  lastRank = now
  return now
enddef

export class Dictionary
  var okuriAri: dict<list<string>> = {}
  var okuriNasi: dict<list<string>> = {}
  # File order of the readings, which a Vim dict cannot provide.
  var okuriAriKeys: list<string> = []
  var okuriNasiKeys: list<string> = []

  var rank: dict<number> = {}

  var path: string = ''
  var rankPath: string = ''
  var loadTime: number = -1

  var cachedPrefix: string = ''
  var cachedFeed: string = ''
  var cachedCandidates: list<list<any>> = []

  def new()
  enddef

  def GetHenkanResult(type: string, word: string): list<string>
    var target = this.Target(type)
    return has_key(target, word) ? Filter(target[word]) : []
  enddef

  def GetCompletionResult(prefix: string, feed: string): list<list<any>>
    this.CacheCandidates(prefix, feed)
    return this.cachedCandidates
  enddef

  # [[candidate, rank], ...] for the candidates of the readings that start
  # with {prefix}, oldest rank first seen.
  def GetRanks(prefix: string): list<list<any>>
    this.CacheCandidates(prefix, '')
    var seen: dict<bool> = {}
    var result: list<list<any>> = []
    for entry in this.cachedCandidates
      for candidate in entry[1]
        if has_key(seen, candidate)
          continue
        endif
        seen[candidate] = true
        if has_key(this.rank, candidate)
          result->add([candidate, this.rank[candidate]])
        endif
      endfor
    endfor
    return result
  enddef

  def RegisterHenkanResult(type: string, word: string, candidate: string): void
    if candidate == ''
      return
    endif
    var target = this.Target(type)
    var keys = this.TargetKeys(type)
    var values: list<string> = [candidate]
    var seen: dict<bool> = {}
    seen[candidate] = true
    if has_key(target, word)
      for old in target[word]
        if !has_key(seen, old)
          seen[old] = true
          values->add(old)
        endif
      endfor
    else
      keys->add(word)
    endif
    target[word] = values
    this.rank[candidate] = RankNow()
    this.cachedPrefix = ''
    this.cachedFeed = ''
  enddef

  def PurgeCandidate(type: string, word: string, candidate: string): void
    var target = this.Target(type)
    if !has_key(target, word)
      return
    endif
    var values: list<string> = []
    for old in target[word]
      if old !=# candidate
        values->add(old)
      endif
    endfor
    if len(values) > 0
      target[word] = values
    else
      remove(target, word)
      var keys = this.TargetKeys(type)
      var i = index(keys, word)
      if i >= 0
        remove(keys, i)
      endif
    endif
    # Note: the TypeScript version does not invalidate the completion cache
    #       here, so a purged candidate can keep showing up until the next
    #       registration.  Clearing it is the behaviour the user expects.
    this.cachedPrefix = ''
    this.cachedFeed = ''
  enddef

  # Read {path} (and the rank file) or keep the current one when it is empty.
  #
  # Note: the file is only read again when its mtime changed, so opening
  #       insert mode does not re-read it; the mtime of the last save is
  #       remembered instead of comparing the contents.
  def Load(path: string = '', rankPath: string = ''): void
    # Note: function arguments are read-only in Vim9 script, so the "keep the
    #       current value when the argument is empty" merge needs locals.
    var nextPath = path != '' ? path : this.path
    var nextRankPath = rankPath != '' ? rankPath : this.rankPath
    this.path = nextPath
    this.rankPath = nextRankPath
    if nextPath == ''
      return
    endif
    try
      var time = getftime(nextPath)
      if time != -1
        if time == this.loadTime
          return
        endif
        this.loadTime = time
        this.ReadFile(nextPath, nextRankPath)
      endif
    catch
      if config.Config.debug
        echomsg 'userDictionary loading failed: ' .. v:exception
      endif
    endtry
    this.cachedPrefix = ''
    this.cachedFeed = ''
  enddef

  def Save(): void
    if this.path == ''
      return
    endif
    try
      this.WriteFile(this.path, this.rankPath)
    catch
      if config.Config.debug
        echomsg 'userDictionary saving failed: ' .. v:exception
      endif
      return
    endtry
    this.loadTime = getftime(this.path)
  enddef

  def ReadFile(path: string, rankPath: string): void
    this.okuriAri = {}
    this.okuriNasi = {}
    this.okuriAriKeys = []
    this.okuriNasiKeys = []
    var tables = [this.okuriAri, this.okuriNasi]
    var keys = [this.okuriAriKeys, this.okuriNasiKeys]
    var mode = -1
    # Note: unlike the global dictionary the user dictionary has always been
    #       written by skkeleton itself, so it is UTF-8 by definition.  The
    #       detector is still asked in case someone kept an old EUC-JP file.
    var data = substitute(
      util.ReadFileWithEncoding(path, ''), "\r\n", "\n", 'g')
    for line in split(data, "\n")
      if line ==# OkuriAriMarker
        mode = 0
        continue
      elseif line ==# OkuriNasiMarker
        mode = 1
        continue
      endif
      if mode < 0
        continue
      endif
      var pos = stridx(line, ' ')
      if pos < 0
        continue
      endif
      var word = strpart(line, 0, pos)
      var candidates = ParseCandidates(strpart(line, pos + 1))
      if !has_key(tables[mode], word)
        keys[mode]->add(word)
      endif
      tables[mode][word] = candidates
    endfor

    if rankPath == ''
      return
    endif
    var rankData = json_decode(util.ReadFileWithEncoding(rankPath, 'utf-8'))
    if type(rankData) != v:t_list
      throw 'skkeleton: rank data must be an array of strings'
    endif
    var rank: dict<number> = {}
    for i in range(len(rankData))
      var candidate = rankData[i]
      if type(candidate) != v:t_string
        throw 'skkeleton: rank data must be an array of strings'
      endif
      rank[candidate] = i
    endfor
    this.rank = rank
  enddef

  def WriteFile(path: string, rankPath: string): void
    # Note: in an SKK dictionary the okuri-ari candidates are sorted in
    #       reverse order (most recently used first); okuri-nasi is ascending.
    var ariKeys = copy(this.okuriAriKeys)
    sort(ariKeys, (a, b) => a <# b ? 1 : a ># b ? -1 : 0)
    var nasiKeys = copy(this.okuriNasiKeys)
    sort(nasiKeys, (a, b) => a <# b ? -1 : a ># b ? 1 : 0)
    var lines: list<string> = [OkuriAriMarker]
    for word in ariKeys
      lines->add(word .. ' /' .. join(this.okuriAri[word], '/') .. '/')
    endfor
    lines->add(OkuriNasiMarker)
    for word in nasiKeys
      lines->add(word .. ' /' .. join(this.okuriNasi[word], '/') .. '/')
    endfor
    try
      writefile(lines, path)
    catch
      echomsg printf(
        'warning(skkeleton): can''t write userDictionary to %s', path)
      throw v:exception
    endtry

    if rankPath == ''
      return
    endif
    var ranked: list<list<any>> = []
    for [candidate, rank] in items(this.rank)
      ranked->add([candidate, rank])
    endfor
    sort(ranked, (a, b) => a[1] < b[1] ? -1 : a[1] > b[1] ? 1 : 0)
    var rankData: list<string> = []
    for entry in ranked
      rankData->add(entry[0])
    endfor
    try
      # Note: the TypeScript version writes JSON.stringify() output as is, so
      #       the 'b' flag is used to keep the file from gaining a trailing NL.
      writefile([json_encode(rankData)], rankPath, 'b')
    catch
      echomsg printf(
        'warning(skkeleton): can''t write candidate rank data to %s', rankPath)
      throw v:exception
    endtry
  enddef

  def CacheCandidates(prefix: string, feed: string): void
    if this.cachedPrefix ==# prefix && this.cachedFeed ==# feed
      return
    endif
    var candidates: list<list<any>> = []
    if feed != ''
      var table = kana.GetKanaTable(config.Config.kanaTable)
      for entry in table
        var key = entry[0]
        var result = entry[1]
        if stridx(key, feed) != 0
          continue
        endif
        # Note: only a [to, feed] pair can extend the prefix with kana.  A
        #       Funcref entry runs a function instead.
        if type(result) != v:t_list || len(result) < 2
          continue
        endif
        var feedPrefix = prefix .. result[0]
        for word in this.okuriNasiKeys
          if stridx(word, feedPrefix) == 0
            candidates->add([word, Filter(this.okuriNasi[word])])
          endif
        endfor
      endfor
    else
      for word in this.okuriNasiKeys
        if stridx(word, prefix) == 0
          candidates->add([word, Filter(this.okuriNasi[word])])
        endif
      endfor
    endif
    this.cachedPrefix = prefix
    this.cachedFeed = feed
    this.cachedCandidates = candidates
  enddef

  # Note: the return type is any on purpose.  Assigning a class member of a
  #       container type to a typed local makes Vim verify the whole container
  #       on every call (O(n)); going through any keeps the same reference
  #       without that check.
  def Target(type: string): any
    return type ==# 'okuriari' ? this.okuriAri : this.okuriNasi
  enddef

  def TargetKeys(type: string): any
    return type ==# 'okuriari' ? this.okuriAriKeys : this.okuriNasiKeys
  enddef
endclass

# The configured user dictionary, whether or not its file exists yet.
export def GetUserDictionary(): any
  var dictionary = Dictionary.new()
  try
    dictionary.Load(
      util.HomeExpand(config.Config.userDictionary),
      util.HomeExpand(config.Config.completionRankFile))
  catch
    if config.Config.debug
      echomsg 'userDictionary loading failed: ' .. v:exception
    endif
  endtry
  return dictionary
enddef

export def GetDictionaries(): list<any>
  return [GetUserDictionary()]
enddef
