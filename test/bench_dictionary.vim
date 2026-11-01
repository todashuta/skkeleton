vim9script
# Measures the dictionary subsystem on a synthetic 100k reading SKK-JISYO, the
# size of a real SKK-JISYO.L.  Run through test/run_bench.sh.
#
# The dictionary is generated here instead of being checked in: the numbers to
# watch are the load time (must stay well under a second per megabyte) and the
# per-lookup time (a key press must not feel it).

import '../autoload/skkeleton/vim9/dictionary.vim' as dictionary
import '../autoload/skkeleton/vim9/sources/skk_dictionary.vim' as skk_dictionary
import '../autoload/skkeleton/vim9/sources/user_dictionary.vim' as user_dictionary

const readings = 100000
const kana = split(
  'あいうえおかきくけこさしすせそたちつてとなにぬねのはひふへほ' ..
  'まみむめもやゆよらりるれろわをんがぎぐげござじずぜぞだぢづでど' ..
  'ばびぶべぼぱぴぷぺぽ', '\zs')
const candidates = ['候補', 'テスト', '漢字', '変換', '辞書']

var seed = 42

# A small deterministic generator so that two runs measure the same file.
def Next(): number
  seed = (seed * 1103515245 + 12345) % 2147483648
  return seed
enddef

def Generate(path: string, encoding: string): number
  seed = 42
  var seen: dict<bool> = {}
  var words: list<string> = []
  while len(words) < readings
    var length = 2 + Next() % 4
    var word = ''
    for i in range(length)
      word ..= kana[Next() % len(kana)]
    endfor
    if has_key(seen, word)
      continue
    endif
    seen[word] = true
    words->add(word)
  endwhile
  var lines: list<string> = [';; okuri-ari entries.']
  var i = 0
  while i < len(words) / 10
    lines->add(words[i] .. 't /' .. candidates[i % 5] .. '/')
    i += 1
  endwhile
  lines->add(';; okuri-nasi entries.')
  while i < len(words)
    lines->add(words[i] .. ' /' .. candidates[i % 5] .. '/')
    i += 1
  endwhile
  if encoding == ''
    writefile(lines, path)
  else
    writefile([iconv(join(lines, "\n"), 'utf-8', encoding)], path, 'b')
  endif
  return len(lines)
enddef

def Ms(start: list<number>): string
  return printf('%.1f', reltimefloat(reltime(start)) * 1000.0)
enddef

def RssKb(): number
  try
    for line in readfile('/proc/self/status')
      if stridx(line, 'VmRSS:') == 0
        return str2nr(matchstr(line, '\d\+'))
      endif
    endfor
  catch
  endtry
  return 0
enddef

var results: list<string> = []
var keys: list<string> = []

def Bench(path: string, encoding: string, label: string): void
  var t = reltime()
  var dic = skk_dictionary.Dictionary.FromFile(path, encoding)
  var lib = dictionary.Library.new([dic], user_dictionary.Dictionary.new())
  var construct = Ms(t)
  var rssBefore = RssKb()
  t = reltime()
  lib.GetHenkanResult('okurinasi', keys[0])
  var load = Ms(t)
  var rss = RssKb()
  results->add(printf(
    '%s: construct=%sms load=%sms rss=%dMB(+%dMB)', label, construct, load,
    rss / 1024, (rss - rssBefore) / 1024))

  t = reltime()
  for key in keys
    lib.GetHenkanResult('okurinasi', key)
  endfor
  results->add(printf('%s: %d henkan lookups=%sms', label, len(keys), Ms(t)))

  t = reltime()
  var completion = lib.GetCompletionResult(keys[0], '')
  var cold = Ms(t)
  t = reltime()
  for i in range(10)
    lib.GetCompletionResult(keys[0], '')
  endfor
  results->add(printf('%s: completion first=%sms 10x=%sms entries=%d',
    label, cold, Ms(t), len(completion)))
  results->add(printf('%s: %d readings', label, readings))
enddef

var dir = tempname()
mkdir(dir)
var utf8Path = dir .. '/bench_utf8'
var eucjpPath = dir .. '/bench_eucjp'
var lineCount = Generate(utf8Path, '')
Generate(eucjpPath, 'euc-jp')
results->add(printf('%d lines, %d bytes (utf-8)', lineCount,
  getfsize(utf8Path)))

# The first 1000 readings of the nasi section: lookups of real readings.
var lines = readfile(utf8Path)
var nasiStart = 0
for i in range(len(lines))
  if lines[i] ==# ';; okuri-nasi entries.'
    nasiStart = i + 1
    break
  endif
endfor
for i in range(1000)
  keys->add(split(lines[nasiStart + i], ' ')[0])
endfor

Bench(utf8Path, 'utf-8', 'utf-8')
Bench(eucjpPath, 'euc-jp', 'euc-jp')
Bench(eucjpPath, '', 'euc-jp-auto')

writefile(results, getcwd() .. '/test/actual/dictionary_bench.txt')
qa!
