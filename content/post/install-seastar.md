---
title: "Build and Link with SeaStar library"
date: 2019-09-26T11:49:09+08:00
draft: true 
---

## Build Seastar

```
git clone https://github.com/scylladb/seastar.git
cd seastar
git submodule update --init --recursive
apt udpate && ./install-dependencies.sh
./configure.py --mode=release --cook fmt
```


## Link with Seastar


```
apt install libunistring-dev
export seastar_dir=`pwd`
g++ my_app.cc $(pkg-config --libs --cflags --static $seastar_dir/build/release/seastar.pc) -o my_app
./my_app

```
