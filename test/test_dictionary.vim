vim9script
# Tests for the dictionary subsystem, mirroring
# denops/skkeleton/dictionary_test.ts.
#
# Expected values are generated from the TypeScript implementation:
#   DENO_DIR="$(pwd)/.deno" deno run -A --config deno.json tools/gen/gen_dict_expect.ts
#
# Run through test/run_dictionary.sh, not by hand: the relative imports below
# only resolve from the test directory.

import '../autoload/skkeleton/vim9/dictionary.vim' as dictionary
import '../autoload/skkeleton/vim9/sources/skk_dictionary.vim' as skk_dictionary
import '../autoload/skkeleton/vim9/sources/user_dictionary.vim' as user_dictionary
import '../autoload/skkeleton/vim9/config.vim' as config

const root = getcwd()
const testdataPath = root .. '/' .. glob('denops/sk*leton/testdata', 0, 1)[0]
const expectedFile = root .. '/' .. glob('test/expected/dict_expected.json', 0, 1)[0]
const expected = json_decode(join(readfile(expectedFile), "\n"))
const cases = expected.cases

var failures: list<string> = []
var checks = 0

def Eq(name: string, actual: any, expectedValue: any): void
  checks += 1
  if actual != expectedValue
    failures->add('FAIL ' .. name .. ': expected=' .. string(expectedValue) ..
      ' actual=' .. string(actual))
  endif
enddef

def Truthy(name: string, condition: bool): void
  checks += 1
  if !condition
    failures->add('FAIL ' .. name)
  endif
enddef

def FileContent(path: string): string
  return join(readfile(path), "\n") .. "\n"
enddef

def WriteTemp(lines: list<string>): string
  var path = tempname()
  writefile(lines, path)
  return path
enddef

def Skk(path: string, encoding: string): any
  return skk_dictionary.Dictionary.FromFile(path, encoding)
enddef

def NewUser(path: string = '', rankPath: string = ''): any
  var dic = user_dictionary.Dictionary.new()
  if path != ''
    dic.Load(path, rankPath)
  endif
  return dic
enddef

# --- number conversion ---------------------------------------------------
def TestNumbers(): void
  for [key, value] in items(expected.number.toKifu)
    Eq('number.toKifu.' .. key, dictionary.ToKifu(str2nr(key)), value)
  endfor
  for [key, value] in items(expected.number.toZenkaku)
    Eq('number.toZenkaku.' .. key, dictionary.ToZenkaku(str2nr(key)), value)
  endfor
  for [key, value] in items(expected.number.toKanjiModern)
    Eq('number.toKanjiModern.' .. key, dictionary.ToKanjiModern(str2nr(key)), value)
  endfor
  for [key, value] in items(expected.number.toKanjiClassic)
    Eq('number.toKanjiClassic.' .. key, dictionary.ToKanjiClassic(str2nr(key)), value)
  endfor
  for [key, value] in items(expected.number.toRoman)
    Eq('number.toRoman.' .. key, dictionary.ToRoman(str2nr(key)), value)
  endfor
  for [key, value] in items(expected.number.toDaiji)
    Eq('number.toDaiji.' .. key, dictionary.ToDaiji(str2nr(key)), value)
  endfor
  for item in expected.number.convert
    Eq('number.convert.' .. item.pattern .. '|' .. item.entry,
      dictionary.ConvertNumber(item.pattern, item.entry), item.result)
  endfor
enddef

# --- SKK-JISYO files -----------------------------------------------------
def TestJson(): void
  var lib = dictionary.Library.new(
    [Skk(testdataPath .. '/newJisyo.json', 'utf-8')], NewUser())
  Eq('newJson.ari', lib.GetHenkanResult('okuriari', 'わるs'), cases.newJson.ari)
  Eq('newJson.nasi', lib.GetHenkanResult('okurinasi', 'あかね'), cases.newJson.nasi)
enddef

