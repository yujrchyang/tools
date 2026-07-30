#!/bin/bash

set -e

function correct_compile()
{
  # shellcheck disable=SC2016
  sed -i '3a\
\
  list(APPEND rocksdb_CMAKE_ARGS -DWITH_LIBURING=${WITH_LIBURING})\
  if(WITH_LIBURING)\
    list(APPEND rocksdb_CMAKE_ARGS -During_INCLUDE_DIR=${URING_INCLUDE_DIR})\
    list(APPEND rocksdb_CMAKE_ARGS -During_LIBRARIES=${URING_LIBRARY_DIR})\
    list(APPEND rocksdb_INTERFACE_LINK_LIBRARIES uring::uring)\
  endif()\
' cmake/modules/BuildRocksDB.cmake

  sed -i 's/lua.hpp/lua5.4\/lua.hpp/g' ./src/cls/lua/cls_lua.cc
  sed -i 's/lua.hpp/lua5.4\/lua.hpp/g' ./src/cls/lua/cls_lua.h
  sed -i 's/lua.hpp/lua5.4\/lua.hpp/g' ./src/cls/lua/lua_bufferlist.cc
  sed -i 's/lua.hpp/lua5.4\/lua.hpp/g' ./src/test/cls_lua/test_cls_lua.cc

  sed -i 's|list(APPEND cflags -D'\''__Pyx_check_single_interpreter\\(ARG\\)=ARG \\#\\# 0'\''|list(APPEND cflags -D'\''__Pyx_check_single_interpreter\\(ARG\\)=ARG\\#\\#0'\''|' cmake/modules/Distutils.cmake
  sed -i 's|                      -D'\''__Pyx_check_single_interpreter\\(ARG\\)=ARG \\#\\# 0'\''\\")|                      -D'\''__Pyx_check_single_interpreter\\(ARG\\)=ARG\\#\\#0'\''\\")|' cmake/modules/Distutils.cmake
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
  elif [ "$dir_name" == "idl"  ];then
    mv "${path_dst:?}/jaeger"-* "${path_dst:?}/$dir_name"
  else
    mv "${path_dst:?}/$dir_name"-* "${path_dst:?}/$dir_name"
  fi
}

function download_dependency()
{
  local LOCAL_FILE_SERVER="http://10.64.17.130:9527/cmain_arch/"
  rm -rf slicer_cmain_makecheck.tar slicer_cmain_makecheck

  echo "downloading dependency ..."
  curl --fail -O "${LOCAL_FILE_SERVER}"/slicer_cmain_makecheck.tar
  tar -xf slicer_cmain_makecheck.tar

  echo "copying submodules ..."
  cp slicer_cmain_makecheck/liburing-0.7.tar.gz .
  cp slicer_cmain_makecheck/boost_1_73_0.tar.bz2 .
  cp slicer_cmain_makecheck/pmdk-1.10.tar.gz .
}

