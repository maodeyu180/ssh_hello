# ssh_hello
连接 SSH 时展示服务器状态、连接信息，以及自定义的 ASCII 艺术字 Banner。

## 特性
- **动态 ASCII 艺术字**：安装时可自定义显示的 Banner 文本（如主机名、项目名）。
- **颜色选择**：支持 7 种颜色的艺术字（红/绿/黄/蓝/紫/青/白）。
- **清屏与居中**：显示欢迎页前先清屏，艺术字按本次登录的终端宽度整体居中，保留字形对齐。
- **自动依赖安装**：脚本会自动检测并安装 `figlet` 工具（支持 Debian/RedHat/Arch 系发行版）。
- **限制登录等待**：磁盘、终端、登录历史和认证日志查询带超时，日志只读取近期有限范围。
- **兼容登录 shell**：生成的欢迎页使用 POSIX sh，只在交互式 SSH 且输出为终端时执行。

## SSH 登录慢？

旧版每次登录会先执行一次全量 `last -Fi` 来探测参数，必要时还会扫描整个认证日志或历史 journal。所有查询都在显示提示符之前同步执行，又没有超时；历史记录多、存储慢时会明显拖延登录。

新版做了这些调整：

- `last` 最多返回当前用户的 20 条记录，取消全量参数探测；工具不支持时显示无可用记录。
- journal 只查过去 24 小时内最近最多 1000 条；文件日志只读末尾 256KiB 中最后 1000 行。
- `df`、`who`、`last`、`journalctl` 和读取日志文件的 `tail`，单次查询 1 秒后终止；忽略终止信号的命令再等 1 秒后强制结束。多个慢查询的等待仍会累加。
- 直接读取 `/proc` 获取系统状态，CPU 采用两次相隔 100ms 的采样，取消 `top`、`ps`、`free` 及重复 `df` 调用。
- 从 `SSH_CONNECTION` 读取本次连接的服务器地址，避免多网卡选错接口，也支持 IPv6。
- Banner 按纯文本安全写入，不解释其中的 `$()`、引号和反引号；安装使用临时文件和原子替换。

详细原因、兼容性边界及慢机器上的定位方法见 [PERFORMANCE.md](PERFORMANCE.md)。

##  使用方式
该脚本为交互式安装脚本，运行后请根据提示输入自定义文本和选择颜色。

1. **获取 root 权限**：`su` 或 `sudo -s`
2. **执行一键安装命令**：

### 海外服务器
```bash
curl -o ssh_info.sh -sSL https://raw.githubusercontent.com/maodeyu180/ssh_hello/main/ssh_info.sh && bash ssh_info.sh
```

### 国内服务器
```bash
curl -o ssh_info.sh -sSL https://ghfast.top/https://raw.githubusercontent.com/maodeyu180/ssh_hello/main/ssh_info.sh && bash ssh_info.sh
```

## 权限与依赖说明
- 系统安装需要有权限写入 `/etc/profile.d/ssh_hello.sh`，通常用 root；文件设置为 `644`，由登录 shell 读取，不需要执行权限。
- 安装器需要 Bash；生成的欢迎页兼容 Bash、dash 和 BusyBox ash，面向提供 `/proc` 的 Linux。
- `figlet` 仅用于安装时生成艺术字；root 安装时会尝试使用 `apt-get` / `dnf` / `yum` / `pacman` 安装。加 `--no-install-deps` 可跳过依赖安装。
- 运行时使用系统已有的 `timeout`（需支持 `-k`）；没有该工具时，跳过可能阻塞的查询，仍显示基础信息。不会在登录时安装依赖或访问网络。
- 在支持的终端中先执行 `clear`；不可用时使用清屏控制序列，`TERM=dumb` 或未设置时跳过清屏。艺术字宽度优先从当前终端读取，再回退到 `COLUMNS` 或 80 列；窗口比艺术字窄时不额外缩进。

### 统计口径

- **密码失败**：统计所示可读日志范围内所有用户的 `Failed password` 记录，不再表示“自上次登录以来的全部失败次数”。文件日志回退未按时间筛选；超过上限的记录不会计入。无权限、命令失败或超时时显示无法统计。
- **上次登录**：当前用户最近 20 条 wtmp 记录中的 SSH 终端记录，跳过本次终端的最新记录。系统未写入 wtmp、没有历史或 `last` 不支持参数时显示无可用记录，不再全量搜索日志补齐。
- **在线终端**：`who` 中的 `pts/` 终端数，可能包含本地终端，不等同于 sshd 网络连接数。
- **设备 IP**：本次 SSH 连接的服务器端地址，不枚举所有网卡地址。

### 本地生成（不安装）

```bash
bash ssh_info.sh --output ./ssh_hello.preview.sh
sh -n ./ssh_hello.preview.sh
```

`--output` 自动跳过依赖安装；只有在交互式 SSH 中 source 预览文件才会显示欢迎页。

### 测试

测试需要本机已有 Python 3、Docker 和对应镜像，无需安装 Python 依赖。每个用例使用隔离容器和项目内临时目录，不写本机 `/etc/profile.d`。

```bash
python3 -m unittest discover -s tests -v
SSH_HELLO_TEST_SHELL=/bin/bash python3 -m unittest discover -s tests -v
SSH_HELLO_TEST_IMAGE=alpine:3.20 python3 -m unittest discover -s tests -v
```

默认镜像为 `python:3.12-slim`，默认 shell 为 `/bin/sh`。测试覆盖慢命令终止、忽略 TERM、缺失工具、日志截断、旧版参数、非交互静默、调用方状态保留和 Banner 特殊字符。

## 卸载与更新
- **卸载**：`rm -f /etc/profile.d/ssh_hello.sh`，然后重新登录。
- **更新**：重新执行安装命令即可覆盖旧版本。

## 效果展示
![ssh效果](https://img.maodeyu.fun/blog/ssh_info_screent.webp)

> 安装完成后，请断开 SSH 并重新连接以查看效果。