def TestYaml(): void
  var lib = dictionary.Library.new(
    [Skk(testdataPath .. '/newJisyo.yaml', 'utf-8')], NewUser())
  Eq('newYaml.ari', lib.GetHenkanResult('okuriari', 'わるs'), cases.newYaml.ari)
  Eq('newYaml.nasi', lib.GetHenkanResult('okurinasi', 'あかね'), cases.newYaml.nasi)
enddef

def TestGlobal(): void
  var lib = dictionary.Library.new(
    [Skk(testdataPath .. '/globalJisyo', 'euc-jp')], NewUser())
  Eq('global.ari', lib.GetHenkanResult('okuriari', 'てすt'), cases.global.ari)
  Eq('global.nasi', lib.GetHenkanResult('okurinasi', 'てすと'), cases.global.nasi)
enddef

def TestGlobalAutoDetect(): void
  var lib = dictionary.Library.new(
    [Skk(testdataPath .. '/globalJisyo', '')], NewUser())
  Eq('globalAutoDetect.ari', lib.GetHenkanResult('okuriari', 'てすt'),
    cases.globalAutoDetect.ari)
  Eq('globalAutoDetect.nasi', lib.GetHenkanResult('okurinasi', 'てすと'),
    cases.globalAutoDetect.nasi)
enddef

def TestGlobal2(): void
  var lib = dictionary.Library.new(
    [Skk(testdataPath .. '/globalJisyo2', 'utf-8')], NewUser())
  Eq('global2.nasiI', lib.GetHenkanResult('okurinasi', 'い'), cases.global2.nasiI)
  Eq('global2.nasiTesuto', lib.GetHenkanResult('okurinasi', 'てすと'),
    cases.global2.nasiTesuto)
  Eq('global2.ariNothing', lib.GetHenkanResult('okuriari', 'てすt'),
    cases.global2.ariNothing)
  Eq('global2.empty', lib.GetHenkanResult('okurinasi', 'なにこれ'),
    cases.global2.empty)
enddef

def TestLazyLoad(): void
  var path = WriteTemp([';; okuri-nasi entries.', 'あ /あ/', ''])
  var dic = Skk(path, 'utf-8')
  delete(path)
  var thrown = ''
  try
    dic.GetHenkanResult('okurinasi', 'あ')
  catch
    thrown = v:exception
  endtry
  Truthy('lazyLoad.throws', thrown != '')
enddef

def TestNum(): void
  var dic = dictionary.WrapDictionary(Skk(testdataPath .. '/numJisyo', 'euc-jp'))
  var lib = dictionary.Library.new([dic], NewUser())
  Eq('num.ban', lib.GetHenkanResult('okurinasi', '101ばん'), cases.num.ban)
  Eq('num.kifu11', lib.GetHenkanResult('okurinasi', '11おうて'), cases.num.kifu11)
  Eq('num.kifu111', lib.GetHenkanResult('okurinasi', '111おうて'),
    cases.num.kifu111)
  Eq('num.banSmall', lib.GetHenkanResult('okurinasi', '3ばん'),
    cases.num.banSmall)
  Eq('num.completion', lib.GetCompletionResult('101ば', ''), cases.num.completion)
enddef

def TestNumIncluding(): void
  var dic = dictionary.WrapDictionary(
    Skk(testdataPath .. '/numIncludingJisyo', 'utf-8'))
  var lib = dictionary.Library.new([dic], NewUser())
  Eq('numIncluding.cat2', lib.GetHenkanResult('okurinasi', 'cat2'),
    cases.numIncluding.cat2)
  Eq('numIncluding.tokyo', lib.GetHenkanResult('okurinasi', '1000001'),
    cases.numIncluding.tokyo)
enddef

# --- completion ----------------------------------------------------------
def TestUserHenkan(): void
  var lib = dictionary.Library.new([], NewUser(testdataPath .. '/userJisyo'))
  Eq('userJisyoHenkan.nasi', lib.GetHenkanResult('okurinasi', 'ユーザー辞書'),
    cases.userJisyoHenkan.nasi)
  Eq('userJisyoHenkan.ari', lib.GetHenkanResult('okuriari', 'ユーザー辞書'),
    cases.userJisyoHenkan.ari)
  Eq('userJisyoHenkan.missing', lib.GetHenkanResult('okurinasi', 'ほげ'),
    cases.userJisyoHenkan.missing)
