" Vim syntax file
" Language:     Limbo
" Maintainer:   Alex Efros <powerman-asdf@ya.ru>
" Version:	0.5
" Updated:      2008-10-17

" Remove any old syntax stuff that was loaded (5.x) or quit when a syntax file
" was already loaded (6.x).
if version < 600
  syntax clear
elseif exists("b:current_syntax")
  finish
endif

syn keyword	lTodo		TODO TBD FIXME XXX BUG contained
syn match	lComment	"#.*" contains=@Spell,lTodo

syn keyword	lInclude	include

syn match	lSpecialChar	display contained "\\\(u\x\{4}\|['\"\\tnrbavf0]\)"
syn match	lSpecialError	display contained "\(\\[^'\"\\tnrbavf0u]\+\|\\u.\{0,3}\X\)"
syn match	lCharError	display contained "\([^\\'][^']\+\|\\[^'][^']\+\)"
syn region	lString		start=+"+ end=+"+ skip=+\\"+ contains=@Spell,lSpecialChar,lSpecialError
syn region	lCharacter	start=+'+ end=+'+ skip=+\\'+ contains=lSpecialChar,lSpecialError,lCharError

syn keyword	lSpecial	nil iota

syn keyword	lFunction	tl hd len tagof
syn match	lFunction	"<-=\?"

syn keyword	lStatement	alt break continue exit return spawn implement import load raise
syn keyword 	lRepeat		for while do
syn keyword	lConditional	if else case 

syn keyword	lType		array big byte chan con int list real string fn fixed
syn keyword	lStructure	adt pick module
syn keyword	lStorageClass	ref self cyclic type of

syn keyword	lDelimiter	or to
syn match	lDelimiter	"=>\|->\|\.\|::"


if version >= 508 || !exists("did_icgiperl_syn_inits")
  if version < 508
    let did_icgiperl_syn_inits = 1
    command -nargs=+ HiLink hi link <args>
  else
    command -nargs=+ HiLink hi def link <args>
  endif

    " Comment
    HiLink lComment         Comment

    " PreProc (Include, PreCondit)
    HiLink lInclude         Include

    " Constant (String, Character, Number, Boolean, Float)
    HiLink lString          String
    HiLink lCharacter       Character

    " Special (Tag, SpecialChar, SpecialComment, Debug)
    HiLink lSpecial	    Special
    HiLink lSpecialChar     SpecialChar

    " Identifier (Function)
    HiLink lFunction        Function

    " Statement (Conditional, Repeat, Label, Operator, Keyword, Exception)
    HiLink lStatement       Statement
    HiLink lRepeat          Repeat
    HiLink lConditional     Conditional

    " Type (StorageClass, Structure, Typedef)
    HiLink lType            Type
    HiLink lStructure       Structure
    HiLink lStorageClass    StorageClass

    " Error
    HiLink lSpecialError    Error
    HiLink lCharError	    Error

    " Todo
    HiLink lTodo	    Todo

    " Delimiter
    HiLink lDelimiter	    Delimiter

  delcommand HiLink
endif


let b:current_syntax = "limbo"
