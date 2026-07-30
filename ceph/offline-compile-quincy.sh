#!/bin/bash

set -e

function correct_compile()
{
  sed -i 's/lua.hpp/lua5.4\/lua.hpp/g' src/cls/lua/cls_lua.cc
  sed -i 's/lua.hpp/lua5.4\/lua.hpp/g' src/cls/lua/cls_lua.h
  sed -i 's/lua.hpp/lua5.4\/lua.hpp/g' src/cls/lua/lua_bufferlist.cc
  sed -i 's/lua.hpp/lua5.4\/lua.hpp/g' src/test/cls_lua/test_cls_lua.cc
}

function unzip_submodules()
{
  local path_src=$1
  local path_dst=$2
  local dir_name=$3

  echo "extract $path_src to $path_dst/$dir_name ..."
  if [ ! -d "$path_dst"  ];then
    mkdir -p "$path_dst"
  fi
  rm -rf "${path_dst:?}/$dir_name"

  unzip -o -q "$path_src" -d "$path_dst"
  if [ "$dir_name" == "testing"  ];then
    mv "${path_dst:?}/arrow-$dir_name"-* "${path_dst:?}/$dir_name"
  elif [ "$dir_name" == "gtest"  ];then
    mv "${path_dst:?}/googletest"-* "${path_dst:?}/$dir_name"
  else
    mv "${path_dst:?}/$dir_name"-* "${path_dst:?}/$dir_name"
  fi
}

