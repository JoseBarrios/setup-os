sudo apt-get update; 
sudo apt-get dist-upgrade; 
sudo apt-get clean;
sudo apt-get install vim;
sudo apt-get install git;

mkdir Development
cd Development

#Node
wget https://nodejs.org/dist/v4.4.7/node-v4.4.7-linux-armv6l.tar.gz 
tar -xvf node-v4.4.7-linux-armv6l.tar.gz 
cd node-v4.4.7-linux-armv6l
sudo cp -R * /usr/local/
cd ..
rm -rf node-v4.4.7-linux-armv6l
rm node-v4.4.7-linux-armv6l.tar.gz 

#CMake
wget https://cmake.org/files/v3.4/cmake-3.4.1.tar.gz
tar -xvzf cmake-3.4.1.tar.gz
cd cmake-3.4.1/
sudo ./bootstrap
sudo make
sudo make install

#VIM configuration
git clone https://github.com/JoseBarrios/vim-dots.git
cd vim-dots
./unpack.sh
cd ..
rm -rf vim-dots
git config --global core.editor vim
