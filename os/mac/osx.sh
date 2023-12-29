mkdir ~/OSSetup
cd ~/OSSetup

# Brew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
(echo; echo 'eval "$(/usr/local/bin/brew shellenv)"') >> /Users/jbarrios/.zprofile
eval "$(/usr/local/bin/brew shellenv)"
brew update
brew doctor
brew install CMake
brew install vim
brew install node
brew install git

# Linters
brew install yamllint

# CloudFront
brew install cfn-lint 

brew install node

# RipGrep
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

git config --global user.name "Jose Barrios"
git config --global user.email github@barrios.io

# Install Node version manager
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash

# Dependency of vim-preview
sudo gem install bluecloth

#Install solarized color scheme
git clone https://github.com/altercation/solarized.git
open ~/OSSetup/solarized/osx-terminal.app-colors-solarized/xterm-256color/Solarized\ Dark\ xterm-256color.terminal

#Install VIM
/bin/bash ../../app/vim/vim-setup.sh


# Fonts and icons
git clone https://github.com/ryanoasis/nerd-fonts.git
cd nerd-fonts && ./install.sh
cd ..

# zsh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

