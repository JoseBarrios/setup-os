mkdir ~/OSSetup
cd ~/OSSetup

#install Brew
/usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
brew update
brew doctor
brew install CMake
brew install gpg
brew install git
brew install node
brew upgrade gnupg
brew install pinentry-mac
killall gpg-agent
git config --global gpg.program gpg
echo "pinentry-program /usr/local/bin/pinentry-mac" >> ~/.gnupg/gpg-agent.conf
# Install n, node version manager
npm install n -g
sudo n lts

#Install solarized color scheme
git clone https://github.com/altercation/solarized.git
open ~/OSSetup/solarized/osx-terminal.app-colors-solarized/xterm-256color/Solarized\ Dark\ xterm-256color.terminal

#Install VIM
git clone https://github.com/JoseBarrios/vim-dots.git
cd vim-dots
sh ./unpack.sh
cd ..

# Fonts and icons
git clone git@github.com:ryanoasis/nerd-fonts.git
cd nerd-fonts && ./install.sh
cd ..

# zsh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

