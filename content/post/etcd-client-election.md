---
title: "Etcd SDK 中的选主实现"
date: 2019-11-18T16:04:19+08:00
draft: false
---


一句话总结就是：每个会话在指定目录下创建一个键值对，谁先创建成功谁就是主。

<!--more-->


# 背景

我们在使用 etcd 时，会利用 etcd 来实现进程抢主的逻辑。 etcd go 的SDK提供了封装好的 concurrency 模块来简化分布式选主的实现。如下，是一个忽略了错误处理的选主实现示例。

{{< gist liuchang0812 0f453b3976de5d927eed083ee93bc0cc "election.go" >}}

那么，etcd clientv3 的 Election 具体是怎么实现的呢？如何保证在任意情况下只有一个实例成为 leader ？



# 内部实现

etcd 维护了一个全局递增的版本号，对应于每次原子修改。这个版本号称之为 Version。相应的，对于每个保存在 etcd 中的 Key 也保存了这个 Key 是在哪一个 Version 时创建的信息，称之为 CreateRevision。

当用户调用`Election.Campaign`方法时，etcd client 就会尝试创建一个 Key(如何已经存在，就不创建，直接取值)，并纪录下这个 Key 的 CreateRevision 。接着，etcd client会遍历指定目录下所有的版本小于 CreateRevision 的 Key。如果不存在小于 CreateRevision 的 Key，则说明当前创建的 Key 就是最早的 Key 了，该会话可以安全的成为 leader。否则，etcd client 会一直监听目录下这些小于 CreateRevision 的 Key，直到所有的 Key 都被删除。


{{< gist liuchang0812 0f453b3976de5d927eed083ee93bc0cc "waitDeletes.go" >}}
