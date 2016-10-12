mkdir ~/OSSetup
cd ~/OSSetup

#install Brew
/usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
brew install CMake
brew install git

#Install solarized color scheme
git clone https://github.com/altercation/solarized.git
open ~/OSSetup/solarized/osx-terminal.app-colors-solarized/xterm-256color/Solarized\ Dark\ xterm-256color.terminal


#Install VIM
git clone https://github.com/JoseBarrios/vim-dots.git
cd vim-dots
sh ./unpack.sh

