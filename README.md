Linux Dotfiles
==============

Linux dotfiles for personal use, if you like these dotfiles, clone and have fun !

## zsh

    sudo apt-get install zsh
    git clone https://github.com/robbyrussell/oh-my-zsh

Install [zsh](http://www.zsh.org/) , clone [oh-my-zsh](https://github.com/robbyrussell/oh-my-zsh) and write custom configs.

## vim

My installed bundles below.

    Plugin 'gmarik/vundle'
    Plugin 'scrooloose/syntastic'
    Plugin 'scrooloose/nerdtree'
    Plugin 'majutsushi/tagbar'
    Plugin 'kien/ctrlp.vim'
    Plugin 'mutewinter/nginx.vim'
    Plugin 'othree/html5.vim'
    Plugin 'hail2u/vim-css3-syntax'

After installed these bundles, I create `~/.vim/colors` folder and put custom colorschemes in it.

## sublime

Sublime Text user settings and installed plugins.

## git

Place global configs in `~/.gitconfig`, then generate `.gitignore` file by [gitignore.io](http://www.gitignore.io/)

## python

To solve `pip install [package]` failure, change the index-url to <http://pypi.douban.com/simple/>, you can find fastest mirror at [PyPi Mirror Status](http://www.pypi-mirrors.org/)

    *unix/mac: `$HOME/.pip/pip.conf`
    windows: `%HOME%\pip\pip.ini`

## ruby

To solve `gem install [package]` failure, change the download sources to <http://ruby.taobao.org/>

## nginx

Basic nginx config files for web applicatons.

## dnsmasq

My local DNS server configs for network speed optimization.

**Install Dnsmasq**

    # Ubuntu
    sudo apt-get install dnsmasq
    sudo service dnsmasq start|restart|stop

**/etc/resolv.conf**

    nameserver 127.0.0.1

**/etc/resolv.dnsmasq.conf**

    # ALI DNS
    nameserver 223.5.5.5
    nameserver 223.6.6.6

    # 114 DNS
    nameserver 114.114.114.114
    nameserver 114.114.115.115

    # V2EX DNS
    nameserver 199.91.73.222
    nameserver 178.79.131.110

    # GOOGLE DNS
    nameserver 8.8.8.8
    nameserver 8.8.4.4

    # OPEN DNS
    nameserver 208.67.222.222
    nameserver 208.67.220.220

    # DEFAULT DNS
    nameserver 127.0.0.1

**/etc/dnsmasq.conf**

My Personal configuration for better dnsmasq usage.

## vagrant

My vagrant config file and  bootstrap shell script.
