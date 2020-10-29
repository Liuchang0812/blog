---
title: "[FUSE03] FUSE 中的 Splice 特性支持"
author: "Chang Liu"
tags: ["fuse", "splice"]
date: 2020-07-30T20:38:39+08:00
draft: false
---

FUSE 通过 `/dev/fuse` 块设备来完成数据在用户态和内核态的交换。FUSE 支持 splice 来实现 zero-copy

<!--more-->

FUSE 通过 `/dev/fuse` 块设备来完成数据在用户态和内核态的交换。FUSE 支持 splice 来实现 zero-copy。举例来说，如果你希望将 socket 中的一段数据写到 FUSE 的文件中，普通流程是：

1. 调用 read(socket) 将数据读到用户态
2. 调用 fuse_ops.write() 将数据传给 fuse
3. FUSE 通过 `/dev/fuse` 块设备将数据复制到内核态

如果 FUSE 实现支持 splice 的话，上面的三步就可以变成一步，直接告诉 FUSE 数据在 socket 的位置，FUSE 在内核中完成数据的消费，避免了数据的拷贝。

FUSE  使用 `fuse_buf` 表示一段数据，数据有两类，一种是使用文件句柄保存的，例如socket，一种是使用内存地址。完整定义如下：

```cpp
/**
 * Single data buffer
 *
 * Generic data buffer for I/O, extended attributes, etc...  Data may
 * be supplied as a memory pointer or as a file descriptor
 */
struct fuse_buf {
	size_t size;
	enum fuse_buf_flags flags;
	void *mem;
	int fd;
	off_t pos;
};
```



对于数据的复制，根据两端数据的类型不同，会调用不同的实现，只有当两端都是文件句柄的形式才会调用 splice 方式来实现 zero-copy。



```CPP
static ssize_t fuse_buf_copy_one(const struct fuse_buf *dst, size_t dst_off,
				 const struct fuse_buf *src, size_t src_off,
				 size_t len, enum fuse_buf_copy_flags flags)
{
	int src_is_fd = src->flags & FUSE_BUF_IS_FD;
	int dst_is_fd = dst->flags & FUSE_BUF_IS_FD;

	if (!src_is_fd && !dst_is_fd) {
		void *dstmem = dst->mem + dst_off;
		void *srcmem = src->mem + src_off;

		if (dstmem != srcmem) {
			if (dstmem + len <= srcmem || srcmem + len <= dstmem)
				memcpy(dstmem, srcmem, len);
			else
				memmove(dstmem, srcmem, len);
		}

		return len;
	} else if (!src_is_fd) {
		return fuse_buf_write(dst, dst_off, src, src_off, len);
	} else if (!dst_is_fd) {
		return fuse_buf_read(dst, dst_off, src, src_off, len);
	} else if (flags & FUSE_BUF_NO_SPLICE) {
		return fuse_buf_fd_to_fd(dst, dst_off, src, src_off, len);
	} else {
		return fuse_buf_splice(dst, dst_off, src, src_off, len, flags);
	}
}
```

## 使用 zero  copy 能否解决请求串行的问题

在 libfuse 自带示例中有一个 `passthrough_fh.c` 的实现，会将 FUSE 请求都转发到根目录下，数据读写都实现了 zero copy 。可以认为是在 FUSE 架构上能达到性能上限了。

![image-20200730204402715](https://assets-1252230511.cos.ap-guangzhou.myqcloud.com/uPic/2020-07/image-20200730204402715-lvbxmR-KJdIBE.png)

单独一个cp和并行cp 50个的耗时如上，从耗时上看，操作还是串行的。`/dev/fuse` 限制了文件系统的吞吐能力。

使用 Zero Copy也不会改善 FUSE 并行能力。但是可以大大的优化单个请求的延时，从来提高整体性能。



## 适配Splice接口的好处

以写操作为例，如果我们适配了 `write_buf` 接口，会复杂内存管理，带来的好处是少了一次内存申请与拷贝。对于 read_buf 则会减少两次内存申请。

```cpp
// int fuse_fs_write_buf()
if (fs->op.write_buf) {
			res = fs->op.write_buf(path, buf, off, fi);
		} else {
			void *mem = NULL;
			struct fuse_buf *flatbuf;
			struct fuse_bufvec tmp = FUSE_BUFVEC_INIT(size);

			if (buf->count == 1 &&
			    !(buf->buf[0].flags & FUSE_BUF_IS_FD)) {
				flatbuf = &buf->buf[0];
			} else {
				res = -ENOMEM;
				mem = malloc(size);
				if (mem == NULL)
					goto out;

				tmp.buf[0].mem = mem;
				res = fuse_buf_copy(&tmp, buf, 0);
				if (res <= 0)
					goto out_free;

				tmp.buf[0].size = res;
				flatbuf = &tmp.buf[0];
			}

			res = fs->op.write(path, flatbuf->mem, flatbuf->size,
					   off, fi);
out_free:
			free(mem);
		}

// int fuse_fs_read_buf()
		if (fs->op.read_buf) {
			res = fs->op.read_buf(path, bufp, size, off, fi);
		} else {
			struct fuse_bufvec *buf;
			void *mem;

			buf = malloc(sizeof(struct fuse_bufvec));
			if (buf == NULL)
				return -ENOMEM;

			mem = malloc(size);
			if (mem == NULL) {
				free(buf);
				return -ENOMEM;
			}
			*buf = FUSE_BUFVEC_INIT(size);
			buf->buf[0].mem = mem;
			*bufp = buf;

			res = fs->op.read(path, mem, size, off, fi);
			if (res >= 0)
				buf->buf[0].size = res;
		}
```