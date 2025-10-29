#!/bin/bash
# shellcheck disable=SC1091,SC2016,SC2086

# sudo sed -i 's/^[[:space:]]*#[[:space:]]*\(deb-src\)/\1/' /etc/apt/sources.list
sudo apt-get update
sudo apt-get install -y ca-certificates

# update apt source for x86
sudo tee /etc/apt/sources.list <<-'EOF'
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy main restricted universe multiverse
deb-src https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-updates main restricted universe multiverse
deb-src https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-updates main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-backports main restricted universe multiverse
deb-src https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-backports main restricted universe multiverse

deb http://security.ubuntu.com/ubuntu/ jammy-security main restricted universe multiverse
deb-src http://security.ubuntu.com/ubuntu/ jammy-security main restricted universe multiverse

# deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-proposed main restricted universe multiverse
# deb-src https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-proposed main restricted universe multiverse
EOF

# update apt source for arm
sudo tee /etc/apt/sources.list <<-'EOF'
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ jammy main restricted universe multiverse
deb-src https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ jammy main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ jammy-updates main restricted universe multiverse
deb-src https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ jammy-updates main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ jammy-backports main restricted universe multiverse
deb-src https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ jammy-backports main restricted universe multiverse

deb http://ports.ubuntu.com/ubuntu-ports/ jammy-security main restricted universe multiverse
deb-src http://ports.ubuntu.com/ubuntu-ports/ jammy-security main restricted universe multiverse

# deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ jammy-proposed main restricted universe multiverse
# deb-src https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ jammy-proposed main restricted universe multiverse
EOF

# install tools
sudo apt-get update
sudo apt-get -y install tzdata
sudo apt-get install -y                                                         \
  vim git wget curl net-tools apt-file libtool smartmontools sysstat            \
  gdb gcc g++ make automake cmake ninja-build build-essential nasm              \
  python3 python3-dev python3-sphinx python3-pip nodejs dosfstools xfsprogs     \
  ack fonts-powerline vim-nox mono-complete openjdk-17-jdk openjdk-17-jre       \
  npm llvm clang clangd libnuma-dev libzstd-dev libzbd-dev bear ccache          \
  lua5.4 liblua5.4-dev tcl sqlite3 libsqlite3-dev e2fsprogs                     \
  systemtap-sdt-dev libbpfcc-dev libbpf-dev libclang-dev bison flex             \
  libelf-dev libcereal-dev libgtest-dev libgmock-dev asciidoctor                \
  libthrift-dev texinfo rdma-core libsystemd-dev libblkid-dev libaio-dev        \
  libsnappy-dev lz4 exa bc dwarves jq libspdlog-dev diffutils unzip             \
  libprotobuf-dev protobuf-compiler zsh netcat libboost-all-dev gdisk           \
  libclang-12-dev libdw-dev bpfcc-tools bpftrace librados-dev librbd-dev        \
  iputils-ping nghttp2 libnghttp2-dev libssl-dev libcurl4-gnutls-dev            \
  fakeroot dpkg-dev nvme-cli consul maven software-properties-common lsof sed   \
  iotop strace psmisc valgrind tree

sudo cp /sys/kernel/btf/vmlinux /usr/lib/modules/"$(uname -r)"/build/

pip install PrettyTable matplotlib seaborn

# enable proxy

# rebuild git
mkdir git-openssl && cd git-openssl                                                                 \
  && sudo apt-get install -y debian-keyring build-essential fakeroot dpkg-dev libcurl4-openssl-dev  \
  && sudo apt-get build-dep git -y                                                                  \
  && sudo apt-get install -y libcurl4-openssl-dev                                                   \
  && apt-get source git -y                                                                          \
  && cd git-2.34.1                                                                                  \
  && grep gnutls < debian/control                                                                   \
  && sed -i 's/libcurl4-gnutls-dev/libcurl4-openssl-dev/g' debian/control                           \
  && grep curl < debian/control                                                                     \
  && dpkg-buildpackage -b -uc -us                                                                   \
  && cd .. && sudo dpkg -i git-man_2.34.1-1ubuntu1.12_all.deb git_2.34.1-1ubuntu1.12_amd64.deb      \
  && cd .. && rm -rf git-openssl

# zsh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"                                   \
  && git clone https://github.com/zsh-users/zsh-completions $HOME/.oh-my-zsh/custom/plugins/zsh-completions                       \
  && git clone https://github.com/zsh-users/zsh-autosuggestions $HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions               \
  && git clone https://github.com/zsh-users/zsh-syntax-highlighting.git $HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting

