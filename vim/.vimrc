" --------------
" general
" --------------
" Show absolute line numbers in the gutter
set number
" Don't create .swp swap files
set noswapfile
" Highlight the line the cursor is on
set cursorline
" Use Vim defaults instead of legacy vi compatibility
set nocompatible
" Show cursor line/column position in the status area
set ruler
" Wrap long lines at word boundaries, not mid-word
set linebreak
" Let backspace delete past indent, line breaks, and insert start
set backspace=indent,eol,start
" Keep 5 lines of context above/below the cursor
set scrolloff=5


" --------------
" modify
" --------------
" cc: change from first non-blank to end of line
nnoremap cc ^c$


" --------------
" window
" --------------
" Ctrl-w |  : split window vertically
nnoremap <C-w>\| <C-w>v
" Ctrl-w -  : split window horizontally
nnoremap <C-w>- <C-w>s


" --------------
" scroll
" --------------
" set scroll=5
" zt: scroll cursor line near top, leaving 3 lines above
nnoremap zt zt3<C-y>
" Ctrl-j: move down one line and scroll view with it
nnoremap <C-j> j<C-e>
" Ctrl-k: move up one line and scroll view with it
nnoremap <C-k> k<C-y>
" Same down-scroll in visual mode
vnoremap <C-j> j<C-e>
" Same up-scroll in visual mode
vnoremap <C-k> k<C-y>
" Ctrl-d: move down 10 lines and scroll view 10
nnoremap <C-d> 10j10<C-e>
" Ctrl-u: move up 10 lines and scroll view 10
nnoremap <C-u> 10k10<C-y>
" nnoremap zz zt10<C-y>

" --------------
" search
" --------------
" Highlight all matches of the last search
set hlsearch
" Show matches incrementally as you type
set incsearch
" set ignorecase
" set smartcase
" Searches are case-sensitive
set noignorecase
" Treat most regex metacharacters as literal in patterns
set nomagic
" *: search word under cursor but stay on current match
nnoremap * *N
" n: next match and center the screen
nnoremap n nzz
" N: previous match and center the screen
nnoremap N Nzz
" Visual *: search for the exact selected text (escaped as a very-nomagic literal)
vnoremap * y/\V<C-R>=substitute(substitute(trim(@0), '\\', '\\\\', 'g'), '\n', '\\n', 'g')<CR><CR>
" nnoremap ' `
" ': jump to a mark and center the screen
nnoremap <expr> ' "`".nr2char(getchar()).'zz'
" Ctrl-l: clear search highlight and redraw
nnoremap <silent> <C-l> :<C-u>nohlsearch<CR><C-l>


" --------------
" tab indent
" --------------
" Copy indentation from the previous line
set autoindent
" Add extra indent after blocks (e.g. after {)
set smartindent
" Insert spaces instead of tab characters
set expandtab
" A tab counts as 2 columns wide
set tabstop=2
" Auto-indent and >> / << use 2 spaces
set shiftwidth=2


" --------------
" show
" --------------
" Wrap long lines onto the next screen row
set wrap
" Always show the status line
set laststatus=2
" Tune colors for a dark background
set background=dark
" Don't print -- INSERT -- (status line shows it)
set noshowmode


" --------------
" new tab
" --------------
" Always show the tab line
set showtabline=2
" Horizontal splits open below the current window
set splitbelow
" Vertical splits open to the right
set splitright


