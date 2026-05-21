# Linux Script Manager

> 🐧 一个以脚本为核心的 Linux 图形化管理工具 —— 管理器是外壳，脚本才是灵魂。

[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Python](https://img.shields.io/badge/Python-3.6%2B-brightgreen.svg)](https://www.python.org/)
[![Platform](https://img.shields.io/badge/Platform-Linux-blue.svg)](https://www.linux.org/)
[![Language](https://img.shields.io/badge/Language-Python%20%7C%20Bash-brightgreen.svg)](#)

---

## 💡 这是什么？

Linux Script Manager 是一个 Linux 图形化脚本管理器。它的核心理念很简单：**把你常用的 `.sh` 脚本收纳进来，一键点击执行，不需要每次打开终端机输入指令。**

管理器本身只是一个载体，真正有价值的是里面附带的脚本插件。每一支脚本都是针对实际使用场景设计的系统工具，涵盖 USB 管理、系统清理、网络调整、解压缩等日常需求。

---

## 📸 界面展示

<img width="1073" height="656" alt="截图 2026-05-21 10-19-51" src="https://github.com/user-attachments/assets/c34c6ee9-6f91-4f58-a735-d77811d6eeee" />


---

## 🚀 快速开始

### 系统要求

- Python 3.6+
- Linux（任何主流发行版）
- 约 100MB 可用磁盘空间

### 安装

```bash
# 克隆仓库
git clone https://github.com/yourusername/linux-script-manager.git
cd linux-script-manager

# 赋予安装脚本执行权限
chmod +x install_linux_script_manager.sh

# 运行安装（需要 sudo 安装系统依赖）
./install_linux_script_manager.sh

# 启动应用
./run.sh
```

安装器会自动完成以下步骤：
1. 检测你的 Linux 发行版
2. 安装所需依赖（Python3、Tkinter、Pillow）
3. 建立 Python 虚拟环境
4. 创建桌面快捷方式
5. 启动应用程序

---

## 🛠️ 内建脚本插件

这是这个项目真正的核心。以下脚本开箱即用，放入 `scripts/` 目录后直接在管理器中点击执行。

---

### 📦 智能批量解压 `auto-extract.sh`

自动搜索指定目录内所有压缩文件并逐一解压，支持无限递归——也就是说，压缩包里面还有压缩包，它会一层一层全部解开，直到没有新的压缩包为止。

**支持格式：** `.zip` `.rar` `.7z` `.tar` `.tar.gz` `.tgz` `.tar.bz2` `.tar.xz` `.gz` `.bz2` `.xz`

**主要功能：**
- 自动侦测系统并安装缺少的解压工具（unzip、unrar、7z 等）
- 支持统一密码批量解压
- 每个压缩包解压到同名文件夹，不会混乱
- 解压成功后自动删除原始压缩包
- 显示每轮解压进度与最终统计报告

**使用场景：** 收到一批打包好的压缩档，不想一个个手动解压。

---

### 🔧 USB 修复工具 `fix-usb.sh`

当 USB 随身碟出现无法挂载、文件系统错误、读写异常等问题时使用。

**支持文件系统：** FAT32、exFAT、NTFS、ext4

**主要功能：**
- 自动列出所有已连接的 USB 设备供选择
- 针对不同文件系统使用对应的修复工具（fsck、ntfsfix 等）
- 自动安装缺少的修复工具
- 适配所有主流 Linux 发行版（需要 sudo 权限）

**使用场景：** USB 随身碟在 Linux 下无法正常读写或挂载。

---

### 💾 USB 格式化工具 `format-usb.sh`

快速将 USB 随身碟格式化为指定文件系统。

**支持格式化格式：** FAT32、exFAT、NTFS、ext4

**主要功能：**
- 自动列出所有 USB 设备，选择后执行格式化
- 操作前要求用户确认，防止误操作
- 自动安装所需格式化工具
- 适配所有主流 Linux 发行版（需要 sudo 权限）

**使用场景：** 新买的随身碟、需要清空重置的 USB 设备。

---

### 🖥️ 制作 USB 开机启动盘 `make-bootable-usb.sh`

使用 `dd` 命令将系统镜像写入 USB，制作可开机的安装盘。

**主要功能：**
- 自动列出可用的 USB 设备供选择
- 支持选择任意 `.iso` 镜像文件
- 写入前显示详细确认信息，防止选错设备
- 写入完成后自动同步确保数据安全（需要 sudo 权限）

**使用场景：** 要安装新的 Linux 系统，需要制作开机 USB 启动盘。

---

### ☀️ 屏幕亮度控制 `screen-brightness-launcher.sh`

为没有内建亮度调节的 Linux 桌面环境提供亮度控制功能。

**主要功能：**
- 安装亮度控制工具（brightness-controller 或 xrandr 方案）
- 启动图形化亮度调节界面
- 支持卸载管理
- 不需要 sudo 权限即可运行

**使用场景：** 使用 Lubuntu、XFCE 等轻量桌面环境，键盘亮度键不起作用。

---

### 🧹 系统清理工具 `system-cleaner.sh`

清理 Linux 系统中积累的垃圾文件，释放磁盘空间。

**清理内容包括：**
- APT / DNF / Pacman / Zypper 的缓存与孤立包
- 系统日志（journald）
- 缩略图缓存
- 临时文件目录
- 回收站

**主要功能：**
- 自动侦测发行版并使用对应的包管理器
- 清理前显示预计释放空间
- 支持 Debian/Ubuntu、Fedora/RHEL/CentOS、Arch、openSUSE（需要 sudo 权限）

**使用场景：** 系统用久了磁盘空间不足，想快速清理。

---

### 📶 WiFi 电源管理 `wifi-power.sh`

查看并调整 WiFi 网卡的省电模式，解决 Linux 下 WiFi 不稳定的常见问题。

**主要功能：**
- 显示当前 WiFi 电源管理状态
- 一键切换「性能模式」（关闭省电）或「省电模式」
- 设置重启后持续生效（写入系统配置）
- 适用于笔记本电脑 WiFi 断线、延迟高等问题（需要 sudo 权限）

**使用场景：** WiFi 频繁断线、延迟不稳定，怀疑是系统省电设定造成的干扰。

---

## 📂 如何添加自己的脚本

这个管理器完全开放，你可以把自己写的任何 `.sh` 脚本放进来使用。

1. 将脚本文件放入 `scripts/` 目录
2. 点击管理器底部的「刷新」按钮
3. 脚本卡片自动出现，点击「启动工具」执行

### 自定义脚本显示信息

在脚本文件开头加入以下注释，管理器会自动读取并显示：

```bash
#!/bin/bash
# DISPLAY_NAME: 我的备份工具         # 卡片上显示的名称
# DESCRIPTION: 备份重要文件到外部硬盘  # 卡片上显示的描述
# REQUIRES_SUDO: false               # 是否需要 sudo 权限（true/false）
```

### 权限切换

点击脚本卡片右下角的权限标签，可以即时切换「需要管理员权限」和「普通权限」，更改会自动写回脚本文件。

---

## 📁 目录结构

```
linux-script-manager/
├── linux_script_manager.py        # 主程序
├── install_linux_script_manager.sh # 安装脚本
├── run.sh                          # 启动脚本
├── scripts/                        # 脚本目录（放你的 .sh 文件）
│   ├── auto-extract.sh
│   ├── fix-usb.sh
│   ├── format-usb.sh
│   ├── make-bootable-usb.sh
│   ├── screen-brightness-launcher.sh
│   ├── system-cleaner.sh
│   └── wifi-power.sh
├── venv/                           # Python 虚拟环境
└── README.md
```

---

## 📋 支持的 Linux 发行版

| 发行版 | 包管理器 | 状态 |
|---|---|---|
| Ubuntu / Debian / Linux Mint | apt | ✅ 完全支持 |
| Lubuntu / Xubuntu / Pop!_OS | apt | ✅ 完全支持 |
| CentOS / RHEL | yum / dnf | ✅ 完全支持 |
| Fedora | dnf | ✅ 完全支持 |
| Arch Linux | pacman | ✅ 完全支持 |
| openSUSE | zypper | ✅ 完全支持 |

---

## 🐛 常见问题

**脚本不显示？**
- 确认文件在 `scripts/` 目录内
- 确认扩展名为 `.sh`
- 点击「刷新」按钮重新扫描

**无法执行脚本？**
```bash
chmod +x scripts/你的脚本.sh
```

**虚拟环境找不到？**
```bash
rm -rf venv/
./install_linux_script_manager.sh
```

---

## 🔐 安全说明

- 脚本默认以当前用户权限执行
- 仅在脚本明确标注 `REQUIRES_SUDO: true` 时才会使用 sudo
- 所有代码开放，可自行审查
- 无需系统级安装，完全在应用目录内运行

---

## 📄 许可证

本项目采用 MIT 许可证 — 详见 [LICENSE](LICENSE) 文件。

本项目使用 AI 工具（DeepSeek 和 Claude）辅助开发。MIT 许可证适用于体现了作者创造性劳动的整体作品。

---

**Made with ❤️ for the Linux Community**
