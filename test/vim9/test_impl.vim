vim9script
import '../../autoload/skkeleton/vim9/context.vim' as context_mod
import '../../autoload/skkeleton/vim9/config.vim' as config_mod
import '../../autoload/skkeleton/vim9/dictionary.vim' as dictionary_mod

# Diffs the Vim9 script implementation against the states the TypeScript one
# produced (test/vim9/expected.json, made by tools/gen/gen_expected.ts).
#
# The keys go through the same dispatch the TypeScript tests use: the real key
# mapping needs a notation table and a buffer, neither of which this is about.

var here = expand('<sfile>:p:h')
var root = fnamemodify(here, ':h:h')
execute 'set runtimepath^=' .. fnameescape(root)
runtime! plugin/skkeleton.vim

# Note: nothing is written to disk; only what is learned in memory matters.
#       A member of an imported variable cannot be assigned at script level in
#       Vim9 script, hence the def.
def Configure(): void
  config_mod.Config.userDictionary = ''
  config_mod.Config.completionRankFile = ''
  config_mod.Config.globalDictionaries = []
enddef
Configure()

var expected = json_decode(join(readfile(here .. '/expected.json'), "\n"))

var lib = dictionary_mod.Current()
for entry in expected.dictionary
  lib.RegisterHenkanResult(entry[0], entry[1], entry[2])
endfor

def Dispatch(context: any, key: string)
  if context.state.type == 'input'
    if key == ' '
      skkeleton#vim9#function#henkan#HenkanFirst(context, key)
    elseif key == ';'
      skkeleton#vim9#function#input#HenkanPoint(context)
    elseif key == "\n"
      skkeleton#vim9#function#common#Newline(context)
    else
      skkeleton#vim9#function#input#KanaInput(context, key)
    endif
  elseif context.state.type == 'henkan'
    if key == ' '
      skkeleton#vim9#function#henkan#HenkanForward(context)
    elseif key == 'x'
      skkeleton#vim9#function#henkan#HenkanBackward(context)
    elseif key == "\n"
      skkeleton#vim9#function#common#Newline(context)
    endif
  endif
enddef

var failures: list<string> = []
for c in expected.cases
  var context = context_mod.Context.new()
  var steps: list<string> = []
  for key in split(c.keys, '\zs')
    Dispatch(context, key)
    steps->add(context.ToString())
  endfor
  var output = context.preEdit.Output('')
  if steps != c.steps
    failures->add(printf('keys %s: steps %s expected %s',
      string(c.keys), string(steps), string(c.steps)))
  endif
  if output !=# c.output
    failures->add(printf('keys %s: output %s expected %s',
      string(c.keys), string(output), string(c.output)))
  endif
endfor

var result: list<string> = []
result->add(printf('%d cases, %d failures', len(expected.cases), len(failures)))
result += failures
writefile(result, here .. '/actual.txt')
if !empty(failures)
  cquit 1
endif
qa!
