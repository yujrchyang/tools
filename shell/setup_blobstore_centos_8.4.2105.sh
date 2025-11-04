#!/bin/bash
# shellcheck disable=SC1091,SC2016,SC2086,SC2046,SC2164

# enable proxy
## ip=
## export https_proxy=http://$ip:7890;export http_proxy=http://$ip:7890;export all_proxy=socks5://$ip:7890
## curl https://www.google.com

# Initialize the variables required by the script
SUDO=''; (( EUID )) && SUDO=sudo; echo $SUDO && \
  ARCH=$(uname -m); ARCH=$(if [ "$ARCH" = "aarch64" ]; then echo "arm64"; elif [ "$ARCH" = "x86_64" ]; then echo "amd64"; else echo "unsupport"; fi); echo $ARCH && \
  WORKDIR="/tmp" && cd $WORKDIR && pwd

$SUDO mv /etc/yum.repos.d /etc/yum.repos.d.bak && \
  $SUDO mkdir -p /etc/yum.repos.d

# use aliyun yum source
$SUDO tee /etc/yum.repos.d/CentOS-Base.repo <<-'EOF'
# CentOS-Base.repo
#
# The mirror system uses the connecting IP address of the client and the
# update status of each mirror to pick mirrors that are updated to and
# geographically close to the client.  You should use this for CentOS updates
# unless you are manually picking other mirrors.
#
# If the mirrorlist= does not work for you, as a fall back you can try the
# remarked out baseurl= line instead.
#
#

[base]
name=CentOS-$releasever - Base - mirrors.aliyun.com
#failovermethod=priority
baseurl=http://mirrors.aliyun.com/centos/$releasever/BaseOS/$basearch/os/
        http://mirrors.aliyuncs.com/centos/$releasever/BaseOS/$basearch/os/
        http://mirrors.cloud.aliyuncs.com/centos/$releasever/BaseOS/$basearch/os/
gpgcheck=1
gpgkey=http://mirrors.aliyun.com/centos/RPM-GPG-KEY-CentOS-Official

#additional packages that may be useful
[extras]
name=CentOS-$releasever - Extras - mirrors.aliyun.com
#failovermethod=priority
baseurl=http://mirrors.aliyun.com/centos/$releasever/extras/$basearch/os/
        http://mirrors.aliyuncs.com/centos/$releasever/extras/$basearch/os/
        http://mirrors.cloud.aliyuncs.com/centos/$releasever/extras/$basearch/os/
gpgcheck=1
gpgkey=http://mirrors.aliyun.com/centos/RPM-GPG-KEY-CentOS-Official

#additional packages that extend functionality of existing packages
[centosplus]
name=CentOS-$releasever - Plus - mirrors.aliyun.com
#failovermethod=priority
baseurl=http://mirrors.aliyun.com/centos/$releasever/centosplus/$basearch/os/
        http://mirrors.aliyuncs.com/centos/$releasever/centosplus/$basearch/os/
        http://mirrors.cloud.aliyuncs.com/centos/$releasever/centosplus/$basearch/os/
gpgcheck=1
enabled=0
gpgkey=http://mirrors.aliyun.com/centos/RPM-GPG-KEY-CentOS-Official

[PowerTools]
name=CentOS-$releasever - PowerTools - mirrors.aliyun.com
#failovermethod=priority
baseurl=http://mirrors.aliyun.com/centos/$releasever/PowerTools/$basearch/os/
        http://mirrors.aliyuncs.com/centos/$releasever/PowerTools/$basearch/os/
        http://mirrors.cloud.aliyuncs.com/centos/$releasever/PowerTools/$basearch/os/
gpgcheck=1
enabled=1
gpgkey=http://mirrors.aliyun.com/centos/RPM-GPG-KEY-CentOS-Official

[AppStream]
name=CentOS-$releasever - AppStream - mirrors.aliyun.com
#failovermethod=priority
baseurl=http://mirrors.aliyun.com/centos/$releasever/AppStream/$basearch/os/
        http://mirrors.aliyuncs.com/centos/$releasever/AppStream/$basearch/os/
        http://mirrors.cloud.aliyuncs.com/centos/$releasever/AppStream/$basearch/os/
gpgcheck=1
gpgkey=http://mirrors.aliyun.com/centos/RPM-GPG-KEY-CentOS-Official

EOF

$SUDO tee /etc/yum.repos.d/Ceph-Pacific.repo <<-'EOF'
[centos-ceph-pacific]
name=CentOS-$releasever - Ceph Pacific
baseurl=http://ftp.cs.stanford.edu/mirrors/centos/$contentdir/$releasever/storage/$basearch/ceph-pacific/
gpgcheck=0
enabled=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-SIG-Storage

[centos-ceph-pacific-test]
name=CentOS-$releasever - Ceph Pacific Testing
baseurl=http://ftp.cs.stanford.edu/mirrors/centos/$releasever/storage/$basearch/ceph-pacific/
gpgcheck=0
enabled=0
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-SIG-Storage

