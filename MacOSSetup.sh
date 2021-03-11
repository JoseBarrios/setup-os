mkdir ~/OSSetup
cd ~/OSSetup

#install Brew
/usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
brew update
brew doctor
brew install CMake
brew install vim
brew install node
brew install git

# Linters
brew install yamllint
brew install cfn-lint # cloudfront

brew install node
brew install rg
brew install gnupg
brew install pinentry-mac
git config --global gpg.program gpg2
echo "pinentry-program /usr/local/bin/pinentry-mac" >> ~/.gnupg/gpg-agent.conf
killall gpg-agent

# Git config
git config --global gpg.program gpg
git config --global merge.tool vimdiff
git config --global merge.conflictstyle diff3
git config --global mergetool.prompt false
git config --global pull.rebase false

# Install n, node version manager
npm install n -g
sudo n lts

# Dependency of vim-preview
sudo gem install bluecloth

#Install solarized color scheme
git clone https://github.com/altercation/solarized.git
open ~/OSSetup/solarized/osx-terminal.app-colors-solarized/xterm-256color/Solarized\ Dark\ xterm-256color.terminal

#Install VIM
git clone https://github.com/JoseBarrios/vim-dots.git
mkdir ~/.vim/undo
cd vim-dots
sh ./unpack.sh
cd ..

# Fonts and icons
git clone git@github.com:ryanoasis/nerd-fonts.git
cd nerd-fonts && ./install.sh
cd ..

# zsh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

