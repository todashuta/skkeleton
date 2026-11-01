vim9script
# Helpers shared by the Vim9 script implementation of skkeleton.
#
# Ported from denops/skkeleton/util.ts and config.ts.  The TypeScript version
# runs inside Deno, so it has TextEncoder, Intl.Segmenter and the File API;
# Vim9 script has strlen(), strchars() and readfile() instead and they count
# things differently enough to deserve a named wrapper each.

# Number of backspaces needed to delete {str}.
#
# Note: the TypeScript version uses Intl.Segmenter("ja") and counts grapheme
#       clusters.  Vim has no grapheme cluster iterator, so this leans on
#       strchars() with skipcc=1, which counts a base character and its
#       composing marks as one.  A pre-edit only ever holds kana, kanji and
#       ASCII, where the two agree.  Not using strlen() here: that counts
#       bytes and one backspace deletes one character, not one byte.
export def GraphemeLength(str: string): number
  return strchars(str, 1)
enddef

# Byte length, the way Vim counts columns.
export def ByteLength(str: string): number
  return strlen(str)
enddef

var home: string = ''
var homeResolved: bool = false

# Expand a leading "~" the way the TypeScript version does.
#
# Note: expand('~') is asked once and remembered because it shows up in the
#       path of every dictionary to be read and expand() is not free.
export def HomeExpand(path: string): string
  if path == '' || path[0] != '~'
    return path
  endif
  if !homeResolved
    home = expand('~')
    homeResolved = true
  endif
  return home .. strpart(path, 1)
enddef

# Read a file and return its text decoded to UTF-8.
#
# Note: readfile() with the 'b' flag hands back the raw bytes and iconv()
#       turns them into the internal encoding, which keeps the EUC-JP and
#       Shift_JIS dictionaries people actually have working without a BOM or
#       a 'fileencoding' guess.
export def ReadFileWithEncoding(path: string, encodingName: string): string
  var lines = readfile(path, 'b')
  var data = join(lines, "\n")
  var encoding = encodingName == '' ? DetectEncoding(data) : encodingName
  if encoding == ''
    return data
  endif
  return iconv(data, encoding, 'utf-8')
enddef

# Guess the encoding of {data} from the bytes alone, or '' for UTF-8.
#
# Note: the TypeScript version asks encoding-japanese.  Vim has no such
#       detector, so this leans on what Vim does with a byte string it cannot
#       decode: a byte of a multibyte sequence that is not valid UTF-8 is kept
#       as a code point in 0x80-0xFF.  A real UTF-8 text only lands there if it
#       holds Latin-1 supplement characters, which a dictionary does not.
#       'euc-jp' is tried before 'shift_jis' because EUC-JP is what SKK
#       dictionaries are distributed in.
export def DetectEncoding(data: string): string
  if IsValidUtf8(data)
    return ''
  endif
  for encoding in ['euc-jp', 'shift_jis']
    if IsValidUtf8(iconv(data, encoding, 'utf-8'))
      return encoding
    endif
  endfor
  return ''
enddef

# Whether {str} decodes as UTF-8.
#
# Note: iconv(str, 'utf-8', 'utf-8') cannot be asked this: Vim lets the bytes
#       through unchanged instead of failing on them.
def IsValidUtf8(str: string): bool
  return empty(str->str2list()->filter((_, c: number) => c >= 0x80 && c <= 0xFF))
enddef