enddef

def TestCompletionUser(): void
  var lib = dictionary.Library.new([], NewUser(testdataPath .. '/userJisyo'))
  Eq('completionUser.oneChar', lib.GetCompletionResult('ユ', ''),
    cases.completionUser.oneChar)
  Eq('completionUser.twoChars', lib.GetCompletionResult('ユー', ''),
    cases.completionUser.twoChars)
  Eq('completionUser.full', lib.GetCompletionResult('ユーザー辞書', ''),
    cases.completionUser.full)
  Eq('completionUser.noMatch', lib.GetCompletionResult('ほ', ''),
    cases.completionUser.noMatch)
  Eq('completionUser.empty', lib.GetCompletionResult('', ''),
    cases.completionUser.empty)
enddef

def TestCompletionSkkAndUser(): void
  var lib = dictionary.Library.new(
    [Skk(testdataPath .. '/globalJisyo2', 'utf-8')],
    NewUser(testdataPath .. '/userJisyo'))
  Eq('completionSkkAndUser.tesu', lib.GetCompletionResult('てす', ''),
    cases.completionSkkAndUser.tesu)
  Eq('completionSkkAndUser.tesuFeedT', lib.GetCompletionResult('てす', 't'),
    cases.completionSkkAndUser.tesuFeedT)
  Eq('completionSkkAndUser.tesuFeedTo', lib.GetCompletionResult('てす', 'to'),
    cases.completionSkkAndUser.tesuFeedTo)
  Eq('completionSkkAndUser.tesuto', lib.GetCompletionResult('てすと', ''),
    cases.completionSkkAndUser.tesuto)
  Eq('completionSkkAndUser.i', lib.GetCompletionResult('い', ''),
    cases.completionSkkAndUser.i)
  Eq('completionSkkAndUser.iFeed', lib.GetCompletionResult('い', 'i'),
    cases.completionSkkAndUser.iFeed)
  Eq('completionSkkAndUser.userPrefix', lib.GetCompletionResult('ユ', ''),
    cases.completionSkkAndUser.userPrefix)
enddef

def TestCompletionMerge(): void
  var path = WriteTemp([
    ';; okuri-ari entries.',
    ';; okuri-nasi entries.',
    'てすと /ﾃｽﾄ/user/',
    'てす /てす/',
    '',
  ])
  var lib = dictionary.Library.new(
    [Skk(testdataPath .. '/globalJisyo2', 'utf-8')], NewUser(path))
  Eq('completionMerge.nasi', lib.GetHenkanResult('okurinasi', 'てすと'),
    cases.completionMerge.nasi)
  Eq('completionMerge.completionTesu', lib.GetCompletionResult('てす', ''),
    cases.completionMerge.completionTesu)
  Eq('completionMerge.completionTesuto', lib.GetCompletionResult('てすと', ''),
    cases.completionMerge.completionTesuto)
  Eq('completionMerge.completionFeed', lib.GetCompletionResult('てす', 't'),
    cases.completionMerge.completionFeed)
  Eq('completionMerge.ranks', lib.GetRanks('てす'), cases.completionMerge.ranks)
enddef

def TestCompletionSort(): void
  var path = WriteTemp([
    ';; okuri-ari entries.',
    ';; okuri-nasi entries.',
    'あい /愛/',
    'あいう /愛雨/',
    'ア /あ/',
    'アア /ああ/',
    'ab /ab/',
    'あ /亜/',
    'てすと /テスト/',
    'テスト /test/',
    '',
  ])
  var lib = dictionary.Library.new([Skk(path, 'utf-8')], NewUser())
  Eq('completionSort.a', lib.GetCompletionResult('あ', ''), cases.completionSort.a)
  Eq('completionSort.ai', lib.GetCompletionResult('あい', ''),
    cases.completionSort.ai)
  Eq('completionSort.a2', lib.GetCompletionResult('ア', ''),
    cases.completionSort.a2)
  Eq('completionSort.te', lib.GetCompletionResult('て', ''),
    cases.completionSort.te)
  Eq('completionSort.t', lib.GetCompletionResult('テ', ''), cases.completionSort.t)
