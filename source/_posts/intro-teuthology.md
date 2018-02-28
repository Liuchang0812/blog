---
title: teuthology 介绍与实现
date: 2018-01-26 16:05:30
tags:
    - ceph
    - teuthology
categories:
    - ceph
---



# teuthology 基本概念

一个集成测试的单位是 suite，一个 suite 由多个 task 组成。对于测试场景使用 yaml 文件来描述，例如 rados集成测试中的一个描述文件 ceph-qa-suite/suites/rados/basic/tasks/rados_striper.yaml 

```
tasks:
- install:
- ceph:
- exec:
   client.0:
   - ceph_test_rados_striper_api_io
   - ceph_test_rados_striper_api_aio
   - ceph_test_rados_striper_api_striping
```
其中，install, ceph, exec 都是在 teuthology 中定义好的 task，对应到  teuthology/teuthology/task/ 下的同名文件。


每个 task 的定义如下：

```
def task(ctx, config):
    pass
```

可以参考一个最简单的 [task: print](https://github.com/ceph/teuthology/blob/master/teuthology/task/print.py
)：

```
"""
Print task
"""
import logging

log = logging.getLogger(__name__)

def task(ctx, config):
    """
    Print out config argument in teuthology log/output
    """
    log.info('{config}'.format(config=config))
```

所以说，整个测试是使用 yaml 描述文件来描述测试场景，用户可以实现大量的 task 类型来满足各种测试场景。

## suite 描述

在一些测试场景下，我们可能希望枚举一个配置来完整的覆盖所有的测试。例如， ceph 的网络框架有 simple, async, rpc 三种，我们希望同一个测试场景分别在三个网络框架下跑一遍，要怎么办呢？ teuthology 通过如下方法来实现。

每个 suite 对应一个目录，如果目录下有如下文件：

1. "+"， 目录下有一个文件名为 + 的文件，则相当于把目录所有的 yaml 文件拼接到一起作为一个 yaml 描述文件
2. "%"，目录下有一个文件名为 % 的文件，则作矩阵运算。例如 foo 目录如下, 则相当于 test.yaml + net/simple.yaml  和 test.yaml + net/async.yaml 两个 yaml 描述文件。

```
foo/
     %
     test.yaml
     net/
          simple.yaml
          async.yaml
```

所以，典型的 suite 描述会将 部署模式、网络模式、测试等分别放到不同的目录，然后放置一个 % 文件来覆盖大量的测试场景。典型的例子可以看 suites/rados/basic 测试：
```
../qa/suites/rados/basic
├── %
├── ceph.yaml
├── clusters
│   ├── +
│   ├── fixed-2.yaml -> ../../../../clusters/fixed-2.yaml
│   └── openstack.yaml
├── mon_kv_backend -> ../../../mon_kv_backend
├── msgr
│   ├── async.yaml
│   ├── random.yaml
│   └── simple.yaml
├── msgr-failures
│   ├── few.yaml
│   └── many.yaml
├── objectstore -> ../../../objectstore
├── rados.yaml -> ../../../config/rados.yaml
└── tasks
    ├── rados_api_tests.yaml
    ├── rados_cls_all.yaml
    ├── rados_python.yaml
    ├── rados_stress_watch.yaml
    ├── rados_striper.yaml
    ├── rados_workunit_loadgen_big.yaml
    ├── rados_workunit_loadgen_mix.yaml
    ├── rados_workunit_loadgen_mostlyread.yaml
    ├── readwrite.yaml
    ├── repair_test.yaml
    ├── rgw_snaps.yaml
    └── scrub_test.yaml
```

# 常用的 task

## install

install task 负责安装程序包，通过在 yaml 文件中添加 install task 我们就可以完成特定版本的 ceph 安装。

## ceph

ceph 负责配置 ceph 环境，启停 ceph 之类的操作。其中关键的一些参数有：

1. log-whitelist 默认情况下， teuthology 会使用日志来决定测试是否成功，该参数可以白名单一些日志，支持正则
2. conf 配置 ceph 的参数

它还有一些子task，例如 restart、healthy（等待集群到 health状态）、wait_for_osds_up、wait_for_mon_quorum 等。

```
tasks:
      - ceph.restart: [osd.0, mon.1]
```
## workunit

执行指定目录下的测试脚本，下面的例子就是在所有的客户端机器上执行 direct_io/xattrs.sh/snaps 几个workunit。所有的 workunit 在 qa/workunits 目录下，如果指定的 workunit 目录下有 MakeFile 则先执行 make 命令，下面的 direct_io 就是一个 c 写的测试。

```
tasks:
        - ceph:
        - ceph-fuse:
        - workunit:
            tag: v0.47
            clients:
              all: [direct_io, xattrs.sh, snaps]
```

## exec，backgroud_exec

在特定机器上执行一个 shell 命令，区别是前后台

## rgw, tgt, hadoop 等

负责初始化这些组件的环境，部署并启动


# teuthology 架构与实现

本质上， teuthology 是一个很强大的任务执行平台，用户通过 yaml 文件来描述自己的任务， teuthology 负责解析 yaml 文件、调试机器去执行对应的任务，收集任务的日志并显示在一个叫pulpito的网页上。


## teuthology 实现

整个 teuthology 可以认为分为如下几块：

- 一个自动的包管理系统： https://www.xsky.com/tec/ceph-weekly-vol-59/，负责为每个版本的 ceph 提供一个 yum/apt 源服务
- 一个消息队列服务 beantalkd ： http://kr.github.io/beanstalkd/，负责存储作业描述消息， teuthology-scheduler 提交任务到消息队列，teuthology-worker 守护进程负责不停的轮询消费消息队列。
-  任务报告存储系统 paddles： https://github.com/ceph/paddles，负责在 pgsql 中存储任务的执行状态和机器结点的状态
- 前端展示太详细 pulpito：https://github.com/ceph/pulpito，负责渲染网页（并不能在线提交任务）
- 任务执行结点 teuthworker，部署 teuthology，监听任务队列，并向资源池分发任务
- 任务提交结点 teuthology，用来添加计算结点，提交任务，删除任务等



# 引用

1. http://docs.ceph.com/teuthology/docs/README.html


