#!/bin/bash
# shellcheck disable=SC1091,SC2016,SC2086,SC2046,SC2164

# enable proxy
## ip=
## export https_proxy=http://$ip:7890;export http_proxy=http://$ip:7890;export all_proxy=socks5://$ip:7890
## curl https://www.google.com

# Initialize the variables required by the script
SUDO=''; (( EUID )) && SUDO=sudo; echo $SUDO
ARCH=$(dpkg --print-architecture); echo $ARCH
WORKDIR="/tmp" && cd $WORKDIR && pwd

# sed -i 's/^[[:space:]]*#[[:space:]]*\(deb-src\)/\1/' /etc/apt/sources.list
$SUDO apt update && $SUDO apt install -y ca-certificates

# backup /etc/apt/sources.list
$SUDO cp /etc/apt/sources.list /etc/apt/sources.list.bak.$(date +%F)

# update apt source for x86
$SUDO tee /etc/apt/sources.list <<-'EOF'
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy main restricted universe multiverse
# deb-src https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-updates main restricted universe multiverse
# deb-src https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-updates main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-backports main restricted universe multiverse
# deb-src https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-backports main restricted universe multiverse

deb http://security.ubuntu.com/ubuntu/ jammy-security main restricted universe multiverse
# deb-src http://security.ubuntu.com/ubuntu/ jammy-security main restricted universe multiverse

# deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-proposed main restricted universe multiverse
# deb-src https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-proposed main restricted universe multiverse

EOF

# update apt source for arm
$SUDO tee /etc/apt/sources.list <<-'EOF'
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ jammy main restricted universe multiverse
# deb-src https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ jammy main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ jammy-updates main restricted universe multiverse
# deb-src https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ jammy-updates main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ jammy-backports main restricted universe multiverse
# deb-src https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ jammy-backports main restricted universe multiverse

deb http://ports.ubuntu.com/ubuntu-ports/ jammy-security main restricted universe multiverse
# deb-src http://ports.ubuntu.com/ubuntu-ports/ jammy-security main restricted universe multiverse

# deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ jammy-proposed main restricted universe multiverse
# deb-src https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ jammy-proposed main restricted universe multiverse

EOF

# install tools
$SUDO apt update && $SUDO apt -y install tzdata
$SUDO timedatectl set-timezone Asia/Shanghai

basic_tools=(
  vim git wget curl net-tools iputils-ping lsof sed tree htop
  iotop strace psmisc valgrind jq bc exa netcat ncat nmap
  unzip diffutils dosfstools xfsprogs e2fsprogs gdisk
  smartmontools nvme-cli sysstat rdma-core shellcheck
  asciidoctor texinfo fakeroot dpkg-dev equivs debian-keyring
  apt-file zsh software-properties-common locales ripgrep fd-find
)
build_tools=(
  gcc g++ make automake cmake ninja-build build-essential nasm
  clang clang-tidy clangd libclang-dev llvm bison flex
  gdb bear ccache maven libtool
)
dev_deps=(
  python3 python3-dev python3-sphinx python3-pip
  nodejs npm golang php composer
  openjdk-8-jdk openjdk-11-jdk openjdk-17-jdk
  lua5.4 liblua5.4-dev tcl sqlite3 libsqlite3-dev

  systemtap-sdt-dev libbpfcc-dev libbpf-dev libelf-dev dwarves
  bpfcc-tools bpftrace
  librados-dev librbd-dev
  libnuma-dev libzstd-dev libzbd-dev lz4 libsnappy-dev
  libaio-dev libdw-dev libblkid-dev libsystemd-dev
  libcereal-dev libgtest-dev libgmock-dev
  libthrift-dev libprotobuf-dev protobuf-compiler
  libssl-dev libnghttp2-dev nghttp2
  libboost-all-dev

  libspdlog-dev
)
$SUDO apt install -y "${basic_tools[@]}"
$SUDO apt install -y "${build_tools[@]}"
$SUDO apt install -y "${dev_deps[@]}"
$SUDO apt install -y linux-headers-$(uname -r) kmod