# setup .zshrc
sed -i 's/^plugins=.*/plugins=(git zsh-completions zsh-autosuggestions zsh-syntax-highlighting)/' $HOME/.zshrc
tee -a $HOME/.zshrc <<-'EOF'

setopt rmstarsilent

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

source $HOME/.zshrc

# install terraform
wget -O - https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg \
  && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(grep -oP '(?<=UBUNTU_CODENAME=).*' /etc/os-release || lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list \
  && sudo apt-get update                                                                                                   \
  && sudo apt-get install -y terraform                                                                                     \
  && wget -O terragrunt https://github.com/gruntwork-io/terragrunt/releases/download/v0.92.1/terragrunt_linux_amd64        \
  && chmod +x terragrunt                                                                                                   \
  && sudo mv terragrunt /usr/bin                                                                                           \
  && wget -O hcl2json https://github.com/tmccombs/hcl2json/releases/download/v0.6.8/hcl2json_linux_amd64                   \
  && chmod +x hcl2json                                                                                                     \
  && sudo mv hcl2json /usr/bin

# install go
sudo add-apt-repository ppa:longsleep/golang-backports                          \
  && sudo apt-get update                                                        \
  && sudo apt-get install -y golang                                             \
  && go env -w GOPROXY=https://goproxy.cn,direct                                \
  && go env -w GOPATH=/opt/go                                                   \
  && mkdir -p $HOME/.config/go                                                  \
  && echo 'export GOPATH=/opt/go' >> $HOME/.config/go/profile                   \
  && echo 'export PATH=$PATH:$GOPATH/bin' >> $HOME/.config/go/profile           \
  && echo '. "$HOME/.config/go/profile"' | tee -a $HOME/.bashrc $HOME/.zshrc

source $HOME/.zshrc

go install github.com/google/pprof@latest                                       \
  && go install mvdan.cc/gofumpt@latest                                         \
  && go install github.com/axw/gocov/gocov@latest                               \
  && go install github.com/AlekSi/gocov-xml@latest

# install rust
curl https://sh.rustup.rs -sSf | sh -s -- -y  \
  && . $HOME/.cargo/env                     \
  && rustup component add rust-src rust-analyzer-preview

# install vim with YCM
git clone https://github.com/yujrchyang/vimrc.git $HOME/.vim_runtime                    \
  && cd $HOME/.vim_runtime                                                              \
  && git submodule update --init --recursive                                            \
  && python3 $HOME/.vim_runtime/my_plugins/YouCompleteMe/install.py --all --force-sudo  \
  && sh $HOME/.vim_runtime/install_awesome_vimrc.sh

# install vim without YCM
git clone https://github.com/yujrchyang/vimrc.git $HOME/.vim_runtime            \
  && sh $HOME/.vim_runtime/install_awesome_vimrc.sh

# install blobstore deps x86
## install consul
wget https://ocs-cn-south1.heytapcs.com/blobstore/consul_1.11.4_linux_amd64.zip \
  && unzip -q consul_1.11.4_linux_amd64.zip                                     \
  && mv -f consul /usr/bin                                                      \
  && rm -rf consul_1.11.4_linux_amd64.zip

## install jdk
wget https://ocs-cn-south1.heytapcs.com/blobstore/jdk-8u321-linux-x64.tar.gz    \
  && tar -zxf jdk-8u321-linux-x64.tar.gz -C /usr/bin                            \
  && rm -rf jdk-8u321-linux-x64.tar.gz                                          \
  && mkdir -p $HOME/.config/java                                                                            \
  && echo 'export JAVA_HOME=/usr/bin/jdk1.8.0_321' >> $HOME/.config/java/profile                            \
  && echo 'export PATH=$JAVA_HOME/bin:$PATH' >> $HOME/.config/java/profile                                  \
  && echo 'export CLASSPATH=$JAVA_HOME/lib/dt.jar:$JAVA_HOME/lib/tools.jar' >> $HOME/.config/java/profile   \
  && echo '. "$HOME/.config/java/profile"' | tee -a $HOME/.bashrc $HOME/.zshrc

source $HOME/.zshrc

# install kafka
wget https://ocs-cn-south1.heytapcs.com/blobstore/kafka_2.13-3.1.0.tgz          \
  && tar -zxf kafka_2.13-3.1.0.tgz -C /usr/bin                                  \
  && rm -rf kafka_2.13-3.1.0.tgz

# install clickhouse
# vim absl/debugging/failure_signal_handler.cc
# size_t stack_size = (std::max<size_t>(SIGSTKSZ, 65536) + page_mask) & ~page_mask;
wget -O abseil-cpp-20200923.3.tar.gz https://github.com/abseil/abseil-cpp/archive/refs/tags/20200923.3.tar.gz                                                             \
  && tar -zxf abseil-cpp-20200923.3.tar.gz                                                                                                                                \
  && cd abseil-cpp-20200923.3                                                                                                                                             \
  && sed -i 's/^  size_t stack_size =.*/  size_t stack_size = (std::max<size_t>(SIGSTKSZ, 65536) + page_mask) \& ~page_mask;/' absl/debugging/failure_signal_handler.cc   \
  && mkdir build && cd build                                                                                                                                              \
  && cmake .. -DCMAKE_BUILD_TYPE=Release                                                                                                                                  \
  && make && sudo make install                                                                                                                                            \
  && cd ../.. && rm -rf abseil-cpp-20200923.3*

wget -O clickhouse-cpp-2.1.0.tar.gz https://github.com/ClickHouse/clickhouse-cpp/archive/refs/tags/v2.1.0.tar.gz  \
  && tar -zxf clickhouse-cpp-2.1.0.tar.gz                                                                         \
  && cd clickhouse-cpp-2.1.0                                                                                      \
  && mkdir build && cd build                                                                                      \
  && cmake .. -DBUILD_SHARED_LIBS=ON -DCMAKE_BUILD_TYPE=Release                                                   \
  && make && sudo make install                                                                                    \
  && cd ../.. && rm -rf clickhouse-cpp*

# install rocksdb deps
wget -O gflags-2.2.2.tar.gz https://github.com/gflags/gflags/archive/refs/tags/v2.2.2.tar.gz  \
  && tar -zxf gflags-2.2.2.tar.gz                                                             \
  && cd gflags-2.2.2                                                                          \
  && mkdir build && cd build                                                                  \
  && cmake .. -DBUILD_SHARED_LIBS=1 -DCMAKE_BUILD_TYPE=Release                                \
  && make && sudo make install                                                                \
  && cd ../.. && rm -rf gflags-2.2.2*

wget -O snappy-1.1.8.tar.gz https://github.com/google/snappy/archive/refs/tags/1.1.8.tar.gz   \
  && tar -zxf snappy-1.1.8.tar.gz                                                             \
  && cd snappy-1.1.8                                                                          \
  && mkdir build && cd build                                                                  \
  && cmake .. -DSNAPPY_BUILD_TESTS=OFF -DBUILD_SHARED_LIBS=1 -DCMAKE_BUILD_TYPE=Release       \
  && make && sudo make install                                                                \
  && cd ../.. && rm -rf snappy-1.1.8*

wget -O leveldb-1.22.tar.gz https://github.com/google/leveldb/archive/refs/tags/1.22.tar.gz   \
  && tar -zxf leveldb-1.22.tar.gz                                                             \
  && cd leveldb-1.22                                                                          \
  && mkdir build && cd build                                                                  \
  && cmake .. -DCMAKE_BUILD_TYPE=Release                                                      \
  && make && sudo make install                                                                \
  && cd ../.. && rm -rf leveldb-1.22*

git clone --depth=1 --branch seastar-22.11.0 https://github.com/scylladb/seastar.git seastar-22.11.0  \
  && cd seastar-22.11.0                                                                               \
  && ./install-dependencies.sh                                                                        \
  && cd .. && rm -rf seastar-22.11.0

# install spdk deps
# delete sudo command in scripts/pkgdep/common.sh
git clone --depth=1 --branch v24.01 https://github.com/spdk/spdk.git spdk-24.01 \
  && cd spdk-24.01                                                              \
  && sed -i 's/\(^[[:space:]]*\)sudo -E /\1/' scripts/pkgdep/common.sh          \
  && scripts/pkgdep.sh --all                                                    \
  && cd .. && rm -rf spdk-24.01

# install pq deps

# install ceph deps
git clone --depth=1 --branch v17.2.8 https://github.com/ceph/ceph ceph-v17.2.8  \
  && cd ceph-v17.2.8                                                            \
  && ./install-deps.sh                                                          \
  && cd .. && rm -rf ceph-v17.2.8

sudo vim /etc/default/grub
# GRUB_CMDLINE_LINUX_DEFAULT="intel_iommu=on iommu=pt"
sudo update-grub
sudo reboot