" --------------
" copy and paste
" --------------
" Pasting over a visual selection normally deletes the selection INTO the
" unnamed register first, clobbering what you yanked -- so a second paste puts
" the just-deleted text instead of your original yank. Vim >= 8.2.0693 fixes
" this with visual P, but this build is older. So we save the unnamed register,
" do a normal paste over the selection, then put the saved text back -- letting
" you paste one yank over many selections in a row. (A short alternative is
" `xnoremap p "_dP`, but that jams spacing on charwise end-of-line pastes.)
function! s:VisualPasteKeepReg()
  let l:save = [getreg('"'), getregtype('"')]
  normal! gvp
  call setreg('"', l:save[0], l:save[1])
endfunction
xnoremap <silent> p :<C-u>call <SID>VisualPasteKeepReg()<CR>

" This Vim is built with -clipboard/-X11 (check :version) and we run over SSH
" inside tmux, so the * / + registers connect to nothing and `set clipboard`
" is a no-op. Instead we push yanks to the LOCAL machine's clipboard with an
" OSC 52 escape sequence: Vim -> tmux -> ssh -> local terminal -> OS clipboard.
" Requires: tmux `set-clipboard on` (it is) and a terminal that honors OSC 52
" (iTerm2, WezTerm, kitty, Alacritty, Windows Terminal, recent macOS Terminal).

" Send a string to the system clipboard via OSC 52 (base64-encoded payload).
function! s:Osc52Copy(text) abort
  let l:b64 = substitute(system('base64 | tr -d "\n"', a:text), '\n', '', 'g')
  let l:seq = "\033]52;c;" . l:b64 . "\007"
  " Inside tmux, wrap the sequence in a DCS passthrough so tmux forwards it.
  if !empty($TMUX)
    let l:seq = "\033Ptmux;\033" . l:seq . "\033\\"
  endif
  " Write straight to the controlling terminal so it works even when Vim's
  " stdout is redirected; fall back to writing to the terminal otherwise.
  silent! call writefile([l:seq], '/dev/tty', 'b')
endfunction

" Auto-mirror real yanks (y / yy / Y) to the local clipboard. Deletes and
" changes are excluded so the clipboard isn't clobbered by editing.
if exists('##TextYankPost')
  augroup osc52_yank
    autocmd!
    autocmd TextYankPost *
          \ if v:event.operator ==# 'y' && v:event.regname ==# '' |
          \   call s:Osc52Copy(join(v:event.regcontents, "\n")) |
          \ endif
  augroup END
endif


" --------------
" filetype
" --------------
" Enable syntax highlighting
syntax on
" Detect the file type
filetype on
" Load filetype-specific plugins
filetype plugin on
" Load filetype-specific indent rules
filetype indent on
" Enable 24-bit (true color) foreground
let &t_8f = "\<Esc>[38;2;%lu;%lu;%lum"
" Enable 24-bit (true color) background
let &t_8b = "\<Esc>[48;2;%lu;%lu;%lum"
" t_8f/t_8b alone do nothing: 'termguicolors' is what switches Vim to 24-bit color
if has('termguicolors')
  set termguicolors
endif


" --------------
" mouse
" --------------
" Enable the mouse in all modes
set mouse=a
" Selection does not include the character under the cursor
set selection=exclusive
" Enter Select mode via mouse drag or shifted keys
set selectmode=mouse,key


" --------------
" ignore
" --------------


" --------------
" leader
" --------------
" Use Space as the <leader> key
let mapleader = " "
" <leader>d: delete without overwriting the yank register
nnoremap <leader>d "_d
" <leader>c: change without overwriting the yank register
nnoremap <leader>c "_c
" <leader>x: delete char without overwriting the yank register
nnoremap <leader>x "_x
" Same black-hole delete in visual mode
vnoremap <leader>d "_d
" Same black-hole change in visual mode
vnoremap <leader>c "_c
" Same black-hole delete in visual mode
vnoremap <leader>x "_x


" --------------
" autocmd
" --------------
" Strip trailing whitespace on save while preserving cursor/search state
function! s:StripTrailingWhitespace()
  let l:save = winsaveview()
  keeppatterns %s/\s\+$//e
  call winrestview(l:save)
endfunction

augroup my_autocmds
  autocmd!
  " Highlight cursor line in the focused window
  autocmd WinEnter * setlocal cursorline
  " Remove the highlight from unfocused windows
  autocmd WinLeave * setlocal nocursorline
  " Clean trailing spaces before writing
  autocmd BufWritePre * call s:StripTrailingWhitespace()
augroup END


" --------------
" Cursor settings
" --------------
" NORMAL  █
let &t_EI = "\033[1 q"
" INSERT  |
let &t_SI = "\033[5 q"


"--------------
" performance
"--------------
" Don't redraw screen during macros (faster)
set lazyredraw
" Faster terminal connection
set ttyfast
" Faster completion (default is 4000ms)
set updatetime=300
" Faster key sequence completion
set timeoutlen=500


" --------------
" plugin
" --------------
call plug#begin()
	Plug 'tpope/vim-surround'
	Plug 'tpope/vim-repeat'
	Plug 'jiangmiao/auto-pairs'
  Plug 'wellle/targets.vim'
  Plug 'inkarkat/vim-ReplaceWithRegister'
  Plug 'junegunn/fzf', { 'do': { -> fzf#install() } }
  Plug 'junegunn/fzf.vim'
  Plug 'justinmk/vim-sneak'
call plug#end()


" --------------
" sneak.vim
" --------------
" Show label mode: tags matches with letters so you can jump directly
let g:sneak#label = 1


" --------------
" fzf.vim
" --------------
" Centered floating popup, 90% x 70% of the screen
let g:fzf_layout = { 'window': { 'width': 0.9, 'height': 0.7, 'border': 'rounded' } }
" Preview pane on the right, 50% wide; toggle it with Ctrl-/
let g:fzf_preview_window = ['right,50%', 'ctrl-/']
" Open the picked file in a tab / split / vsplit
let g:fzf_action = {
  \ 'ctrl-t': 'tab split',
  \ 'ctrl-x': 'split',
  \ 'ctrl-v': 'vsplit' }
" Skip the filename column in :Rg so fzf only fuzzy-matches the match text
" (paths still appear in the results, they just aren't part of the query).
command! -bang -nargs=* Rg
  \ call fzf#vim#grep(
  \   'rg --column --line-number --no-heading --color=always --smart-case -- '.shellescape(<q-args>),
  \   1, fzf#vim#with_preview({'options': '--delimiter : --nth 4..'}), <bang>0)

" <leader>f : fuzzy-find files under CWD (respects .gitignore if inside a repo)
nnoremap <leader>f :Files<CR>
" <leader>F : same, but seed the query with the word under the cursor
nnoremap <leader>F :Files <C-r><C-w><CR>
" <leader>b : pick from open buffers
nnoremap <leader>b :Buffers<CR>
" <leader>r : ripgrep across the project (needs rg installed)
nnoremap <leader>r :Rg<CR>
" <leader>R : ripgrep, seeded with the word under the cursor
nnoremap <leader>R :Rg <C-r><C-w><CR>
" <leader>l : fuzzy-search lines in the current buffer
nnoremap <leader>l :BLines<CR>
" <leader>L : fuzzy-search lines across all loaded buffers
nnoremap <leader>L :Lines<CR>
" <leader>h : recently opened files (MRU)
nnoremap <leader>h :History<CR>
" <leader>/ : recent search patterns
nnoremap <leader>/ :History/<CR>
" <leader>; : recent Ex commands
nnoremap <leader>; :History:<CR>
" <leader>gc : git commits reachable from HEAD
nnoremap <leader>gc :Commits<CR>
" <leader>gf : git-tracked files
nnoremap <leader>gf :GFiles<CR>
" <leader>gs : git status (staged / unstaged files)
nnoremap <leader>gs :GFiles?<CR>
" <leader>m  : marks
nnoremap <leader>m :Marks<CR>
" <leader>t  : ctags in the current buffer (requires ctags)
nnoremap <leader>t :BTags<CR>
" <leader>T  : ctags across the project
nnoremap <leader>T :Tags<CR>


" --------------
" end
" --------------
