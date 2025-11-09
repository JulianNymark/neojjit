" Syntax highlighting for neojjit status buffer

if exists("b:current_syntax")
  finish
endif

" Headers and sections
syntax match NeojjitHint "^Hint:.*$"
syntax match NeojjitHeader "^Working copy:.*$"
syntax match NeojjitSectionHeader "^Changes\s\+(\d\+)$"

" File status indicators
syntax match NeojjitFileAdded "^added\s\+" nextgroup=NeojjitFilename
syntax match NeojjitFileModified "^modified\s\+" nextgroup=NeojjitFilename
syntax match NeojjitFileDeleted "^deleted\s\+" nextgroup=NeojjitFilename
syntax match NeojjitFilename "\S\+$"

" Diff content (for inline diffs)
syntax match NeojjitDiffAdd "^+.*$"
syntax match NeojjitDiffDelete "^-.*$"
syntax match NeojjitDiffHeader "^@@.*@@.*$"

" Change and commit IDs
syntax match NeojjitChangeId "\x\{8\}"

" Highlight links
highlight default link NeojjitHint Comment
highlight default link NeojjitHeader Title
highlight default link NeojjitSectionHeader Statement

highlight default link NeojjitFileAdded DiffAdd
highlight default link NeojjitFileModified DiffChange
highlight default link NeojjitFileDeleted DiffDelete
highlight default link NeojjitFilename Normal

highlight default link NeojjitDiffAdd DiffAdd
highlight default link NeojjitDiffDelete DiffDelete
highlight default link NeojjitDiffHeader PreProc

highlight default link NeojjitChangeId Identifier

let b:current_syntax = "neojjit"
