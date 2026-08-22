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
" Yank/paste through the system clipboard (* register)
set clipboard=unnamed


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
" call plug#begin()
" 	Plug 'preservim/NERDTree'
" 	Plug 'vim-airline/vim-airline'
" 	Plug 'ctrlpvim/ctrlp.vim'
" 	Plug 'tpope/vim-surround'
" 	Plug 'tpope/vim-repeat'
" 	Plug 'tomtom/tcomment_vim'
" 	Plug 'mileszs/ack.vim'
" 	Plug 'jiangmiao/auto-pairs'
" 	Plug 'vim-scripts/ReplaceWithRegister'
" 	Plug 'ojroques/vim-oscyank'
" call plug#end()


" --------------
" end
" --------------
