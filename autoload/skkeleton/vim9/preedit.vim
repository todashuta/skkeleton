vim9script
# Simulated IME pre-edit, ported from denops/skkeleton/preedit.ts.
#
# Vim has no pre-edit of its own on the buffer side, so skkeleton writes the
# text itself and deletes it again before writing the next one.  This keeps
# track of what is on screen and of what a key handling has decided to write
# but has not sent back yet.

import './util.vim' as util

export class PreEdit
  # what the buffer holds now
  var current: string = ''
  # what this key handling has written but Vim has not received yet
  var kakutei: string = ''

  # Whether the key handling has written something Vim has not seen.
  #
  # Note: a key can confirm a candidate and then type on; the reading on screen
  #       is then ahead of the buffer until Vim applies the result.
  def IsDirty(): bool
    return this.kakutei != ''
  enddef

  def DoKakutei(str: string): void
    this.kakutei ..= str
  enddef

  # Return the keys which turn what is on screen into {next}.
  def Output(next: string): string
    var ret: string
    # Note: a completion menu flickers when the pre-edit is deleted and written
    #       again for nothing, so only the difference is sent when {next}
    #       extends what is already there.
    if this.kakutei == '' && stridx(next, this.current) == 0
      ret = strpart(next, strlen(this.current))
    else
      ret = repeat("\b", util.GraphemeLength(this.current)) .. this.kakutei .. next
    endif
    this.current = next
    this.kakutei = ''
    return ret
  enddef
endclass