enddef

# --- registration, ranks and persistence ---------------------------------
def TestRegister(): void
  var lib = dictionary.Library.new([], NewUser())
  lib.RegisterHenkanResult('okurinasi', 'test', 'a')
  lib.RegisterHenkanResult('okurinasi', 'test', 'b')
  Eq('register.afterB', lib.GetHenkanResult('okurinasi', 'test'),
    cases.register.afterB)
  lib.RegisterHenkanResult('okurinasi', 'test', 'a')
  Eq('register.afterA', lib.GetHenkanResult('okurinasi', 'test'),
    cases.register.afterA)
enddef

def TestInterop(): void
  var lib = dictionary.Library.new(
    [Skk(testdataPath .. '/globalJisyo', 'euc-jp')], NewUser())
  lib.RegisterHenkanResult('okurinasi', 'てすと', 'test')
  Eq('interop.afterTest', lib.GetHenkanResult('okurinasi', 'てすと'),
    cases.interop.afterTest)
  lib.RegisterHenkanResult('okurinasi', 'てすと', 'てすと')
  Eq('interop.afterTesuto', lib.GetHenkanResult('okurinasi', 'てすと'),
    cases.interop.afterTesuto)
enddef

def TestEmptyCandidate(): void
  var dic = NewUser()
  dic.RegisterHenkanResult('okurinasi', 'ほげ', '')
  dic.RegisterHenkanResult('okuriari', 'ほげ', '')
  Eq('emptyCandidate.nasi', dic.GetHenkanResult('okurinasi', 'ほげ'),
    cases.emptyCandidate.nasi)
  Eq('emptyCandidate.ari', dic.GetHenkanResult('okuriari', 'ほげ'),
    cases.emptyCandidate.ari)
enddef

def TestRanks(): void
  var dic = NewUser()
  dic.RegisterHenkanResult('okurinasi', 'ほげ', 'hoge')
  dic.RegisterHenkanResult('okurinasi', 'ぴよ', 'piyo')
  dic.RegisterHenkanResult('okurinasi', 'ほげほげ', 'hogehoge')
  var a = dic.GetRanks('ほげ')
  sort(a, (x, y) => x[1] < y[1] ? 1 : x[1] > y[1] ? -1 : 0)
  Eq('ranks.a', mapnew(a, (_, v) => v[0]), cases.ranks.a)
  dic.RegisterHenkanResult('okurinasi', 'ほげ', 'hoge')
  var b = dic.GetRanks('ほげ')
  sort(b, (x, y) => x[1] < y[1] ? 1 : x[1] > y[1] ? -1 : 0)
  Eq('ranks.b', mapnew(b, (_, v) => v[0]), cases.ranks.b)
  Eq('ranks.c', mapnew(dic.GetRanks('ぴよ'), (_, v) => v[0]), cases.ranks.c)
enddef

def TestSaveContent(): void
  var path = WriteTemp([
    '',
    ';; okuri-ari entries.',
    ';; okuri-nasi entries.',
    'あ /あ/',
    '',
  ])
  var dic = NewUser(path)
  Eq('saveContent.before', dic.GetHenkanResult('okurinasi', 'あ'),
    cases.saveContent.before)
  dic.RegisterHenkanResult('okurinasi', 'あ', '亜')
  dic.Save()
  Eq('saveContent.data', FileContent(path), cases.saveContent.data)
  var lines = readfile(path)
  var line = ''
  for candidate in lines
    if stridx(candidate, 'あ') == 0
      line = candidate
      break
    endif
  endfor
  Eq('saveContent.line', line, cases.saveContent.line)
enddef