# update locale
$SUDO locale-gen en_US.UTF-8
$SUDO update-locale LANG=en_US.UTF-8

# for desktop virtualbox
$SUDO apt install gcc-12 g++-12 && \
  $SUDO ln -sf /usr/bin/gcc-12 /usr/bin/gcc && \
  $SUDO ln -sf /usr/bin/g++-12 /usr/bin/g++

# update-alternatives --config java
java -version

# install python pkgs
python3 -m pip install --user pyright ruff PrettyTable matplotlib seaborn

# setup .bashrc
tee -a $HOME/.bashrc <<-'EOF'

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export LESSCHARSET=utf-8

function git_branch {
    branch="`git branch 2>/dev/null | grep "^\*" | sed -e "s/^\*\ //"`"
    if [ "${branch}" != "" ];then
        if [ "${branch}" = "(no branch)" ];then
            branch="(`git rev-parse --short HEAD`...)"
        fi
        echo " ($branch)"
    fi
}
export PS1='[\u@\h \[\033[01;36m\]\W\[\033[01;32m\]$(git_branch)\[\033[00m\]] \$ '

alias rm='rm -rf'
alias ..='cd ..'
alias la='exa --long --header --group --modified --color-scale --all --sort=type'
alias ll='exa --long --header --group --modified --color-scale --sort=type'
alias ls='exa'
alias gs='git status'
alias gaa='git add .'
alias gcm='git commit -m'
alias gp='git push'

export TERM=xterm-256color

export USE_CCACHE=1
export CCACHE_SLOPPINESS=file_macro,include_file_mtime,time_macros
export CCACHE_UMASK=002

EOF

source $HOME/.bashrc

# rebuild git
mkdir git-openssl && cd git-openssl && \
  $SUDO apt build-dep git -y && \
  $SUDO apt install -y libcurl4-openssl-dev && \
  apt source git -y && \
  cd git-2.34.1 && \
  grep gnutls < debian/control && \
  sed -i 's/libcurl4-gnutls-dev/libcurl4-openssl-dev/g' debian/control && \
  grep curl < debian/control && \
  dpkg-buildpackage -b -uc -us && \
  cd .. && $SUDO dpkg -i git-man_*_all.deb git_*_$ARCH.deb && \
  cd .. && rm -rf git-openssl

# zsh
# sh -c "$(curl -fsSL https://install.ohmyz.sh/)"
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" && \
  git clone https://github.com/zsh-users/zsh-completions $HOME/.oh-my-zsh/custom/plugins/zsh-completions && \
  git clone https://github.com/zsh-users/zsh-autosuggestions $HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions && \
  git clone https://github.com/zsh-users/zsh-syntax-highlighting.git $HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting

# setup .zshrc
sed -i 's/^ZSH_THEME=.*/ZSH_THEME="gentoo"/' $HOME/.zshrc
sed -i 's/^plugins=.*/plugins=(git zsh-completions zsh-autosuggestions zsh-syntax-highlighting)/' $HOME/.zshrc
tee -a $HOME/.zshrc <<-'EOF'

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export LESSCHARSET=utf-8

setopt rmstarsilent

alias rm='rm -rf'
alias ..='cd ..'
alias la='exa --long --header --group --modified --color-scale --all --sort=type'
alias ll='exa --long --header --group --modified --color-scale --sort=type'
alias ls='exa'
alias gs='git status'

export TERM=xterm-256color

export USE_CCACHE=1
export CCACHE_SLOPPINESS=file_macro,include_file_mtime,time_macros
export CCACHE_UMASK=002

EOF

source $HOME/.zshrc

