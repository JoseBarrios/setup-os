# Change kali username's default password
# passwd 

# Change root's default password
# sudo passwd root

# Update packages
sudo apt update
sudo apt full-upgrade -y

# Assumes python and pip are installed
python -m pip install --user ansible

# Configure basic tools
sudo apt install node

# Code repo
sudo apt install git

# Editor
sudo apt install vim
./app/vim/setup-vim.sh


