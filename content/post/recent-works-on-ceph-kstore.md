---
title: "最近在 Ceph KStore 上的一些工作（2020-01-13）"
date: 2020-01-13T15:50:31+08:00
draft: false
toc: true
backtotop: true
---

# 背景


分享我们最近在 ceph kstore 上的一些工作。

<!--more-->

Ceph 目前自带了一些单机存储引擎，包括

* 基于文件的FileStore;
* 基于KV的KStore；
* 基于RocksDB+裸盘的BlueStore；
* 基于内存的测试用MemStore；
* 基于seastar实现的全用户态SeaStore。

这些单机存储引擎都有适用的用户场景和读写模型。对于海量小文件的场景下，KStore 是一个很好的选择，LSM 架构的 KV 引擎天然的将数据聚合为大文件，顺序的存储到磁盘中。但是，KStore 一直以来应用较少，社区在上面维护的资源也较小。

最近，我们希望在 Rocksdb 层面进行优化，让 Rocksdb 对 blob 写入进行优化。从而使得 KStore 不仅可以支持海量小文件，也可以较好的支持大文件。

# 让 RocksDB 支持 Blob 存储

原生的 RocksDB 其实不适合存储Blob（Value 较大），因为分层模型和日志的存在，数据放大会更明显，KV在执行后台compaction也会更慢。业界提出的解决方案主要就是“Key Value 分开存储”，这样可以独立对 Blob 文件进行优化，减少写放大和compaction影响。具体可以阅读 [Wisckey](https://www.usenix.org/system/files/conference/fast16/fast16-papers-lu.pdf) 的论文（阿里云应该在13年的时候就已经在内部KV实现了这类优化，支持其上OSS类BLOB业务)。

目前，PingCAP 公司基于 RocksDB 和 Wisckey 实现了一个 RocksDB 的插件 [TitanDB](https://github.com/tikv/titan). 上层程序可以简单的通过 Titan::DB 的命名空间来使用。因此，我们将Titan 替换原生的 RocksDB，使得 KStore 可以较好的存储大文件。

理论上，KStore 层面的代码完全不用修改，性能也不会有损耗。相对于 FileStore，没有 Double Write 的过程，性能更好。相对于 BlueStore，实现上更简单更易维护，对小文件更友善，性能类似。具体的性能报告待整理完善。

# Read Stripe Cache 导致的内存泄漏

* [issue地址](https://tracker.ceph.com/issues/39665)
* [PR地址](https://github.com/ceph/ceph/pull/32538)
* [与社区讨论地址](https://github.com/ceph/ceph/pull/28056)

这个问题在19年5月分的时候就已经提交到社区，中间因为同事转岗以及社区对read-cache是否有意义有分歧，拖到最近才合并到主线。

简单的讲，问题是KStore会为一个 transaction 的写入读取缓存 stripe，来保护一个事务中的写入只用更新内存。这块Cache会在事务结束的时候释放。但是在读文件的时候也有类似的Cache，但是读操作并不通过事务提交，这块儿内存没有释放。本质上读类操作并不需要 stripe cache，经过来来回回的讨论，大家终于达成一致，彻底在 read 操作中移除 stripe cache。


# Onode Cache 导致的内存泄漏

* [issue地址](https://tracker.ceph.com/issues/43436)
* [PR地址](https://github.com/ceph/ceph/pull/32446)

在KStore的实现中，每打开一个 RADOS obj都会在内存中缓存 onode 结构体。在长时间的测量中发现，内存占用会缓慢上涨，直到 OOM。通过代码阅读，怀疑是 Onode Cache 没有释放。直接 GDB 线上进程，可以发现每个 collection 缓存了 9k+ 的 Onode, 当前进程共打开了399个 collection。通过计算，这一块就占用了1.7GB的内存。

为了更好的观察 onode 的内存占用，我们添加了 mempool 对 KStore 的支持，可以直接通过 asock 命令来查看实时的 onode 个数与内存占用，对应的代码为[链接](https://github.com/ceph/ceph/pull/32446/commits/c3811eaba9444ee68612a88f900e70fb7948c5c1)。

查看了 BlueStore 的实现，会有一个后台线程 MempoolThread 周期的释放 Onode Cache，同时也会在读写操作时，根据 Cache 来释放一些 Onode Cache。目前，我们简单的添加了一个后台进程来周期的释放 Onode Cache，将来可以基于 mempool 来做更精细化的内存管控。


# Pending Stripes 并发访问的 SegFault Core

* [issue地址](http://tracker.ceph.com/issues/43520)
* [PR地址](https://github.com/ceph/ceph/pull/32540)

这个问题比较简单，在测试的时候遇到 OSD Core，通过 GDB 怀疑和 pending stripes 结构体的并发访问有关。加锁验证了一下，确实不会再出现 SegFault。于是修改为性能更好的读写锁。