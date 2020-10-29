---
title: "使用docker作为开发环境"
author: "Chang Liu"
tags: ["docker"]
date: 2020-07-06T11:22:55+08:00
draft: false
---

纪录自己使用容器作为开发环境的常用命令。

<!--more-->

举例来说，使用ubuntu作为开发环境，同时把本地目录挂载到容器中，让容器一直运行在后台。

```bash
docker run  -t --name leveldb --net=host  -w "/root/workspace" -v "`pwd`:/root/workspace/leveldb" ubuntu /bin/sh -c "echo Container started ; while sleep 1; do :; done"
```

在需要使用容器时，使用 exec 命令进入容器。

```bash
docker exec -it leveldb bash
```