[centos-ceph-pacific-source]
name=CentOS-$releasever - Ceph Pacific Source
baseurl=http://ftp.cs.stanford.edu/mirrors/centos/$contentdir/$releasever/storage/Source/ceph-pacific/
gpgcheck=0
enabled=0
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-SIG-Storage

EOF

$SUDO yum clean all && yum makecache

$SUDO yum install -y tzdata && \
  $SUDO ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \
  date

$SUDO yum install -y vim git curl wget gdb gcc gcc-c++ make automake cmake      \
  python3 maven lsof sysstat smartmontools ncurses diffutils unzip              \
  rpm-build rpmdevtools e4fsprogs xfsprogs gdisk util-linux jq net-tools        \
  perf iotop strace psmisc valgrind createrepo yum-utils golang socat           \
  java-1.8.0-openjdk gflags-devel gflags libasan libubsan gperftools-devel      \
  librados-devel

# setup .bashrc
tee -a $HOME/.bashrc <<-'EOF'

alias rm='rm -rf'
alias ..='cd ..'
alias ls='ls --color'
alias ll='ls --color -lh'
alias la='ls --color -lhA'
 
# set bash git branch
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

EOF

source $HOME/.bashrc

wget https://rpmfind.net/linux/epel/8/Everything/aarch64/Packages/h/htop-3.2.1-1.el8.aarch64.rpm && \
  $SUDO yum install -y htop-3.2.1-1.el8.aarch64.rpm && \
  rm -rf htop-3.2.1-1.el8.aarch64.rpm

# install go
# pkgname=go1.24.9.linux-$ARCH.tar.gz && \
#   wget https://go.dev/dl/$pkgname && \
#   tar -zxf $pkgname && rm -rf $pkgname && \
#   $SUDO mv go /usr/lib/go-1.24 && \
#   $SUDO update-alternatives --install /usr/bin/go go /usr/lib/golang/bin/go 116 --slave /usr/bin/gofmt gofmt /usr/lib/golang/bin/gofmt && \
#   $SUDO update-alternatives --install /usr/bin/go go /usr/lib/go-1.24/bin/go 124 --slave /usr/bin/gofmt gofmt /usr/lib/go-1.24/bin/gofmt && \
#   go version

pkgname=go1.24.9.linux-$ARCH.tar.gz && \
  wget https://go.dev/dl/$pkgname && \
  tar -zxf $pkgname && rm -rf $pkgname && \
  $SUDO mv go /usr/lib/go-1.24 && \
  $SUDO update-alternatives --install /usr/bin/go go /usr/lib/golang/bin/go 116 --slave /usr/bin/gofmt gofmt /usr/lib/golang/bin/gofmt && \
  $SUDO update-alternatives --install /usr/bin/go go /usr/lib/go-1.21/bin/go 121 --slave /usr/bin/gofmt gofmt /usr/lib/go-1.21/bin/gofmt && \
  go version

go env GOPATH GOROOT && \
  mkdir -p $HOME/.config/go && \
  echo 'export GOPATH=$HOME/go' >> $HOME/.config/go/profile && \
  echo 'export PATH=$PATH:$GOPATH/bin' >> $HOME/.config/go/profile && \
  echo '. "$HOME/.config/go/profile"' | tee -a $HOME/.bashrc && \
  source $HOME/.bashrc && echo $PATH

go install golang.org/x/tools/gopls@latest && \
  go install honnef.co/go/tools/cmd/staticcheck@latest && \
  go install mvdan.cc/gofumpt@v0.2.1 && \
  go install github.com/go-delve/delve/cmd/dlv@v1.22.1 && \
  go install github.com/golang/mock/mockgen@v1.6.0 && \
  go install github.com/axw/gocov/gocov@v1.1.0 && \
  go install github.com/AlekSi/gocov-xml@v1.1.0

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

# install consul
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

# install compile deps
wget -O zlib-1.2.13.tar.gz https://zlib.net/fossils/zlib-1.2.13.tar.gz && \
  wget -O bzip2-1.0.6.tar.gz https://sourceware.org/pub/bzip2/bzip2-1.0.6.tar.gz && \
  wget -O zstd-1.4.8.tar.gz https://github.com/facebook/zstd/releases/download/v1.4.8/zstd-1.4.8.tar.gz && \
  wget -O lz4-1.8.3.tar.gz https://codeload.github.com/lz4/lz4/tar.gz/v1.8.3 && \
  wget -O snappy-1.1.7.tar.gz https://github.com/google/snappy/archive/refs/tags/1.1.7.tar.gz && \
  wget -O rocksdb-6.3.6.tar.gz https://github.com/facebook/rocksdb/archive/refs/tags/v6.3.6.tar.gz && \
  $SUDO mv -f zlib-1.2.13.tar.gz bzip2-1.0.6.tar.gz zstd-1.4.8.tar.gz lz4-1.8.3.tar.gz snappy-1.1.7.tar.gz rocksdb-6.3.6.tar.gz /usr/local/src
