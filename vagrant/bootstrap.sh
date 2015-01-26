#!/bin/sh
set -e

echo ">> install begin...\n"

# fix locale
echo 'LANG="en_US.UTF-8"' > /etc/default/locale
echo 'LANGUAGE="en_US:en"' >> /etc/default/locale
echo 'LC_ALL="en_US.UTF-8"' >> /etc/default/locale
dpkg-reconfigure locales

# update & upgrade
apt-get update
apt-get -y dist-upgrade
apt-get -y upgrade

# clean
apt-get clean
apt-get autoclean
apt-get -y autoremove

# install tools
apt-get install -y wget curl xtail unzip p7zip exuberant-ctags

# install git
apt-get install -y git tig git-flow
wget https://raw.githubusercontent.com/laozhu/dotfiles/master/git/gitconfig -O /home/vagrant/.gitconfig
wget https://raw.githubusercontent.com/laozhu/dotfiles/master/git/gitignore -O /home/vagrant/.gitignore

# install vim
apt-get install -y vim-nox
git clone https://github.com/gmarik/Vundle.vim.git /home/vagrant/.vim/bundle/Vundle.vim
wget https://raw.githubusercontent.com/laozhu/dotfiles/master/vim/vimrc -O /home/vagrant/.vimrc

# install python
apt-get install -y python python-pip python-dev
apt-get install -y python3 python3-pip python3-dev
mkdir /root/.pip
mkdir /home/vagrant/.pip
wget https://raw.githubusercontent.com/laozhu/dotfiles/master/pip/pip.conf -O /root/.pip/pip.conf
wget https://raw.githubusercontent.com/laozhu/dotfiles/master/pip/pip.conf -O /home/vagrant/.pip/pip.conf
pip install virtualenvwrapper ipython flake8
pip3 install ipython

# install ruby
apt-get install -y ruby
git clone https://github.com/sstephenson/rbenv.git /home/vagrant/.rbenv
git clone https://github.com/sstephenson/ruby-build.git /home/vagrant/.rbenv/plugins/ruby-build
wget https://raw.githubusercontent.com/laozhu/dotfiles/master/gem/gemrc -O /home/vagrant/.gemrc
wget https://raw.githubusercontent.com/laozhu/dotfiles/master/gem/gemrc -O /root/.gemrc

# install nodejs
git clone https://github.com/creationix/nvm.git /home/vagrant/.nvm
wget https://raw.githubusercontent.com/laozhu/dotfiles/master/node/npmrc -O /home/vagrant/.npmrc

# install zsh
apt-get install -y zsh
git clone git://github.com/robbyrussell/oh-my-zsh.git /home/vagrant/.oh-my-zsh
wget https://raw.githubusercontent.com/laozhu/dotfiles/master/zsh/zshrc -O /home/vagrant/.zshrc
chown -R vagrant:vagrant /home/vagrant/

# install nginx
apt-get install -y nginx
mkdir /etc/nginx/h5bp
wget https://raw.githubusercontent.com/laozhu/dotfiles/master/nginx/nginx.conf -O /etc/nginx/nginx.conf
wget https://raw.githubusercontent.com/laozhu/dotfiles/master/nginx/h5bp/cross-domain-fonts.conf -O /etc/nginx/h5bp/cross-domain-fonts.conf
wget https://raw.githubusercontent.com/laozhu/dotfiles/master/nginx/h5bp/cross-domain-insecure.conf -O /etc/nginx/h5bp/cross-domain-insecure.conf
wget https://raw.githubusercontent.com/laozhu/dotfiles/master/nginx/h5bp/expires.conf -O /etc/nginx/h5bp/expires.conf
wget https://raw.githubusercontent.com/laozhu/dotfiles/master/nginx/h5bp/no-transform.conf -O /etc/nginx/h5bp/no-transform.conf
wget https://raw.githubusercontent.com/laozhu/dotfiles/master/nginx/h5bp/protect-system-files.conf -O /etc/nginx/h5bp/protect-system-files.conf
wget https://raw.githubusercontent.com/laozhu/dotfiles/master/nginx/h5bp/x-ua-compatible.conf -O /etc/nginx/h5bp/x-ua-compatible.conf
sed -i "s/user nginx nginx;/user www-data;/" /etc/nginx/nginx.conf
/etc/init.d/nginx restart

# install postgresql
apt-get install -y postgresql postgresql-client libpq-dev
/etc/init.d/postgresql restart

echo "exec `BundleInstall` in vim manually\n"
echo "exec `chsh -s /bin/zsh` in shell manually\n"
echo "\n>> install finish..."