def TestSaveSortOrder(): void
  var path = WriteTemp([
    ';; okuri-ari entries.',
    ';; okuri-nasi entries.',
    '',
  ])
  var dic = NewUser(path)
  dic.RegisterHenkanResult('okuriari', 'わるs', '悪')
  dic.RegisterHenkanResult('okuriari', 'てすt', 'テスト')
  dic.RegisterHenkanResult('okuriari', 'あs', '亜')
  dic.RegisterHenkanResult('okurinasi', 'てすと', 'テスト')
  dic.RegisterHenkanResult('okurinasi', 'あ', '亜')
  dic.RegisterHenkanResult('okurinasi', 'あ', '唖')
  dic.Save()
  Eq('saveSortOrder.data', FileContent(path), cases.saveSortOrder.data)
enddef

def TestLoadAnnotation(): void
  var path = WriteTemp([
    ';; okuri-ari entries.',
    'わるs /[わる/]悪/[わるs/]/',
    ';; okuri-nasi entries.',
    'あ /[あ/]亜/',
    '',
  ])
  var dic = NewUser(path)
  Eq('loadAnnotation.ari', dic.GetHenkanResult('okuriari', 'わるs'),
    cases.loadAnnotation.ari)
  Eq('loadAnnotation.nasi', dic.GetHenkanResult('okurinasi', 'あ'),
    cases.loadAnnotation.nasi)
  dic.Save()
  Eq('loadAnnotation.data', FileContent(path), cases.loadAnnotation.data)
enddef

def TestRankFile(): void
  var path = WriteTemp([
    ';; okuri-ari entries.',
    ';; okuri-nasi entries.',
    'ほげ /hoge/',
    'ぴよ /piyo/',
    '',
  ])
  var rankPath = WriteTemp([json_encode(['piyo', 'hoge'])])
  var dic = NewUser(path, rankPath)
  Eq('rankFile.ranks', dic.GetRanks('ほ'), cases.rankFile.ranks)
  Eq('rankFile.ranksPi', dic.GetRanks('ぴ'), cases.rankFile.ranksPi)
enddef

def TestRankFileSave(): void
  var path = WriteTemp([
    ';; okuri-ari entries.',
    ';; okuri-nasi entries.',
    '',
  ])
  var rankPath = tempname()
  var dic = NewUser(path, rankPath)
  dic.RegisterHenkanResult('okurinasi', 'ほげ', 'hoge')
  dic.RegisterHenkanResult('okurinasi', 'ぴよ', 'piyo')
  dic.RegisterHenkanResult('okurinasi', 'ほげほげ', 'hogehoge')
  dic.Save()
  Eq('rankFileSave.data', FileContent(path), cases.rankFileSave.data)
  Eq('rankFileSave.rank', join(readfile(rankPath), "\n"),
    cases.rankFileSave.rank)
enddef

def TestPurge(): void
  var path = WriteTemp([
    ';; okuri-ari entries.',
    ';; okuri-nasi entries.',
    'てすと /テスト/test/',
    '',
  ])
  var dic = NewUser(path)
  dic.PurgeCandidate('okurinasi', 'てすと', 'test')
  Eq('purge.afterOne', dic.GetHenkanResult('okurinasi', 'てすと'),
    cases.purge.afterOne)
  dic.PurgeCandidate('okurinasi', 'てすと', 'テスト')
  Eq('purge.afterAll', dic.GetHenkanResult('okurinasi', 'てすと'),
    cases.purge.afterAll)
  dic.PurgeCandidate('okurinasi', 'てすと', 'テスト')
  dic.Save()
  Eq('purge.data', FileContent(path), cases.purge.data)
enddef

def TestLibraryWithoutUserDictionary(): void
  var lib = dictionary.Library.new([], v:null)
  Eq('noUser.henkan', lib.GetHenkanResult('okurinasi', 'あ'), [])
  Eq('noUser.ranks', lib.GetRanks('あ'), [])
  Eq('noUser.completion', lib.GetCompletionResult('あ', ''), [])
  lib.RegisterHenkanResult('okurinasi', 'あ', '亜')
  lib.Save()
enddef

