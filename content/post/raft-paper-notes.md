---
title: "Raft Paper Notes"
date: 2019-10-28T10:57:14+08:00
tags: ["raft"]
draft: false
---

介绍 raft 协议

<!--more-->

### 为什么要发明 RAFT 一致性协议？

因为 paxos 过于复杂，难以理解。同时，paxos 是面向学术和理论证明，没有在论文中介绍工程上的实现。如果要实现一个工业级的 paxos，要做很多优化拓展，例如 multi-paxos。为了解决这些问题， raft 是一个把可理解性、明确工程实现方法放在首要考虑地位的算法。


# RAFT 算法细节

raft 算法主要分为两个部分: 1)Leader Election; 2)Log Replication。


## 基本概念

1. term, 每次 leader 变更时就增长1。每个 term 内只会有一个 leader。时间的逻辑划分，用于 leader election。
2. RPC，不同结点之间通过 RPC 来通信，在 raft 中有两个 RPC: 1)RequestVote;2)AppendEntries。

## Leader Election

空的 AppendEntries RPC 被用来作为心跳包，由 Leader 发送给其它 Server，同时维持其的Leader角色（Leader Authority）。当一个 Server 在超过一定时间(election timeout)没有收来自Leader的心跳包，就认为 Leader 不存在，开始新一轮的选举。

选举的策略比较简单，每个 Server 在每个 Term 只给一个人投票，遵循先到先得的策略。为了尽量避免出现 split 投不出大多数的情况，每个 Server 都有一个随机的election timeout配置，来避免多个 Server 在同时发出 RequestVote 请求。

## Log Replication

committed log: 保证持久化的日志，不会因为机器故障等各类原因丢失该日志。并且该日志最终会被所有可用机器执行。

日志满足一个特性 Log Matching Property，类似于归纳法。对于不同的日志，只有他们的term和index相同,他们的内容一定相同。同时他们之前日志的内容也相同。

Consistency Check: When send- ing an AppendEntries RPC, the leader includes the index and term of the entry in its log that immediately precedes the new entries. If the follower does not find an entry in its log with the same index and term, then it refuses the new entries.

Leader 日志是immutable的，follower 的日志是可以覆盖的：

  a leader creates at most one entry with a given log index in a given term, and log entries never change their position in the log. 
  the leader handles inconsistencies by forcing the followers’ logs to duplicate its own. This means that conflicting entries in follower logs will be overwritten with entries from the leader’s log.

Leader 通过给 Follower 不停的发送 AppendEntries RPC 来找到 follower 的日志起点（term和index都相同）。

## Safety

Leader Completeness Property: the leader for any given term con- tains all of the entries committed in previous terms 
Leader Completeness Property: Leader Completeness Prop
