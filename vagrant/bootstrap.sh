#!/bin/sh
set -e

echo ">>> Bootstrap started...\n"

# Fix locales
echo 'LANG="en_US.UTF-8"' > /etc/default/locale
echo 'LANGUAGE="en_US:en"' >> /etc/default/locale
echo 'LC_ALL="en_US.UTF-8"' >> /etc/default/locale
dpkg-reconfigure locales
echo "\n>>> Locales fixed...\n"

# Select fastest mirror
sed -i '1s/^/deb mirror:\/\/mirrors.ubuntu.com\/mirrors.txt vivid-security main universe\n/' /etc/apt/sources.list
sed -i '1s/^/deb mirror:\/\/mirrors.ubuntu.com\/mirrors.txt vivid-backports main universe\n/' /etc/apt/sources.list
sed -i '1s/^/deb mirror:\/\/mirrors.ubuntu.com\/mirrors.txt vivid-updates main universe\n/' /etc/apt/sources.list
sed -i '1s/^/deb mirror:\/\/mirrors.ubuntu.com\/mirrors.txt vivid main universe\n/' /etc/apt/sources.list
echo "\n>>> Mirror selected...\n"

# Upgrade task
apt-get update
apt-get -y dist-upgrade
apt-get -y upgrade
echo "\n>>> Upgrade completed...\n"

# Clean task
apt-get clean
apt-get autoclean
apt-get -y autoremove
echo "\n>>> Clean completed...\n"

# Install essentials
apt-get install -y wget curl exuberant-ctags xtail libjpeg-dev
echo "\n>>> Essentials installed...\n"

# Install git
apt-get install -y git tig
wget https://raw.githubusercontent.com/laozhu/dotfiles/master/git/gitconfig -O /home/vagrant/.gitconfig
chown vagrant:vagrant /home/vagrant/.gitconfig
echo "\n>>> Git installed...\n"

# Install vim
apt-get install -y vim-nox
mkdir -p /home/vagrant/.vim/colors
wget https://raw.githubusercontent.com/laozhu/dotfiles/master/vim/vimrc -O /home/vagrant/.vimrc
wget https://raw.githubusercontent.com/laozhu/dotfiles/master/vim/colors/molokai.vim -O /home/vagrant/.vim/colors/molokai.vim
wget https://raw.githubusercontent.com/laozhu/dotfiles/master/vim/colors/Tomorrow-Night-Eighties.vim -O /home/vagrant/.vim/colors/Tomorrow-Night-Eighties.vim
git clone https://github.com/gmarik/Vundle.vim.git /home/vagrant/.vim/bundle/Vundle.vim
chown vagrant:vagrant /home/vagrant/.vimrc
chown -R vagrant:vagrant /home/vagrant/.vim
echo "\n>>> Vim installed...\n"

# Install zsh
apt-get install -y zsh
wget https://raw.githubusercontent.com/laozhu/dotfiles/master/zsh/zshrc -O /home/vagrant/.zshrc
git clone git://github.com/robbyrussell/oh-my-zsh.git /home/vagrant/.oh-my-zsh
chown vagrant:vagrant /home/vagrant/.zshrc
chown -R vagrant:vagrant /home/vagrant/.oh-my-zsh
echo "\n>>> Zsh installed...\n"

# Install python
apt-get install -y python-dev python3-dev python-setuptools
easy_install pip
pip install virtualenvwrapper flake8 autopep8
echo "\n>>> Python installed...\n"

# Install nginx
apt-get install -y nginx
rm /etc/nginx/nginx.conf
wget https://raw.githubusercontent.com/laozhu/dotfiles/master/nginx/nginx.conf -O /etc/nginx/nginx.conf
service nginx restart

# Install postgresql
apt-get install -y postgresql postgresql-client libpq-dev
service postgresql restart

echo ">>> Bootstrap finished...\n"
echo "*** exec 'PluginInstall' in vim manually\n"
echo "*** exec 'chsh -s /bin/zsh' in shell manually\n"
