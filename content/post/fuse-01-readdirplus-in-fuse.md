---
title: "[FUSE01] readdirplus 优化"
author: "Chang Liu"
tags: ["fuse", "filesystem"]

date: 2020-06-23T17:03:29+08:00
draft: false
---


使用 FUSE 将一个存储系统映射到本地文件系统时，都会遇到一个问题：默认的 ls 操作耗时特别长，用户体验特别糟糕。这里介绍我们优化 FUSE 中目录遍历的方法：通过支持 readdirplus 调用来上百倍的提升 ls 命令耗时。

<!--more-->

# 问题背景

对于分布式存储系统来说，为了方便用户的接入使用，会提供对应的 fuse 实现。用户通过 fuse 将存储系统挂载到本地目录，就可以像使用普通文件系统一样来使用。这样，使用者就可以0成本的无感知的从本地迁移到云上。

但是，现实和理想还是有一定的差距。在使用 FUSE 过程中。大家都至少会遇到下面这个问题：FUSE 目录下的 ls 操作耗时严重。

例如在 [OSS](https://help.aliyun.com/document_detail/32196.html?spm=a2c4g.11186623.6.762.7a402e080pEApn)/[COS](https://cloud.tencent.com/document/product/436/6883) 的文档中都标注了这句话：

> 元数据操作，例如list directory，因为需要远程访问OSS服务器，所以性能较差。

## 本质问题

在典型的FUSE实现中，对于一次 ls 目录操作，FUSE执行的回调依次为：

* opendir
* readdir
* 对每个文件执行 getattr
* closedir

整个过程是串行的，对于每次 getattr 都需要发送网络请求的话。对于一个比较大的目录，例如目录下有10W个文件。完成一次 ls 操作，就是要串行的完成10W+次RPC调用。所以耗时会比较严重，用户侧的体验非常糟糕。

## 一些优化

为了优化这个问题，思路也比较明确。就是要减少 getattr 的耗时。在内存中 cache 住文件的 st 信息，避免产生网络请求。

实现上比较简单，但是需要用户指定最大cache数目，以及cache保留多久。需要用户来决定能接受多长时间的cache不一致性。例如 [moosefs](https://linux.die.net/man/8/mfsmount) 允许用户使用如下参数指定相关cache过期时间

> -o mfsattrcacheto=SEC
>  set attributes cache timeout in seconds (default: 1.0)
> -o mfsentrycacheto=SEC
>  set file entry cache timeout in seconds (default: 0.0, i.e. no cache)
> -o mfsdirentrycacheto=SEC
>  set directory entry cache timeout in seconds (default: 1.0)

# 解决方案

理论上，在执行 readdir 的时候，可以同时把文件的ST信息也生成了。之后串行的对每个文件 getattr 是没有必要的。所以我们期望从机制上直接去掉 getattr 操作。

在 NFS 的[标准](https://tools.ietf.org/html/rfc1813#page-80) 中，提出了 READDIRPLUS 的解决方案。

>       Procedure READDIRPLUS retrieves a variable number of
>      entries from a file system directory and returns complete
>      information about each along with information to allow the
>      client to request additional directory entries in a
>      subsequent READDIRPLUS.  READDIRPLUS differs from READDIR
>      only in the amount of information returned for each
>      entry.  In READDIR, each entry returns the filename and
>      the fileid.  In READDIRPLUS, each entry returns the name,
>      the fileid, attributes (including the fileid), and file
>      handle. 

同样的，FUSE 也从 3.0 版本开始支持了 readdirplus 。只需要实现 readdirplus 回调，就可以大大的优化 FUSE 的目录遍历体验。遗憾的是，文件和示例非常非常稀缺，对于实现 readdirplus 的细节描述的很不清晰。

# 实现细节

## 普通 readdir 的实现简介

在实现普通的 readdir 时，是通过向 fuse 注册一个回调函数实现的。当用户在目录下执行 ls 命令时，fuse 会调用你设置的回调函数。其中，有一个参数为名字为fuse_fill_dir_t的函数指针，你通过这个函数指针填充文件列表。完整的函数声明如下

```cpp
typedef int(* fuse_fill_dir_t) (void *buf, const char *name, const struct stat *stbuf, off_t off, enum fuse_fill_dir_flags flags)
/*
Function to add an entry in a readdir() operation

The off parameter can be any non-zero value that enables the filesystem to identify the current point in the directory stream. It does not need to be the actual physical position. A value of zero is reserved to indicate that seeking in directories is not supported.

Parameters
buf	the buffer passed to the readdir() operation
name	the file name of the directory entry
stat	file attributes, can be NULL
off	offset of the next entry or zero
flags	fill flags
Returns
1 if buffer is full, zero otherwise
*/
```

这里要注意的细节是 off 参数。对于简单实现来说，你可以直接设置 off 为0，在一次readdir调用中将所有的文件列表填充，不关心 fuse_fill_dir_t 的返回值。也可以返回明确的 off !=0 ，并判断 fuse_fill_dir_t 的返回值，当返回 1 的时候退出。


## 实现 readdirplus 

当你需要实现 readdirplus 时，有以下四个关键点：

1. fuse_fill_dir_t 中的 fuse_fill_dir_flags 应该为 FUSE_FILL_DIR_PLUS(2);
2. fuse_fill_dir_t 中的 off 应该不为0，并且每个文件全局唯一；
3. 需要判断 fuse_fill_dir_t 调用的返回值，当返回1时，要正常退出；
4. readdir 的参数 offset 可能会回退，要保证函数的可重入。

当完成这些后，一次 ls 目录操作就会对应到FUSE层面的:opendir->readdir*N->releasedir。不会再对每个文件产生 getattr 操作。