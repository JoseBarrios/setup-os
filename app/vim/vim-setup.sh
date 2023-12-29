#!/bin/bash
#################
#   VARIABLES   #
#################
files="vimrc vim"   # list of files/folders to symlink in homedir
dir=${PWD}/app         	# dotfiles directory
vim=$dir/vim      	# vim settings directory
olddir=$vim/old   	# old dotfiles backup directory
vimcolors=$vim/colors
vimbackups=$vim/backups
vimbundle=$vim/bundle
vimswaps=$vim/swaps
vimundo=$vim/undo

#################
#   FUNCTIONS   #
#################
# INFO:   Creates a directory if one doesn't already exist
# INPUT:  $1 = directory, $2 command to execute once directory exists
function makeDirectory {
    if [ ! -d "$1" ]; then
        mkdir -p "$1"
        echo "Created directory: $1"
    else
        echo "Directory $1 already exists"
    fi
    # Is there a 2nd argument passed?
    if [ ! -z "$2" ]; then
        eval "$2"
    fi
}

#############
#   MAIN    #
#############
makeDirectory $vim
makeDirectory $vimcolors
makeDirectory $olddir
makeDirectory $vimswaps
makeDirectory $vimbackups
makeDirectory $vimundo
makeDirectory $vimbundle "git clone https://github.com/gmarik/Vundle.vim.git $vimbundle/Vundle.vim"

# move any existing dotfiles in homedir to dot_old directory, then create symlinks from the homedir to any files in the ~/dotfiles directory specified in $files
cd $dir
for file in $files; do
    echo "Moving any existing dotfiles from ~ to $olddir"
    mv ~/.$file $olddir/
    echo "Creating symlink to $file in home directory."
    ln -s $dir/$file ~/.$file
    echo "Installing solarized colors for VIM"
    git clone https://github.com/altercation/vim-colors-solarized.git
    cp ./vim-colors-solarized/colors/solarized.vim $vimcolors
    rm -rf vim-colors-solarized

done
# Install plugins defined in vimrc
echo "Installing vim plugins"
vim +PluginInstall +qall
wait

# Additional setup for plugins
echo "Configuring plugins"
if [ -d "$vimbundle/tern_for_vim/" ]; then
    pushd "$vimbundle/tern_for_vim/"
    npm install
    popd
fi
if [ -d "$vimbundle/YouCompleteMe/" ]; then
    pushd "$vimbundle/YouCompleteMe/"
    git submodule update --init --recursive
    brew install cmake macvim
    python install.py
    ./install.py -all --clangd-completer
    popd
fi

# Used by vim-prettier
npm install prettier -g

# used by black
cd ~/.vim/bundle/black
