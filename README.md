# ssh_hello
连接 SSH 时展示服务器状态、连接信息，以及自定义的 ASCII 艺术字 Banner。

##  新特性
- **动态 ASCII 艺术字**：安装时可自定义显示的 Banner 文本（如主机名、项目名）。
- **颜色选择**：支持 7 种颜色的艺术字（红/绿/黄/蓝/紫/青/白）。
- **自动依赖安装**：脚本会自动检测并安装 `figlet` 工具（支持 Debian/RedHat/Arch 系发行版）。

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
- 需要 root 权限写入 `/etc/profile.d/ssh_hello.sh` 并设置执行权限。
- `figlet` 用于生成 ASCII 艺术字；脚本会尝试使用 `apt-get` / `yum` / `dnf` / `pacman` 自动安装。
- 若非 root 且系统无 `sudo`，会跳过自动安装并回退为普通文本显示。

## 卸载与更新
- **卸载**：`rm -f /etc/profile.d/ssh_hello.sh`，然后重新登录。
- **更新**：重新执行安装命令即可覆盖旧版本。

## 效果展示
![ssh效果](https://img.maodeyu.fun/blog/ssh_info_screent.webp)

> 安装完成后，请断开 SSH 并重新连接以查看效果。