function unzip_uring()
{
  local path_src=$1
  local path_dst=$2
  local dir_name="$3"

  echo "extract $path_src to $path_dst/$dir_name ..."
  if [ ! -d "$path_dst"  ];then
    mkdir -p "$path_dst"
  fi
  rm -rf "${path_dst:?}/$dir_name"
  mkdir -p "${path_dst:?}/$dir_name"

  tar -zxf "$path_src" -C "$path_dst/$dir_name"
  cp -r "$path_dst/$dir_name/liburing-liburing-0.7"/* "$path_dst/$dir_name"
  rm -rf "$path_dst/$dir_name/liburing-liburing-0.7"
}

function unzip_srcs()
{
  unzip_submodules "$tar_pdir/ceph-erasure-code-corpus*.zip" "$cur_dir" "ceph-erasure-code-corpus"
  unzip_submodules "$tar_pdir/ceph-object-corpus*.zip" "$cur_dir" "ceph-object-corpus"
  unzip_submodules "$tar_pdir/src/arrow*.zip" "$cur_dir/src" "arrow"
  unzip_submodules "$tar_pdir/src/blkin*.zip" "$cur_dir/src" "blkin"
  unzip_submodules "$tar_pdir/src/c-ares*.zip" "$cur_dir/src" "c-ares"
  unzip_submodules "$tar_pdir/src/crypto/isa-l/isa-l_crypto*.zip" "$cur_dir/src/crypto/isa-l" "isa-l_crypto"
  unzip_submodules "$tar_pdir/src/dmclock*.zip" "$cur_dir/src" "dmclock"
  unzip_submodules "$tar_pdir/src/erasure-code/jerasure/gf-complete*.zip" "$cur_dir/src/erasure-code/jerasure" "gf-complete"
  unzip_submodules "$tar_pdir/src/erasure-code/jerasure/jerasure*.zip" "$cur_dir/src/erasure-code/jerasure" "jerasure"
  unzip_submodules "$tar_pdir/src/fmt*.zip" "$cur_dir/src" "fmt"
  unzip_submodules "$tar_pdir/src/googletest*.zip" "$cur_dir/src" "googletest"
  unzip_submodules "$tar_pdir/src/isa-l*.zip" "$cur_dir/src" "isa-l"
  unzip_submodules "$tar_pdir/src/libkmip*.zip" "$cur_dir/src" "libkmip"
  unzip_submodules "$tar_pdir/src/pybind/mgr/rook/rook-client-python*.zip" "$cur_dir/src/pybind/mgr/rook" "rook-client-python"
  unzip_submodules "$tar_pdir/src/rapidjson*.zip" "$cur_dir/src" "rapidjson"
  unzip_submodules "$tar_pdir/src/rocksdb*.zip" "$cur_dir/src" "rocksdb"
  unzip_submodules "$tar_pdir/src/s3select*.zip" "$cur_dir/src" "s3select"
  unzip_submodules "$tar_pdir/src/seastar*.zip" "$cur_dir/src" "seastar"
  unzip_submodules "$tar_pdir/src/spawn*.zip" "$cur_dir/src" "spawn"
  unzip_submodules "$tar_pdir/src/spdk*.zip" "$cur_dir/src" "spdk"
  unzip_submodules "$tar_pdir/src/utf8proc*.zip" "$cur_dir/src" "utf8proc"
  unzip_submodules "$tar_pdir/src/xxHash*.zip" "$cur_dir/src" "xxHash"
  unzip_submodules "$tar_pdir/src/zstd*.zip" "$cur_dir/src" "zstd"
  unzip_submodules "$tar_pdir/src/arrow/cpp/submodules/parquet-testing*.zip" "$cur_dir/src/arrow/cpp/submodules" "parquet-testing"
  unzip_submodules "$tar_pdir/src/arrow/arrow-testing*.zip" "$cur_dir/src/arrow" "testing"
  unzip_submodules "$tar_pdir/src/rapidjson/thirdparty/googletest*.zip" "$cur_dir/src/rapidjson/thirdparty" "gtest"
  unzip_submodules "$tar_pdir/src/seastar/dpdk*.zip" "$cur_dir/src/seastar" "dpdk"
  unzip_submodules "$tar_pdir/src/spawn/test/dependency/googletest*.zip" "$cur_dir/src/spawn/test/dependency" "googletest"
  unzip_submodules "$tar_pdir/src/spdk/dpdk*.zip" "$cur_dir/src/spdk" "dpdk"
  unzip_submodules "$tar_pdir/src/spdk/intel-ipsec-mb*.zip" "$cur_dir/src/spdk" "intel-ipsec-mb"
  unzip_submodules "$tar_pdir/src/spdk/isa-l*.zip" "$cur_dir/src/spdk" "isa-l"
  unzip_submodules "$tar_pdir/src/spdk/ocf*.zip" "$cur_dir/src/spdk" "ocf"
}

function do_cmake()
{
  rm -rf "$build_dir"
  mkdir "$build_dir"

  CI_MAKE_CHECK=true ./do_cmake.sh -DCMAKE_EXPORT_COMPILE_COMMANDS=ON -DWITH_CCACHE=ON \
    -DWITH_MANPAGE=OFF -DWITH_BABELTRACE=OFF -DWITH_MGR_DASHBOARD_FRONTEND=OFF \
    -DWITH_RBD=OFF -DWITH_KRBD=OFF -DWITH_RADOSGW=OFF -DWITH_SYSTEM_ZSTD=ON \
    -DWITH_SYSTEM_LIBURING=ON -DWITH_SYSTEM_BOOST=OFF -DWITH_SPDK=ON \
    -DCMAKE_BUILD_TYPE=Release

  unzip_uring "$tar_pdir/liburing-0.7.tar.gz" "$cur_dir/$build_dir/src" "liburing"
  sed -i '/liburing_ext-gitclone.cmake/d' "$build_dir"/build.ninja
  cp "$tar_pdir"/boost_1_75_0.tar.bz2 "$build_dir"/boost/src/
}

tar_pdir="/yzq-dev/tar/ceph/quincy-submodules"
cur_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
build_dir="build"

opt=$1

if [ -z "$opt" ]; then
  echo "Usage: $0 {all|cmake|release}"
  exit 1
fi

if [ "$opt" == "all" ];then
  unzip_srcs
  correct_compile
  do_cmake
elif [ "$opt" == "cmake" ] || [ "$opt" == "release" ];then
  do_cmake
else
  echo "invalid opt $opt, please use: all, cmake, or release"
  exit 1
fi