# --- encoded dictionaries -------------------------------------------------
def WriteEncoded(text: string, encoding: string): string
  var path = tempname()
  # Note: iconv() hands back a string holding the bytes of {encoding}; the 'b'
  #       flag of writefile() keeps them from being translated again.
  writefile([iconv(text, 'utf-8', encoding)], path, 'b')
  return path
enddef

def TestSjis(): void
  var text = join([
    ';; okuri-ari entries.',
    'てすt /テスト/',
    ';; okuri-nasi entries.',
    'あ /亜/唖/',
    'てすと /テスト/',
    '',
  ], "\n")
  var path = WriteEncoded(text, 'sjis')
  var explicit = Skk(path, 'sjis')
  Eq('sjis.explicitNasi', explicit.GetHenkanResult('okurinasi', 'あ'),
    cases.sjis.explicitNasi)
  var auto = Skk(path, '')
  Eq('sjis.autoNasi', auto.GetHenkanResult('okurinasi', 'あ'),
    cases.sjis.autoNasi)
  Eq('sjis.autoAri', auto.GetHenkanResult('okuriari', 'てすt'),
    cases.sjis.autoAri)
enddef

def TestEucMapping(): void
  # The six characters glibc's iconv() and encoding-japanese disagree on.
  # They are spelled with nr2char() because U+2016 (‖) and U+2225 (∥) look
  # alike; the input side must be the one glibc's iconv() encodes.
  var unicodeKey = nr2char(0x301c) .. nr2char(0x2016) .. nr2char(0x2212) ..
    nr2char(0x00a2) .. nr2char(0x00a3) .. nr2char(0x00ac)
  var windowsKey = nr2char(0xff5e) .. nr2char(0x2225) .. nr2char(0xff0d) ..
    nr2char(0xffe0) .. nr2char(0xffe1) .. nr2char(0xffe2)
  var path = WriteEncoded(join([
    ';; okuri-ari entries.',
    ';; okuri-nasi entries.',
    unicodeKey .. ' /x/',
    'あ /亜/',
    'い /井/',
    '',
  ], "\n"), 'euc-jp')
  var lib = dictionary.Library.new([Skk(path, 'euc-jp')], NewUser())
  Eq('eucMapping.windowsKey', lib.GetHenkanResult('okurinasi', windowsKey),
    cases.eucMapping.windowsKey)
  Eq('eucMapping.unicodeKey', lib.GetHenkanResult('okurinasi', unicodeKey),
    cases.eucMapping.unicodeKey)
  Eq('eucMapping.kana', lib.GetHenkanResult('okurinasi', 'あ'),
    cases.eucMapping.kana)
  var autoLib = dictionary.Library.new([Skk(path, '')], NewUser())
  Eq('eucMapping.autoWindowsKey',
    autoLib.GetHenkanResult('okurinasi', windowsKey),
    cases.eucMapping.autoWindowsKey)
enddef

def TestEucAuto(): void
  var lines: list<string> = [';; okuri-ari entries.', ';; okuri-nasi entries.']
  for i in range(300)
    lines->add(repeat('あ', (i % 4) + 1) .. 'い /候補' .. string(i) .. '/')
  endfor
  var path = WriteEncoded(join(lines, "\n"), 'euc-jp')
  var lib = dictionary.Library.new([Skk(path, '')], NewUser())
  Eq('eucAuto.a', lib.GetHenkanResult('okurinasi', 'あい'), cases.eucAuto.a)
  Eq('eucAuto.aa', lib.GetHenkanResult('okurinasi', 'ああい'), cases.eucAuto.aa)
  Eq('eucAuto.aaa', lib.GetHenkanResult('okurinasi', 'あああい'),
    cases.eucAuto.aaa)
enddef

