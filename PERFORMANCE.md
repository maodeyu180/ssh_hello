# SSH 欢迎页的性能与兼容性排查

## 结论

旧版有明确的阻塞路径，主要是每次登录同步扫描登录历史和认证日志，且没有超时。系统适配问题会触发额外回退、错误解析或字段缺失，进一步放大等待。是否正好命中某台慢机器，仍需要在该机器上计时；本次验证只在本地隔离容器执行。

## 旧版的具体卡点

以下位置对应修改前的 `173c7e5` 版本：

| 位置 | 行为 | 影响 |
| --- | --- | --- |
| `ssh_info.sh:101` | `last -Fi >/dev/null` 探测参数，没有 `-n` | 即使忽略输出，仍会读取 wtmp 历史；每次登录必经 |
| `ssh_info.sh:130–134` | `grep ... auth.log/secure` 或无范围的 `journalctl`，最后才 `tail -2` | `tail` 无法让前面的命令提前结束；可能遍历整个认证日志/历史 journal |
| `ssh_info.sh:153–198` | 登录失败统计，journal 无条数上限；文件日志全量读取 | 被大量密码尝试刷日志或长时间未登录时，统计量增大 |
| `ssh_info.sh:193–198` | awk 无 `mktime` 时，每条失败记录调用两次 `date` | 精简系统/旧 awk 上可能产生大量子进程 |
| `ssh_info.sh:83,212,226,255` | 两次 `df`，加上 `top`、`ps` | 增加磁盘和进程扫描开销；这些命令也没有超时 |

`last` 的 `-n` 限制的是返回的登录记录数量；对于历史稀疏的用户，仍可能扫描较多 wtmp 数据，因此需要同时设置超时。[util-linux last 手册](https://www.man7.org/linux/man-pages/man1/last.1%40%40util-linux.html)

原来的两个 `_SYSTEMD_UNIT=` 同字段条件是 OR，写法本身有效；问题在读取范围。journal 默认只显示当前调用者可读的记录，所以欢迎页统计也只能覆盖可读范围。[systemd journalctl 官方文档源码](https://raw.githubusercontent.com/systemd/systemd/main/man/journalctl.xml)

## 适配方面的问题

- `/etc/profile.d` 可能被 dash/ash 加载，旧代码却使用 `==`、`local` 和不统一的 `echo -e` 行为。
- GNU `date -d`、`last -F`、`awk mktime` 和 `top -bn1` 的可用性、格式并不统一。BusyBox 的 `last` 可能不支持带上限的参数，此时应跳过，不能退回无限制查询。
- 依靠 `grep -v File` 排除 `df` 表头、依靠 `Mem`/`Swap` 或 `top` 英文字段，受 locale 和工具版本影响。
- `grep -v lo` 过滤的是所有包含 `lo` 的接口名；取“第一个接口”也不能保证是本次 SSH 使用的接口。
- 没有记录时查询其他用户的历史，可能把别人的登录显示为自己的上次登录。
- 仅判断 `SSH_CONNECTION` 会让 `ssh host command` 等非交互登录也执行采集；欢迎页输出还会混入命令结果。
- Banner 被直接插入双引号脚本，文本中的命令替换可能在后续登录时执行。新版按单引号字面量写入。

## 修改后的等待与统计边界

慢查询使用 `timeout -k 1 1`：正常响应终止信号的命令约 1 秒跳过，忽略终止信号的命令约 2 秒强制结束。这个限制作用于单次查询，多个慢项目仍可能累加，不是整个欢迎页的 1 秒总预算。缺失或不兼容的 timeout 不触发无保护回退。[GNU timeout 官方文档源码](https://raw.githubusercontent.com/coreutils/coreutils/master/doc/coreutils.texi)

密码失败改为近期有限日志的摘要，界面明确显示范围，不再宣称完整覆盖“自上次登录以来”。不支持 wtmp/last 时，上次登录信息允许缺失。完整认证审计应单独查询，避免让每次打开 shell 都承担历史统计的成本。

CPU 占用来自 100ms 采样。容器中的 `/proc` 信息可能反映宿主机资源，当前实现没有按 cgroup 配额折算 CPU、内存；普通 Linux 主机不受这个容器口径影响。macOS/BSD 不在完整系统状态展示的支持范围内。

## 本地验证

2026-09-15，在已有的 Debian 13（`python:3.12-slim`）和 Alpine 3.20 容器中验证：

| 环境 | 测试 | 模拟正常查询 | 模拟 `last` 睡眠 10 秒 |
| --- | --- | --- | --- |
| Debian / dash | 17 项通过 | 0.12 秒 | 1.12 秒 |
| Debian / Bash | 17 项通过 | 0.13 秒 | 1.13 秒 |
| Alpine / BusyBox ash | 17 项通过 | 0.11 秒 | 1.12 秒 |

计时读取容器 `/proc/uptime`，不含 Docker 启动时间。`df`、`who`、`last` 和 journal 使用固定测试数据或故障注入，CPU/内存等读取真实 `/proc`。这些数字验证脚本开销和超时行为，不代表实际服务器登录耗时，也不能据此断言慢机器只存在这一处问题。

## 在慢机器上定位

先区分等待发生的位置：

- 如果 SSH 认证完成后、欢迎页/提示符出现之前卡住，这个脚本可能参与了等待。
- 如果在认证完成前就卡住，欢迎页通常尚未执行，需要继续检查 SSH 建连、认证、PAM 等阶段。

客户端可用 `ssh -vvv 用户@主机` 观察认证阶段。已有会话中，以下只读命令可分别测量旧版最重的两类查询；每条都限制在 3 秒，避免诊断本身长时间阻塞：

```bash
time timeout -k 1 3 last -Fi >/dev/null
time timeout -k 1 3 journalctl --no-pager \
  _SYSTEMD_UNIT=sshd.service _SYSTEMD_UNIT=ssh.service >/dev/null
time timeout -k 1 3 df -Pk / >/dev/null
```

追踪已安装欢迎页时，GNU/Linux 上可在现有终端执行：

```bash
timeout -k 1 8 bash --noprofile --norc -ic \
  'PS4="+ \${EPOCHREALTIME:-\$SECONDS} "; set -x; . /etc/profile.d/ssh_hello.sh'
```

这是执行一次欢迎页并打印命令及时间标记，不修改配置、不重启服务。未设置 `SSH_CONNECTION` 或标准输出不是终端时，新版会跳过采集。追踪内容可能包含 IP、用户名和登录记录，分享结果前按需脱敏。
