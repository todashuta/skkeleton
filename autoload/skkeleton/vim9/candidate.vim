vim9script
# Candidate annotation handling, ported from denops/skkeleton/candidate.ts.

# Strip the annotation from {candidate} and the affix marker the reading asked
# for.
#
# A candidate in the dictionary is "word;annotation", and a reading marked with
# a leading or trailing ">" wants that marker taken off the candidate.
export def ModifyCandidate(candidate: string, affix: string): string
  if candidate == ''
    return ''
  endif
  var separator = stridx(candidate, ';')
  var candidateStrip = separator == -1 ? candidate : strpart(candidate, 0, separator)
  if affix == 'prefix'
    return substitute(candidateStrip, '>$', '', '')
  elseif affix == 'suffix'
    return substitute(candidateStrip, '^>', '', '')
  endif
  return candidateStrip
enddef
