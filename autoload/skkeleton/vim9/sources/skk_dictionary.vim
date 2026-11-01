vim9script
# Global SKK-JISYO dictionaries, ported from
# denops/skkeleton/sources/skk_dictionary.ts.
#
# An SKK-JISYO text file has two sections:
#
#     ;; okuri-ari entries.
#     てすt /テスト/
#     ;; okuri-nasi entries.
#     てすと /テスト/test/
#
# Each entry is "reading /candidate/candidate/".  A dictionary of 100k lines
# is normal, so the file is only read on the first query and the reading is
# parsed into dicts; a plain dict lookup answers a henkan without any scan.
#
# Note: the TypeScript version reads .json/.yaml/.mpk as well because denops
#       can use the libraries that parse them.  Only JSON (json_decode) and
#       the small subset of YAML a jisyo file uses are supported here; msgpack
#       would need an unpacker that Vim does not have.

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

export class Dictionary
  # reading -> candidates.  A dict is the closest thing Vim9 has to a
  # JavaScript Map for this: the keys are unique readings.
  var okuriAri: dict<list<string>> = {}
  var okuriNasi: dict<list<string>> = {}

  # First character -> entries starting with it, built on demand for
  # completion.  Scanning 100k readings on every key press would be visible.
  var cachedCandidates: dict<list<list<any>>> = {}

  var path: string = ''
  var encoding: string = ''
  var loaded: bool = false

  def new(path: string = '', encoding: string = '')
    this.path = path
    this.encoding = encoding
  enddef

  static def FromFile(path: string, encoding: string = ''): Dictionary
    return Dictionary.new(path, encoding)
  enddef

  def GetHenkanResult(type: string, word: string): list<string>
    this.EnsureLoaded()
    # Note: assigning a class member container to a local variable makes Vim
    #       check the whole container against its declared type, which is O(n)
    #       (about 0.4ms for a 90k reading dict, on every lookup).  Reading
    #       the member directly avoids that, so the branches are written out.
    if type ==# 'okuriari'
      return has_key(this.okuriAri, word) ? this.okuriAri[word] : []
    endif
    return has_key(this.okuriNasi, word) ? this.okuriNasi[word] : []
  enddef

  def GetCompletionResult(prefix: string, feed: string): list<list<any>>
    this.EnsureLoaded()
    var candidates: list<list<any>> = []
    if feed != ''
      var table = kana.GetKanaTable()
      for entry in table
        var key = entry[0]
        var result = entry[1]
        if stridx(key, feed) != 0
          continue
        endif
        # Note: the TypeScript version tests `kanas.length > 1` on whatever
        #       the kana table holds; only a [to, feed] pair can extend the
        #       prefix with kana.  A Funcref entry runs a function instead and
        #       never matches a dictionary reading, so it is skipped.
        if type(result) != v:t_list || len(result) < 2
          continue
        endif
        var feedPrefix = prefix .. result[0]
        for candidate in this.GetCachedCandidates(strcharpart(prefix, 0, 1))
          if stridx(candidate[0], feedPrefix) == 0
            candidates->add(candidate)
          endif
        endfor
      endfor
    else
      for candidate in this.GetCachedCandidates(strcharpart(prefix, 0, 1))
        if stridx(candidate[0], prefix) == 0
          candidates->add(candidate)
        endif
      endfor
    endif
    # Note: the TypeScript version uses localeCompare(), whose collation puts
    #       a voiced kana right next to its unvoiced base (か and が differ only
    #       at a lower weight).  Vim has no collation for kana and strcoll()
    #       depends on the machine's locale, so a byte compare is used: the
    #       readings are still ordered deterministically and hiragana still
    #       comes before katakana, but "かた" now sorts before "がいしゃ".
    #       This only changes the order of the completion menu; the candidate
    #       set itself is the same as the TypeScript version's.
    sort(candidates, (a, b) => a[0] <# b[0] ? -1 : a[0] ># b[0] ? 1 : 0)
    return candidates
  enddef

  # Entries whose reading starts with {prefix}, where {prefix} is one
  # character.
  #
  # Note: the result is cached per first character because the completion
  #       callbacks of a single reading ask for the same character repeatedly.
  def GetCachedCandidates(prefix: string): list<list<any>>
    if has_key(this.cachedCandidates, prefix)
      return this.cachedCandidates[prefix]
    endif
    var candidates: list<list<any>> = []
    for word in keys(this.okuriNasi)
      if stridx(word, prefix) == 0
        candidates->add([word, this.okuriNasi[word]])
      endif
    endfor
    this.cachedCandidates[prefix] = candidates
    return candidates
  enddef

  # Read {path} now; with an empty {path} the current file, if any, is read.
  def Load(path: string = '', encoding: string = ''): Dictionary
    if path != ''
      this.path = path
      this.encoding = encoding
      this.loaded = false
      this.cachedCandidates = {}
    endif
    this.EnsureLoaded()
    return this
  enddef

  def EnsureLoaded(): void
    if this.loaded || this.path == ''
      return
    endif
    this.ReadFile()
    this.loaded = true
  enddef

  def ReadFile(): void
    var path = this.path
    if path =~# '\.yaml$' || path =~# '\.yml$'
      this.LoadYaml(util.ReadFileWithEncoding(path, 'utf-8'))
    elseif path =~# '\.json$'
      this.LoadJson(util.ReadFileWithEncoding(path, 'utf-8'))
    elseif path =~# '\.mpk$'
      throw 'skkeleton: msgpack dictionaries are not supported: ' .. path
    elseif this.encoding != ''
      this.LoadString(FixJisMapping(
        util.ReadFileWithEncoding(path, this.encoding), this.encoding))
    else
      this.LoadDetected(path)
    endif
  enddef

  # Read a text dictionary whose encoding was not given in the configuration.
  #
  # Note: util.DetectEncoding() decides UTF-8 from what Vim makes of bytes it
  #       cannot decode, but a lot of EUC-JP byte pairs also happen to be
  #       valid UTF-8 sequences (they turn into unrelated CJK code points), so
  #       a large EUC-JP dictionary can be taken for UTF-8 and read as
  #       garbage.  Each candidate is therefore parsed and the readings are
  #       inspected; the first one that looks like an SKK dictionary wins.
  def LoadDetected(path: string): void
    for candidate in ['utf-8', 'euc-jp', 'shift_jis']
      this.LoadString(FixJisMapping(
        util.ReadFileWithEncoding(path, candidate), candidate))
      if this.Plausible()
        return
      endif
    endfor
    # Nothing looked like an SKK dictionary; leave the detector's answer.
    this.LoadString(util.ReadFileWithEncoding(path, ''))
    if config.Config.debug
      echomsg 'skkeleton: could not detect the encoding of ' .. path
    endif
  enddef

  # Whether the parsed readings look like an SKK dictionary: the readings are
  # kana, abbreviations are ASCII, and a handful of patterns start with "#".
  def Plausible(): bool
    var plausible = 0
    var checked = 0
    for word in keys(this.okuriAri)
      if checked >= 100
        break
      endif
      checked += 1
      if IsPlausibleReading(word)
        plausible += 1
      endif
    endfor
    for word in keys(this.okuriNasi)
      if checked >= 200
        break
      endif
      checked += 1
      if IsPlausibleReading(word)
        plausible += 1
      endif
    endfor
    # Note: the threshold is 50%: a small dictionary can have a reading that
    #       is neither kana nor ASCII (a numeric pattern, for instance), while
    #       text decoded with the wrong encoding is mojibake for nearly every
    #       reading.
    return checked > 0 && plausible * 2 >= checked
  enddef

  def LoadJson(data: string): void
    var jisyo = json_decode(data)
    if type(jisyo) != v:t_dict
      throw 'skkeleton: jisyo JSON must be an object'
    endif
    this.okuriAri = ToCandidateMap(get(jisyo, 'okuri_ari', {}))
    this.okuriNasi = ToCandidateMap(get(jisyo, 'okuri_nasi', {}))
  enddef

  # The subset of YAML a jisyo file is written in:
  #
  #     okuri_ari:
  #       わるs:
  #         - 悪
  #     okuri_nasi:
  #       あかね:
  #         - 茜
  #
  # Note: a full YAML parser is a project of its own and Vim has none; the
  #       jisyo schema is fixed to two maps of string lists, so only that
  #       shape is understood.  Flow lists ("わるs: [悪]") are accepted as a
  #       convenience, everything else is ignored.
  def LoadYaml(data: string): void
    var ari: dict<list<string>> = {}
    var nasi: dict<list<string>> = {}
    var sections: dict<dict<list<string>>> = {
      'okuri_ari': ari,
      'okuri_nasi': nasi,
    }
    var section = ''
    var entry = ''
    for raw in split(data, "\n")
      var line = substitute(raw, '\s\+$', '', '')
      if line == '' || line =~# '^\s*#' || line =~# '^---'
        continue
      endif
      var indent = matchstr(line, '^\s*')
      var body = strpart(line, strlen(indent))
      if strlen(indent) == 0
        var colon = stridx(body, ':')
        if colon < 0
          continue
        endif
        var key = Unquote(trim(strpart(body, 0, colon)))
        section = has_key(sections, key) ? key : ''
        entry = ''
        continue
      endif
      if section == ''
        continue
      endif
      if body =~# '^-'
        if entry == ''
          continue
        endif
        var item = trim(strpart(body, 1))
        if item != ''
          sections[section][entry]->add(Unquote(item))
        endif
      else
        var colon = stridx(body, ':')
        if colon < 0
          continue
        endif
        entry = Unquote(trim(strpart(body, 0, colon)))
        sections[section][entry] = []
        var inline = trim(strpart(body, colon + 1))
        if inline =~# '^\[' && inline =~# '\]$'
          var inner = strpart(inline, 1, strlen(inline) - 2)
          for item in split(inner, ',')
            if trim(item) != ''
              sections[section][entry]->add(Unquote(trim(item)))
            endif
          endfor
        endif
      endif
    endfor
    this.okuriAri = ari
    this.okuriNasi = nasi
  enddef

  def LoadString(data: string): void
    this.okuriAri = {}
    this.okuriNasi = {}
    this.cachedCandidates = {}
    # Note: CRLF files are common on Windows; the trailing CR would otherwise
    #       keep the section markers from matching.
    var text = substitute(data, "\r\n", "\n", 'g')

    var mode = -1
    var tables = [this.okuriAri, this.okuriNasi]
    for line in split(text, "\n")
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
      # Note: the TypeScript version does not special case comment lines, but
      #       a real SKK-JISYO.L has ";" comments inside the sections and one
      #       with a space in it would be taken for an entry.
      if line == '' || strpart(line, 0, 1) ==# ';'
        continue
      endif
      var pos = stridx(line, ' ')
      if pos < 0
        continue
      endif
      var word = strpart(line, 0, pos)
      var rest = strpart(line, pos + 1)
      if strlen(rest) < 2
        continue
      endif
      # rest is "/candidate/candidate/": drop both slashes.
      tables[mode][word] = split(strpart(rest, 1, strlen(rest) - 2), '/', true)
    endfor
  enddef
endclass

# Validate the shape of a JSON jisyo map the way the jsonschema validation in
# the TypeScript version does: object of string arrays.
def ToCandidateMap(value: any): dict<list<string>>
  if type(value) != v:t_dict
    throw 'skkeleton: jisyo entries must be an object'
  endif
  var result: dict<list<string>> = {}
  for [word, candidates] in items(value)
    if type(candidates) != v:t_list
      throw printf('skkeleton: candidates of "%s" must be an array', word)
    endif
    var list: list<string> = []
    for candidate in candidates
      if type(candidate) != v:t_string
        throw printf('skkeleton: candidate of "%s" must be a string', word)
      endif
      list->add(candidate)
    endfor
    result[word] = list
  endfor
  return result
enddef

def Unquote(str: string): string
  if strlen(str) >= 2
    var first = strpart(str, 0, 1)
    var last = strpart(str, strlen(str) - 1, 1)
    if (first ==# '"' && last ==# '"') || (first ==# "'" && last ==# "'")
      return strpart(str, 1, strlen(str) - 2)
    endif
  endif
  return str
enddef

def IsPlausibleReading(word: string): bool
  if word == ''
    return false
  endif
  var first = strcharpart(word, 0, 1)
  return first =~# '^[ぁ-んァ-ヶー]$' || first =~# '^[\x20-\x7e]$'
enddef

# EUC-JP and Shift_JIS have characters that glibc's iconv() and the mapping
# encoding-japanese / TextDecoder use disagree on.  The TypeScript
# implementation reads EUC-JP through encoding-japanese and Shift_JIS through
# TextDecoder, so a dictionary converted here would otherwise hold a lookalike
# character (e.g. 〜 U+301C instead of ～ U+FF5E).
#
# Note: the pairs are the complete set of differences for JIS X 0208 (six
#       characters), so this is a fixed table, not an option.  tr() is used
#       because it translates the whole dictionary in one C pass; six
#       substitute() calls were measurably slower on a 175k line file.
const jisMappingFrom = nr2char(0x301c) .. nr2char(0x2016) ..
  nr2char(0x2212) .. nr2char(0x00a2) .. nr2char(0x00a3) .. nr2char(0x00ac)
const jisMappingTo = nr2char(0xff5e) .. nr2char(0x2225) ..
  nr2char(0xff0d) .. nr2char(0xffe0) .. nr2char(0xffe1) .. nr2char(0xffe2)

def FixJisMapping(data: string, encoding: string): string
  var name = tolower(encoding)
  if name != 'euc-jp' && name != 'eucjp' && name != 'sjis' &&
      name != 'shift_jis' && name != 'shift-jis'
    return data
  endif
  return tr(data, jisMappingFrom, jisMappingTo)
enddef

# The global dictionaries named in the configuration.
export def GetDictionaries(): list<any>
  var dictionaries: list<any> = []
  for entry in config.Config.globalDictionaries
    var path: string
    var encoding = ''
    if type(entry) == v:t_list
      path = entry[0]
      encoding = len(entry) > 1 ? entry[1] : ''
    else
      path = entry
    endif
    dictionaries->add(Dictionary.FromFile(util.HomeExpand(path), encoding))
  endfor
  return dictionaries
enddef