# install go 1.24
## $SUDO add-apt-repository ppa:longsleep/golang-backports                      \
##   && $SUDO apt update                                                        \
##   && $SUDO apt install -y golang                                             \
##   && go env -w GOPATH=/opt/go                                                \
##   && mkdir -p $HOME/.config/go                                               \
##   && echo 'export GOPATH=/opt/go' >> $HOME/.config/go/profile                \
##   && echo 'export PATH=$PATH:$GOPATH/bin' >> $HOME/.config/go/profile        \
##   && echo '. "$HOME/.config/go/profile"' | tee -a $HOME/.bashrc $HOME/.zshrc

pkgname=go1.24.11.linux-$ARCH.tar.gz && \
  wget https://go.dev/dl/$pkgname && \
  tar -zxf $pkgname && rm -rf $pkgname && \
  $SUDO mv go /usr/lib/go-1.24 && \
  $SUDO update-alternatives --install /usr/bin/go go /usr/lib/go-1.18/bin/go 118 --slave /usr/bin/gofmt gofmt /usr/lib/go-1.18/bin/gofmt && \
  $SUDO update-alternatives --install /usr/bin/go go /usr/lib/go-1.24/bin/go 124 --slave /usr/bin/gofmt gofmt /usr/lib/go-1.24/bin/gofmt && \
  go version

go env GOPATH GOROOT && \
  mkdir -p $HOME/.config/go && \
  echo 'export GOPATH=$HOME/go' >> $HOME/.config/go/profile && \
  echo 'export PATH=$PATH:$GOPATH/bin' >> $HOME/.config/go/profile && \
  echo '. "$HOME/.config/go/profile"' | tee -a $HOME/.bashrc $HOME/.zshrc && \
  source $HOME/.zshrc && echo $PATH

# install golangci-lint
# https://golangci-lint.run/docs/welcome/install/#local-installation
curl -sSfL https://raw.githubusercontent.com/golangci/golangci-lint/HEAD/install.sh | sh -s -- -b $(go env GOPATH)/bin v2.6.2
golangci-lint --version

# go install github.com/axw/gocov/gocov@latest
go install golang.org/x/tools/gopls@latest && \
  go install honnef.co/go/tools/cmd/staticcheck@latest && \
  go install github.com/google/pprof@latest && \
  go install mvdan.cc/gofumpt@latest && \
  go install github.com/AlekSi/gocov-xml@latest && \
  go install github.com/matm/gocov-html/cmd/gocov-html@latest && \
  go install github.com/go-delve/delve/cmd/dlv@latest && \
  go install github.com/golang/mock/mockgen@latest && \
  go install github.com/charmbracelet/glow/v2@latest

# install rust
curl https://sh.rustup.rs -sSf | sh -s -- -y && \
  . $HOME/.cargo/env && \
  rustc --version && \
  rustup component add rust-src rust-analyzer rust-analyzer-preview

# install terraform
pkgname=terraform_1.13.4_linux_$ARCH.zip && \
  wget https://releases.hashicorp.com/terraform/1.13.4/$pkgname && \
  unzip -q $pkgname && \
  $SUDO mv terraform /usr/bin && \
  rm -rf $pkgname LICENSE.txt && \
  wget -O terragrunt https://github.com/gruntwork-io/terragrunt/releases/download/v0.92.1/terragrunt_linux_$ARCH && \
  chmod +x terragrunt && \
  $SUDO mv terragrunt /usr/bin && \
  wget -O hcl2json https://github.com/tmccombs/hcl2json/releases/download/v0.6.8/hcl2json_linux_$ARCH && \
  chmod +x hcl2json && \
  $SUDO mv hcl2json /usr/bin && \
  which terraform terragrunt hcl2json

# install vim with YCM
git clone https://github.com/yujrchyang/vimrc.git $HOME/.vim_runtime && \
  cd $HOME/.vim_runtime && \
  git submodule update --init --recursive && \
  python3 $HOME/.vim_runtime/my_plugins/YouCompleteMe/install.py --all --force-sudo && \
  sh $HOME/.vim_runtime/install_awesome_vimrc.sh && \
  cd $WORKDIR

