---
title: "FUSE 中的 readdirplus 优化"
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

实现上比较简单，但是需要用户指定最大cache数目，以及cache保留多久。需要用户来决定能接爱的多长时间的cache不一致性。

# 解决方案

在日常运营过程，用户反馈比较集中的也是元数据操作，包括上文所说的 ls 卡顿、find 卡顿、无法 tab 补全。

# 实现细节

