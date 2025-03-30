# Linux 一键安装 Clash
## 一键安装


```bash
git clone --branch test --depth 1 https://gh-proxy.com/https://github.com/wujean/clash-for-linux-install.git \
  && cd clash-for-linux-install \
  && bash -c '. install.sh; exec bash'
```

### 命令一览

执行 `clash` 列出开箱即用的快捷命令。

```bash
$ clash
Usage:
    clash                    命令一览
    clashon                  开启代理
    clashoff                 关闭代理
```

### 优雅启停

```bash
$ clashoff
😼 已关闭代理环境

$ clashon
😼 已开启代理环境
```