mkdir ~/OSSetup
cd ~/OSSetup

#install Brew
/usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
brew install CMake

#Install solarized color scheme
git clone https://github.com/altercation/solarized.git
open solarised/osx-terminal.app-colors-solarized/xterm-256color/Solarized Dark xterm-256color.terminal

#Install VIM
git clone git@github.com:JoseBarrios/vim-dots.git
./vim-dots/unpack.sh

