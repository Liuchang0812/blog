---
title: "[FUSE02] 事件循环的实现"
author: "Chang Liu"
tags: ["fuse", "cpp"]
date: 2020-07-29T21:03:48+08:00
draft: false
---

FUSE 是如何实现内核与用户态的消息交互，完成整个事件循环的。

<!--more-->

[TOC]

# 概述

FUSE 是为了简化文件系统实现的技术。用户不需要在内核态进行开发，只需要按照约定实现一些回调接口，就可以实现一个可以挂载的文件系统。

整体 FUSE 可以分为三个部分：

1. 内核的 FUSE 模块。
2. libfuse 的开发库。
3. 用户实现部分。

内核的 FUSE 模块与用户态的FUSE实现，通过块设备 `/dev/fuse` 来完成消息交互。举例来说，用户使用一个 FUSE 实现，挂载了一个目录 `/mnt/fusedir`，当调用 `getattr /mnt/fusedir/a.txt` 时，会发生如下流程：

1. 操作系统调用 FUSE 内核模块；
2. FUSE 内核模块向 `/dev/fuse` 模块写入一条消息(`fuse_req`)；
3. 用户态的 FUSE 模块会从 `/dev/fuse` 读取消息；
4. 根据消息类型，调用对应的用户回调；
5. 向 `/dev/fuse` 写入回应消息。

# 关键函数

* `fuse_session_receive_buf_int`: 从 `/dev/fuse`读取消息，如果支持 `splice` 还会启用 `splice` 来实现 ZeroCopy。
* `fuse_session_process_buf_int`: 处理消息函数，调用用户回调，封装成消息写回 `/dev/fuse` 。

# 详细实现

## 单线程



单线程模式比较简单清晰，就是一个循环，不停的调用 `fuse_session_receive_buf_int` 和 `fuse_session_process_buf_int` ，实现如下：

```cpp
// libfuse/lib/fuse_loop.c
int fuse_session_loop(struct fuse_session *se)
{
	int res = 0;
	struct fuse_buf fbuf = {
		.mem = NULL,
	};

	while (!fuse_session_exited(se)) {
		// 注：从 /dev/fuse 块设备读取数据
    res = fuse_session_receive_buf_int(se, &fbuf, NULL);
		
		if (res == -EINTR)
			continue;
		if (res <= 0)
			break;
		// 注：解析数据并调用用户回调
		fuse_session_process_buf_int(se, &fbuf, NULL);
	}

	free(fbuf.mem);
	if(se->error != 0)
		res = se->error;
	fuse_session_reset(se);
	return res;
}
```

## 多线程

多线程的版本实现在 `libfuse/lib/fuse_loop_mt.c` 

* `fuse_worker` 一个工作线程，双向链表
* `fuse_mt` 纪录事件循环的相关配置与信息，例如是否开启 clone fd 特性，可用线程数，总线程数等。
* `fuse_chan` fuse channel，在开启 clone fd 特性时，使用 `fuse_chan`对应一个 `/dev/fuse` 的 clone fd

```cpp
int fuse_session_loop_mt() {
	struct fuse_mt mt;
  // 初始化 mt
  fuse_loop_start_thread(&mt);
  // 等待信号量和 fuse_worker退出
}

void* fuse_do_work() {
	fuse_session_receive_buf_int()
	// 如果没有空闲线程，创建一个线程
	fuse_loop_start_thread()
	fuse_session_process_buf_int()
}

int fuse_loop_start_thread() {
  // 创建一个 `fuse_worker`
  struct fuse_worker *w = malloc(sizeof(struct fuse_worker));
  fuse_start_thread(fuse_do_work);
}
```