# --- shared library and configuration ------------------------------------
# Note: these change config.Config, which is process global; they run last.
def TestCurrentLazy(): void
  # Building the library must not read the dictionary files; that is the whole
  # point of the lazy global dictionaries.
  config.Config.userDictionary = ''
  config.Config.completionRankFile = ''
  config.Config.globalDictionaries = [['/nonexistent/skk-dictionary-file', 'utf-8']]
  config.Config.sources = ['skk_dictionary']
  dictionary.ResetCurrent()
  var lib = dictionary.Current()
  # Note: empty() reports every class object as empty, so type() is asked.
  Truthy('currentLazy.noReadAtConstruction', type(lib) != v:t_none)
  var thrown = ''
  try
    lib.GetHenkanResult('okurinasi', 'あ')
  catch
    thrown = v:exception
  endtry
  Truthy('currentLazy.throwsOnFirstQuery', thrown != '')
  dictionary.ResetCurrent()
enddef

def TestCurrent(): void
  var userPath = WriteTemp([
    ';; okuri-ari entries.',
    ';; okuri-nasi entries.',
    '',
  ])
  config.Config.userDictionary = userPath
  config.Config.completionRankFile = ''
  config.Config.globalDictionaries = [[testdataPath .. '/globalJisyo2', 'utf-8']]
  config.Config.sources = ['skk_dictionary']
  config.Config.immediatelyDictionaryRW = true
  dictionary.ResetCurrent()
  var lib = dictionary.Current()
  Eq('current.nasi', lib.GetHenkanResult('okurinasi', 'い'), ['i'])
  Eq('current.completion', lib.GetCompletionResult('てす', 't'),
    [['てすと', ['ﾃｽﾄ']]])
  Truthy('current.singleton', dictionary.Current() is lib)
  lib.RegisterHenkanResult('okurinasi', 'てすと', 'てすと')
  Eq('current.register', lib.GetHenkanResult('okurinasi', 'てすと'),
    ['てすと', 'ﾃｽﾄ'])
  Eq('current.saved', FileContent(userPath),
    ";; okuri-ari entries.\n;; okuri-nasi entries.\nてすと /てすと/\n")
  config.Config.globalDictionaries = [[testdataPath .. '/globalJisyo', 'euc-jp']]
  var reloaded = dictionary.Current(true)
  Eq('current.reload', reloaded.GetHenkanResult('okurinasi', 'てすと'),
    ['てすと', 'テスト', 'test'])
enddef

def TestInvalidSource(): void
  var lib = dictionary.New(['bogus_source'])
  Eq('invalidSource.henkan', lib.GetHenkanResult('okurinasi', 'あ'), [])
enddef

def TestImmediateRW(): void
  var userPath = WriteTemp([
    ';; okuri-ari entries.',
    ';; okuri-nasi entries.',
  ])
  config.Config.userDictionary = userPath
  config.Config.globalDictionaries = []
  config.Config.sources = ['skk_dictionary']
  config.Config.immediatelyDictionaryRW = false
  dictionary.ResetCurrent()
  var lib = dictionary.Current()
  lib.RegisterHenkanResult('okurinasi', 'あ', '亜')
  Eq('immediateRW.notSaved', FileContent(userPath),
    ";; okuri-ari entries.\n;; okuri-nasi entries.\n")
  lib.Save()
  Eq('immediateRW.saved', FileContent(userPath),
    ";; okuri-ari entries.\n;; okuri-nasi entries.\nあ /亜/\n")
enddef

# --- run -----------------------------------------------------------------
TestNumbers()
TestJson()
TestYaml()
TestGlobal()
TestGlobalAutoDetect()
TestGlobal2()
TestLazyLoad()
TestNum()
TestNumIncluding()
TestUserHenkan()
TestCompletionUser()
TestCompletionSkkAndUser()
TestCompletionMerge()
TestCompletionSort()
TestRegister()
TestInterop()
TestEmptyCandidate()
TestRanks()
TestSaveContent()
TestSaveSortOrder()
TestLoadAnnotation()
TestRankFile()
TestRankFileSave()
TestPurge()
TestLibraryWithoutUserDictionary()
TestSjis()
TestEucMapping()
TestEucAuto()
TestCurrentLazy()
TestCurrent()
TestInvalidSource()
TestImmediateRW()

var lines: list<string> = []
lines += failures
lines->add(printf('checked %d, failed %d', checks, len(failures)))
writefile(lines, root .. '/test/actual/dictionary.txt')
qa!