# install vim without YCM
git clone https://github.com/yujrchyang/vimrc.git $HOME/.vim_runtime && \
  sh $HOME/.vim_runtime/install_awesome_vimrc.sh

# install nvim
## install dep node.js
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash && \
  \. "$HOME/.nvm/nvm.sh" && \
  nvm install 24 && \
  node -v && \
  npm -v

## install dep julialang/neovim/tree-sitter
curl -fsSL https://install.julialang.org | sh && \
  . $HOME/.zshrc && \
  npm install -g neovim && \
  cargo install --locked tree-sitter-cli

pkgarch=$(if [ "$ARCH" = "arm64" ]; then echo "arm64"; else echo "x86_64"; fi) && \
  pkgname=nvim-linux-$pkgarch.tar.gz && \
  wget https://github.com/neovim/neovim/releases/download/v0.11.5/$pkgname && \
  tar -zxf $pkgname && rm -rf $pkgname && \
  $SUDO mv nvim-linux-$pkgarch /usr/lib/nvim-0.11.5-linux-$pkgarch && \
  $SUDO ln -s /usr/lib/nvim-0.11.5-linux-$pkgarch/bin/nvim /usr/bin && \
  which nvim

# arm
mkdir -p $HOME/.local/share/nvim/mason/packages/clangd/mason-schemas && \
  cd $HOME/.local/share/nvim/mason/packages/clangd && \
  curl -qs https://raw.githubusercontent.com/clangd/vscode-clangd/master/package.json | jq .contributes.configuration > mason-schemas/lsp.json && \
  echo '{"schema_version":"1.1","primary_source":{"type":"local"},"name":"clangd","links":{"share":{"mason-schemas/lsp/clangd.json":"mason-schemas/lsp.json"}}}' > mason-receipt.json && \
  cd $WORKDIR

git clone https://github.com/yujrchyang/neovimrc.git $HOME/.config/nvim
nvim --headless +"Lazy! sync" +qa
nvim

# install blobstore deps x86
## install consul
pkgname=consul_1.11.4_linux_$ARCH.zip && \
  wget https://releases.hashicorp.com/consul/1.11.4/$pkgname && \
  unzip -q $pkgname && \
  rm -rf $pkgname && \
  $SUDO mv -f consul /usr/bin && \
  which consul

# install kafka
wget https://ocs-cn-south1.heytapcs.com/blobstore/kafka_2.13-3.1.0.tgz && \
  $SUDO tar -zxf kafka_2.13-3.1.0.tgz -C /usr/bin && \
  rm -rf kafka_2.13-3.1.0.tgz && \
  wget https://repo1.maven.org/maven2/log4j/apache-log4j-extras/1.2.17/apache-log4j-extras-1.2.17.jar && \
  $SUDO mv apache-log4j-extras-1.2.17.jar /usr/bin/kafka_2.13-3.1.0/libs/log4j-extras-1.2.17.jar

# install cosbench
wget https://github.com/intel-cloud/cosbench/releases/download/v0.4.2.c4/0.4.2.c4.zip && \
  unzip -q 0.4.2.c4.zip && \
  chmod +x 0.4.2.c4/*.sh && \
  $SUDO mv 0.4.2.c4 /usr/bin/cosbench-0.4.2.c4 && \
  rm -rf 0.4.2.c4.zip

# install clickhouse
# vim absl/debugging/failure_signal_handler.cc
# size_t stack_size = (std::max<size_t>(SIGSTKSZ, 65536) + page_mask) & ~page_mask;
wget -O abseil-cpp-20200923.3.tar.gz https://github.com/abseil/abseil-cpp/archive/refs/tags/20200923.3.tar.gz && \
  tar -zxf abseil-cpp-20200923.3.tar.gz && \
  cd abseil-cpp-20200923.3 && \
  sed -i 's/^  size_t stack_size =.*/  size_t stack_size = (std::max<size_t>(SIGSTKSZ, 65536) + page_mask) \& ~page_mask;/' absl/debugging/failure_signal_handler.cc && \
  mkdir build && cd build && \
  cmake .. -DCMAKE_BUILD_TYPE=Release && \
  make && $SUDO make install && \
  cd ../.. && rm -rf abseil-cpp-20200923.3*

