---
title: "raft paper reading"
author: "Chang Liu"
tags: ["raft", "algorithm", "distributed system"]

date: 2020-09-06T21:03:29+08:00
draft: false

---




<!--more-->



翻译对照表

* committed log entry: 已提交日志

## 5.4 Safety

之前已经介绍的算法并不能足够保证一致性。本节添加限制

### 5.4.1 选举限制

在任何 leader-based 一致性算法，leader最终储存所有已提交日志。

> all the committed entries from previous terms are present on each new leader from the moment of its election, without the need to transfer those entries to the leader.



### 5.4.2 commit

图8举了一个例子，在目前的限制下会覆盖已经提交的日志。

![img](https://assets-1252230511.cos.ap-guangzhou.myqcloud.com/uPic/2020-09/QQ%E6%88%AA%E5%9B%BE20181125102046-1024x974-MB44N4.jpg)

新加限制

> Raft never commits log entries from previous terms by count- ing replicas. Only log entries from the leader’s current term are committed by counting replicas



http://dev.poetpalace.org/?p=632