function copy_submodules()
{
  tar_pdir="/yzq-dev/tar/ceph/pacific-submodules"
  cur_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

  unzip_submodules "$tar_pdir/ceph-erasure-code-corpus*.zip" "$cur_dir" "ceph-erasure-code-corpus"
  unzip_submodules "$tar_pdir/ceph-object-corpus*.zip" "$cur_dir" "ceph-object-corpus"
  unzip_submodules "$tar_pdir/src/blkin*.zip" "$cur_dir/src" "blkin"
  unzip_submodules "$tar_pdir/src/c-ares*.zip" "$cur_dir/src" "c-ares"
  unzip_submodules "$tar_pdir/src/civetweb*.zip" "$cur_dir/src" "civetweb"
  unzip_submodules "$tar_pdir/src/crypto/isa-l/isa-l_crypto*.zip" "$cur_dir/src/crypto/isa-l" "isa-l_crypto"
  unzip_submodules "$tar_pdir/src/dmclock*.zip" "$cur_dir/src" "dmclock"
  unzip_submodules "$tar_pdir/src/erasure-code/jerasure/gf-complete*.zip" "$cur_dir/src/erasure-code/jerasure" "gf-complete"
  unzip_submodules "$tar_pdir/src/erasure-code/jerasure/jerasure*.zip" "$cur_dir/src/erasure-code/jerasure" "jerasure"
  unzip_submodules "$tar_pdir/src/fmt*.zip" "$cur_dir/src" "fmt"
  unzip_submodules "$tar_pdir/src/googletest*.zip" "$cur_dir/src" "googletest"
  unzip_submodules "$tar_pdir/src/isa-l*.zip" "$cur_dir/src" "isa-l"
  unzip_submodules "$tar_pdir/src/jaegertracing/jaeger-client-cpp*.zip" "$cur_dir/src/jaegertracing" "jaeger-client-cpp"
  unzip_submodules "$tar_pdir/src/jaegertracing/jaeger-client-cpp/jaeger-idl*.zip" "$cur_dir/src/jaegertracing/jaeger-client-cpp" "idl"
  unzip_submodules "$tar_pdir/src/jaegertracing/opentracing-cpp*.zip" "$cur_dir/src/jaegertracing" "opentracing-cpp"
  unzip_submodules "$tar_pdir/src/jaegertracing/thrift*.zip" "$cur_dir/src/jaegertracing" "thrift"
  unzip_submodules "$tar_pdir/src/libkmip*.zip" "$cur_dir/src" "libkmip"
  unzip_submodules "$tar_pdir/src/pybind/mgr/rook/rook-client-python*.zip" "$cur_dir/src/pybind/mgr/rook" "rook-client-python"
  unzip_submodules "$tar_pdir/src/rapidjson*.zip" "$cur_dir/src" "rapidjson"
  unzip_submodules "$tar_pdir/src/rapidjson/thirdparty/googletest*.zip" "$cur_dir/src/rapidjson/thirdparty" "gtest"
  unzip_submodules "$tar_pdir/src/rocksdb*.zip" "$cur_dir/src" "rocksdb"
  unzip_submodules "$tar_pdir/src/s3select*.zip" "$cur_dir/src" "s3select"
  unzip_submodules "$tar_pdir/src/seastar*.zip" "$cur_dir/src" "seastar"
  unzip_submodules "$tar_pdir/src/seastar/dpdk*.zip" "$cur_dir/src/seastar" "dpdk"
  unzip_submodules "$tar_pdir/src/spawn*.zip" "$cur_dir/src" "spawn"
  unzip_submodules "$tar_pdir/src/spawn/test/dependency/googletest*.zip" "$cur_dir/src/spawn/test/dependency" "googletest"
  unzip_submodules "$tar_pdir/src/spdk*.zip" "$cur_dir/src" "spdk"
  unzip_submodules "$tar_pdir/src/spdk/dpdk*.zip" "$cur_dir/src/spdk" "dpdk"
  unzip_submodules "$tar_pdir/src/spdk/intel-ipsec-mb*.zip" "$cur_dir/src/spdk" "intel-ipsec-mb"
  unzip_submodules "$tar_pdir/src/spdk/isa-l*.zip" "$cur_dir/src/spdk" "isa-l"
  unzip_submodules "$tar_pdir/src/spdk/ocf*.zip" "$cur_dir/src/spdk" "ocf"
  unzip_submodules "$tar_pdir/src/xxHash*.zip" "$cur_dir/src" "xxHash"
  unzip_submodules "$tar_pdir/src/zstd*.zip" "$cur_dir/src" "zstd"
}

function do_cmake()
{
  [ -d build ] && rm -rf build
  mkdir build

  CI_MAKE_CHECK=true ./do_cmake.sh -DCMAKE_EXPORT_COMPILE_COMMANDS=ON -DWITH_CCACHE=ON \
    -DWITH_SYSTEM_BOOST=ON -DWITH_PYTHON3=3 -DWITH_MANPAGE=OFF \
    -DWITH_BABELTRACE=OFF -DWITH_MGR_DASHBOARD_FRONTEND=OFF \
    -DWITH_RBD=OFF -DWITH_KRBD=OFF -DWITH_RADOSGW=OFF \
    -DWITH_LIBURING=OFF -DCMAKE_BUILD_TYPE=Release

  # echo "copying boost ..."
  # cp ./boost_1_73_0.tar.bz2 build/boost/src/

  echo "copying liburing ..."
  mkdir -p build/src/liburing
  tar -zxf liburing-0.7.tar.gz -C build/src/liburing
  cp -r build/src/liburing/liburing-liburing-0.7/* build/src/liburing/

  echo "copying ceph-detect-init-virtualenv ..."
  cp -r slicer_cmain_makecheck/ceph-detect-init-virtualenv build

  echo "copying ceph-disk-virtualenv ..."
  cp -r slicer_cmain_makecheck/ceph-disk-virtualenv build

  echo "copying mgr-virtualenv ..."
  cp -r slicer_cmain_makecheck/mgr-virtualenv build
}

opt=$1
if [ -z "$opt" ]; then
  echo "Usage: $0 {all|submodules|cmake}"
  exit 1
fi

if [ "$opt" == "all" ];then
  download_dependency
  copy_submodules
  correct_compile
  do_cmake
elif [ "$opt" == "submodules"  ];then
  copy_submodules
elif [ "$opt" == "cmake" ];then
  do_cmake
else
  echo "invalid opt $opt, please use: all, submodules, or cmake"
  exit 1
fi