wget -O clickhouse-cpp-2.1.0.tar.gz https://github.com/ClickHouse/clickhouse-cpp/archive/refs/tags/v2.1.0.tar.gz && \
  tar -zxf clickhouse-cpp-2.1.0.tar.gz && \
  cd clickhouse-cpp-2.1.0 && \
  mkdir build && cd build && \
  cmake .. -DBUILD_SHARED_LIBS=ON -DCMAKE_BUILD_TYPE=Release && \
  make && $SUDO make install && \
  cd ../.. && rm -rf clickhouse-cpp*

# install rocksdb deps
wget -O gflags-2.2.2.tar.gz https://github.com/gflags/gflags/archive/refs/tags/v2.2.2.tar.gz && \
  tar -zxf gflags-2.2.2.tar.gz && \
  cd gflags-2.2.2 && \
  mkdir build && cd build && \
  cmake .. -DBUILD_SHARED_LIBS=1 -DCMAKE_BUILD_TYPE=Release && \
  make && $SUDO make install && \
  cd ../.. && rm -rf gflags-2.2.2*

wget -O snappy-1.1.8.tar.gz https://github.com/google/snappy/archive/refs/tags/1.1.8.tar.gz && \
  tar -zxf snappy-1.1.8.tar.gz && \
  cd snappy-1.1.8 && \
  mkdir build && cd build && \
  cmake .. -DSNAPPY_BUILD_TESTS=OFF -DBUILD_SHARED_LIBS=1 -DCMAKE_BUILD_TYPE=Release && \
  make && $SUDO make install && \
  cd ../.. && rm -rf snappy-1.1.8*

wget -O leveldb-1.22.tar.gz https://github.com/google/leveldb/archive/refs/tags/1.22.tar.gz && \
  tar -zxf leveldb-1.22.tar.gz && \
  cd leveldb-1.22 && \
  mkdir build && cd build && \
  cmake .. -DCMAKE_CXX_FLAGS="-fPIC" -DCMAKE_C_FLAGS="-fPIC" -DCMAKE_BUILD_TYPE=Release && \
  make && $SUDO make install && \
  cd ../.. && rm -rf leveldb-1.22*

# install seastar deps
git clone --depth=1 --branch seastar-22.11.0 https://github.com/scylladb/seastar.git seastar-22.11.0 && \
  cd seastar-22.11.0 && \
  $SUDO ./install-dependencies.sh && \
  cd .. && rm -rf seastar-22.11.0

# install spdk deps
# delete sudo command in scripts/pkgdep/common.sh
git clone --depth=1 --branch v24.01 https://github.com/spdk/spdk.git spdk-24.01 && \
  cd spdk-24.01 && \
  ( [[ "$SUDO" == "sudo" ]] || sed -i 's/\(^[[:space:]]*\)sudo -E /\1/' scripts/pkgdep/common.sh ) && \
  $SUDO scripts/pkgdep.sh --all && \
  cd .. && rm -rf spdk-24.01

# install ceph deps
git clone --depth=1 --branch v17.2.9 https://github.com/ceph/ceph ceph-v17.2.9 && \
  cd ceph-v17.2.9 && \
  ./install-deps.sh && \
  cd .. && rm -rf ceph-v17.2.9

$SUDO cp /sys/kernel/btf/vmlinux /usr/lib/modules/"$(uname -r)"/build/
$SUDO vim /etc/default/grub
# GRUB_CMDLINE_LINUX_DEFAULT="intel_iommu=on iommu=pt"
$SUDO update-grub
$SUDO reboot
