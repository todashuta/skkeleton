vim9script
# Building complete items for Vim's completion menu, ported from
# denops/skeleton/completion.ts.

import './okuri.vim' as okuri

# The first ";" opens the annotation of a candidate.
def SplitAnnotation(word: string): list<string>
  var i = stridx(word, ';')
  if i < 0
    return [word, '']
  endif
  return [strpart(word, 0, i), strpart(word, i + 1)]
enddef

def UserData(metadata: dict<any>): string
  return json_encode(metadata)
enddef

export def BuildOkurinasiCompleteItems(
  candidates: list<list<any>>, rankData: list<list<any>>): list<dict<any>>
  var ranks: dict<number> = {}
  for entry in rankData
    ranks[entry[0]] = entry[1]
  endfor
  var sortedCandidates = copy(candidates)
  # Note: Vim sorts in place, and the caller's list must not be reordered.
  sort(sortedCandidates, (a, b) =>
    a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0)
  var globalRank = -1
  var items: list<dict<any>> = []
  for entry in sortedCandidates
    var kana = entry[0]
    for word in entry[1]
      var parts = SplitAnnotation(word)
      var rank: number
      if has_key(ranks, word)
        rank = ranks[word]
      else
        # Note: candidates nobody has picked yet keep the dictionary order;
        #       they are ranked below every known one by counting down.
        globalRank -= 1
        rank = globalRank
      endif
      items->add({
        word: parts[0],
        abbr: parts[0],
        info: parts[1],
        equal: 1,
        dup: 1,
        empty: 1,
        user_data: UserData({
          tag: 'skkeleton',
          midasi: kana,
          word: word,
          type: 'okurinasi',
        }),
        rank: rank,
      })
    endfor
  endfor
  sort(items, (a, b) => b.rank - a.rank)
  for item in items
    remove(item, 'rank')
  endfor
  return items
enddef

export def BuildOkuriariCompleteItems(
  kana: string, GetCandidates: func): list[dict<any>>
  var chunks = okuri.OkuriSplits(kana)
  var cache: dict<list<string>> = {}
  var items: list[dict<any>> = []
  for chunk in chunks
    var midasi = okuri.GetOkuriStr(chunk[0], chunk[1])
    var candidates: list<string>
    if has_key(cache, midasi)
      candidates = cache[midasi]
    else
      candidates = call(GetCandidates, [midasi])
      cache[midasi] = candidates
    endif
    for candidate in candidates
      var parts = SplitAnnotation(candidate)
      items->add({
        word: parts[0] .. chunk[1],
        abbr: parts[0] .. chunk[1],
        info: parts[1],
        equal: 1,
        dup: 1,
        empty: 1,
        user_data: UserData({
          tag: 'skkeleton',
          midasi: midasi,
          word: candidate,
          type: 'okuriari',
        }),
      })
    endfor
  endfor
  return items
enddef

export def BuildCompleteItems(
  candidates: list<list<any>>,
  rankData: list<list<any>>,
  kana: string,
  GetOkuriariCandidates: func): list<dict<any>>
  return BuildOkurinasiCompleteItems(candidates, rankData) +
    BuildOkuriariCompleteItems(kana, GetOkuriariCandidates)
enddef
