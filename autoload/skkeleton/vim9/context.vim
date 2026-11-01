vim9script
# The per-buffer editing context, ported from denops/skeleton/context.ts.
#
# It holds what skkeleton needs to keep between key handlings: the state, the
# simulated pre-edit and, for |skkeleton-functions-kakuteiUndo|, the kakutei
# that may still be taken back.

import './config.vim' as config
import './preedit.vim' as preedit
import './state.vim' as state_mod
import './util.vim' as util

# Whether {str} ends with {suffix}.
#
# Note: Vim9 script has no endsWith(), and strpart() at a negative index means
#       something else, so the length has to be checked first.
def EndsWith(str: string, suffix: string): bool
  var length = strlen(suffix)
  return strlen(str) >= length && strpart(str, strlen(str) - length) ==# suffix
enddef

export class Context
  var state: dict<any> = {}
  # g:skkeleton#mode copy, set on every mode change
  var mode: string = 'hira'
  var preEdit: any = 0
  var vimMode: string = ''
  # where Vim is at the current key handling, received on every handle()
  var prevInput: string = ''
  var bufnr: number = -1
  var lnum: number = -1
  var lastCandidate: dict<any> = {}
  var lastKakutei: dict<any> = {}
  var pendingKakutei: dict<any> = {}
  var rememberedPoint: dict<any> = {}
  # where Vim has to put the cursor once it has applied the output of this key
  # handling, or an empty dict for leaving it where the output ends
  var restorePoint: dict<any> = {}

  def new()
    this.state = state_mod.NewInputState()
    this.preEdit = preedit.PreEdit.new()
    this.lastCandidate = {type: 'okurinasi', word: '', candidate: ''}
  enddef

  # Vim9 script only lets a class write its own variables, so the callers that
  # have to set one go through these.
  def SetStatus(vimMode: string, prevInput: string, bufnr: number, lnum: number): void
    this.vimMode = vimMode
    this.prevInput = prevInput
    this.bufnr = bufnr
    this.lnum = lnum
  enddef

  def SetRestorePoint(point: dict<any>): void
    this.restorePoint = point
  enddef

  def SetLastCandidate(candidate: dict<any>): void
    this.lastCandidate = candidate
  enddef

  def SetState(newState: dict<any>): void
    this.state = newState
  enddef

  def SetMode(mode: string): void
    this.mode = mode
  enddef

  # Remember where the cursor is standing, before kakuteiUndo() walks it back
  # to the kakutei it is about to delete.
  def RecordPointRestore(kakutei: string, bufferText: string): void
    var col = util.ByteLength(this.prevInput) + 1
    # Note: the cursor was inside the kakutei, so the column it was at means
    #       nothing once something of another length has replaced it.
    if col >= util.ByteLength(bufferText) + 1
      this.rememberedPoint = {
        lnum: this.lnum,
        col: col,
        bytes: util.ByteLength(kakutei),
      }
    else
      this.rememberedPoint = {}
    endif
  enddef

  # The byte column to put the cursor back at, now that {kakutei} is what has
  # been written where the undo walked away from, or an empty dict when there
  # is nothing to put back.
  #
  # The column is shifted by however much longer or shorter {kakutei} is than
  # what was taken back, so the cursor keeps its place in the text.  An undo
  # which never moved the cursor gives the column the kakutei ends at anyway,
  # so nothing visibly happens for it.
  def UsePointRestore(kakutei: string): dict<any>
    var restore = this.rememberedPoint
    this.rememberedPoint = {}
    if empty(restore)
      return {}
    endif
    return {
      lnum: restore.lnum,
      col: restore.col + util.ByteLength(kakutei) - restore.bytes,
    }
  enddef

  # Give up on putting the cursor back.
  #
  # Called once skkeleton has nothing pending where the undo happened: the
  # reading may have been taken all the way back with cancel, or skkeleton
  # disabled, and a column remembered for a spot nobody is editing any more
  # would move the cursor on some unrelated kakutei later on.
  def ForgetPointRestore(): void
    this.rememberedPoint = {}
  enddef

  # Whether skkeleton is still writing where the undo left off: a henkan, a
  # reading being typed, or a pre-edit waiting to become one.
  def HasPendingInput(): bool
    var state = this.state
    return state.type != 'input' || state.mode != 'direct' ||
      state.feed != '' || this.preEdit.current != ''
  enddef

  # Remember a kakutei so that |skkeleton-functions-kakuteiUndo| can take it
  # back.
  #
  # The buffer is only written after this key handling has returned, hence the
  # recording is completed at the next one.
  def RecordKakutei(kakuteiType: string, kakutei: string, henkanState: dict<any>): void
    this.lastKakutei = {}
    this.pendingKakutei = {
      type: kakuteiType,
      kakutei: kakutei,
      state: henkanState,
      mode: this.mode,
      vimMode: this.vimMode,
      bufnr: this.bufnr,
      lnum: this.lnum,
      tail: '',
    }
  enddef

  # Forget the last kakutei because it can no longer be taken back.
  def InvalidateKakutei(): void
    this.lastKakutei = {}
    this.pendingKakutei = {}
  enddef

  # Complete the kakutei recorded at the previous key handling.
  #
  # prevInput has just been received from Vim, so it tells where the kakutei has
  # left the cursor.  Returns whether the buffer has been rewritten by a kakutei
  # skkeleton knows about, which is what explains a mismatch against the
  # pre-edit.
  def ResolvePendingKakutei(): bool
    var pending = this.pendingKakutei
    if empty(pending)
      return false
    endif
    this.pendingKakutei = {}
    if !this.IsAt(pending)
      return false
    endif
    # Note: what the key handling has left behind the kakutei is not a part of
    #       it: the input of the key which has confirmed a candidate by typing
    #       on, and the pre-edit it has started.
    #       It is not stripped when it is not found in the buffer, which is the
    #       case for a completion: the engine has rewritten the buffer and the
    #       pre-edit skkeleton remembers is a stale one.
    var tail = pending.tail .. this.preEdit.current
    var bufferText = this.prevInput
    if tail != '' && EndsWith(this.prevInput, tail)
      bufferText = strpart(this.prevInput, 0, strlen(this.prevInput) - strlen(tail))
    endif
    if !EndsWith(bufferText, pending.kakutei)
      return false
    endif
    var last = copy(pending)
    last.bufferText = bufferText
    this.lastKakutei = last
    return true
  enddef

  # The kakutei which can be taken back right now, if any.
  #
  # Note: that the confirmed string is still in the buffer is not decided here.
  #       The cursor may have moved on since the kakutei, and only Vim knows
  #       what the line looks like beyond it, so kakuteiUndo() asks before it
  #       deletes anything.
  def TakeBackableKakutei(): dict<any>
    var last = this.lastKakutei
    if empty(last) || !this.IsAt(last) ||
        # Note: a key handled before this one within the same handling has
        #       written to the buffer already, which prevInput cannot know yet.
        this.preEdit.IsDirty()
      return {}
    endif
    return last
  enddef

  # Whether the cursor is right after the last kakutei, which is where the undo
  # can delete it without moving anything.
  def IsRightAfterKakutei(last: dict<any>): bool
    return this.prevInput ==# last.bufferText
  enddef

  # Whether Vim is still where the kakutei has happened.
  def IsAt(at: dict<any>): bool
    return this.vimMode ==# at.vimMode && this.bufnr == at.bufnr &&
      this.lnum == at.lnum
  enddef

  def Kakutei(str: string): void
    # Remember what the rest of this key handling writes behind a kakutei it
    # has just recorded.
    if !empty(this.pendingKakutei)
      this.pendingKakutei.tail ..= str
    endif
    this.preEdit.DoKakutei(str)
  enddef

  def KakuteiWithUndoPoint(str: string): void
    var text = str
    if config.Config.setUndoPoint && this.vimMode == 'i'
      text ..= "\<C-g>u"
    endif
    this.preEdit.DoKakutei(text)
  enddef

  def ToString(): string
    return state_mod.ToString(this.state)
  enddef
endclass
