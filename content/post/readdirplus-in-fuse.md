---
title: "FUSE 中的 readdirplus 优化"
author: "Chang Liu"
cover: "/images/cover.jpg"
tags: ["fuse", "filesystem"]
date: 2020-06-23T17:03:29+08:00
draft: false
---


使用 FUSE 将一个存储系统映射到本地文件系统时，都会遇到一个问题：默认的 ls 操作耗时特别长，用户体验特别糟糕。这里介绍我们优化 FUSE 中目录遍历的方法：通过支持 readdirplus 调用来上百倍的提升 ls 命令耗时。

<!--more-->

# 问题背景

# 解决方案

# 实现细节

