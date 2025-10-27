# Linux Script Manager

> 🐧 一个功能强大的Linux脚本管理工具，支持中英文双语，让你轻松组织和运行系统脚本。

[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Python](https://img.shields.io/badge/Python-3.6%2B-brightgreen.svg)](https://www.python.org/)
[![Platform](https://img.shields.io/badge/Platform-Linux-blue.svg)](https://www.linux.org/)
[![Language](https://img.shields.io/badge/Language-Python%20%7C%20Bash-brightgreen.svg)](#)

<div align="center">

[English](#-english) • [中文](#-中文)

</div>

---

## 📋 English

### Overview

Linux Script Manager is a modern, user-friendly GUI application designed to help Linux users quickly organize and execute shell scripts. It features a beautiful intuitive interface, supports multiple languages (Chinese/English), and works seamlessly across all major Linux distributions.

### ✨ Features

- 🎨 **Beautiful GUI Interface** - Modern dark theme with responsive design
- 🌐 **Multi-language Support** - Seamless Chinese/English switching at runtime
- 📦 **Universal Package Manager Support** - Works with apt, yum, dnf, zypper, pacman
- 🔐 **Sudo Permission Management** - Easily toggle admin rights for scripts with one click
- 🚀 **Quick Script Execution** - Launch scripts directly from the GUI with system integration
- 📱 **Cross-Platform Compatible** - Ubuntu, Debian, CentOS, Fedora, Arch, openSUSE and more
- 📝 **Bi-lingual Script Support** - Scripts can use mixed Chinese/English descriptions
- 🛠️ **Local Installation** - No system-wide installation needed, fully portable
- ⚡ **Zero Configuration** - Automatic system detection and dependency installation

### 📸 Screenshots


<img width="709" height="633" alt="截图_2025-10-27_13-43-20" src="https://github.com/user-attachments/assets/c459d53d-bd28-4b5d-879b-15440ebbd79c" />



### 🚀 Quick Start

#### Prerequisites
- Python 3.6+
- Linux (any major distribution)
- 100MB free disk space

#### Installation

```bash
# Clone the repository
git clone https://github.com/yourusername/linux-script-manager.git
cd linux-script-manager

# Make installation script executable
chmod +x install_linux_script_manager.sh

# Run installation (requires sudo for system dependencies)
./install_linux_script_manager.sh

# Start the application
./run.sh
```

#### First-time Setup
1. The installer will automatically detect your Linux distribution
2. Install required dependencies (Python3, Tkinter, Pillow)
3. Create a Python virtual environment
4. Create desktop shortcuts for easy access
5. Launch the application

### 📚 Usage

#### Adding Scripts
1. Place your `.sh` scripts in the `scripts/` directory
2. Scripts are automatically detected and displayed
3. Customize script information with comments:

```bash
#!/bin/bash
# My Backup Tool
# DESCRIPTION: Backup important files to external drive / 备份重要文件到外部驱动
# REQUIRES_SUDO: false

# Your script code here
echo "Backing up files..."
```

#### Script Metadata
Customize how scripts appear in the GUI:

```bash
# DISPLAY_NAME: Custom Script Name       # Display name
# DESCRIPTION: What this script does      # Description (supports mixed Chinese/English)
# REQUIRES_SUDO: true/false               # Admin rights needed (optional)
```

#### Toggling Script Permissions
- Click the permission label on any script card to instantly toggle between admin and user mode
- Changes are saved automatically
- Visual indicators show current permission level

#### Language Switching
- Click the language button at the bottom (中文/English) to switch languages
- All UI elements update instantly - no restart needed!

#### Advanced Features
- **Terminal Integration** - View output of scripts in terminal windows
- **Real-time Refresh** - Click "Refresh" to reload script list
- **Permission Management** - Toggle sudo requirements on-the-fly
- **Desktop Shortcuts** - Create quick-launch desktop icons

### 📁 Directory Structure

```
linux-script-manager/
├── linux_script_manager.py   # Main application
├── install.sh                # Installation script
├── run.sh                     # Launch script
├── scripts/                   # Your custom scripts directory
│   ├── backup-tool.sh
│   ├── network-diag.sh
│   └── ... (add your scripts here)
├── venv/                      # Python virtual environment
├── tmp/                       # Temporary files
└── README.md                  # This file
```

### 🔧 Configuration

The application requires minimal configuration. All settings are auto-detected:
- System package manager automatically detected
- Python virtual environment automatically created
- Dependencies automatically installed

Optional: Edit script descriptions directly in their headers.

### ⌨️ Command Line

```bash
# Start the application
./run.sh

# Or if installed system-wide
linux-script-manager

# Manual virtual environment activation
source venv/bin/activate
python3 linux_script_manager.py
```

### 🐛 Troubleshooting

**Issue: "Virtual environment not found"**
```bash
# Recreate virtual environment
rm -rf venv/
python3 -m venv venv
source venv/bin/activate
pip install pillow
```

**Issue: Missing dependencies**
```bash
# Reinstall dependencies
./install_linux_script_manager.sh
```

**Issue: Scripts not appearing**
1. Verify scripts are in the `scripts/` directory
2. Make sure files have `.sh` extension
3. Click "Refresh" button to reload
4. Check `install.log` for errors

**Issue: Cannot run scripts**
1. Check script has execute permission: `chmod +x script.sh`
2. Verify script shebang: `#!/bin/bash`
3. Check if script needs sudo permissions

### 📋 Supported Distributions

| Distribution | Package Manager | Status |
|---|---|---|
| Ubuntu / Debian | apt | ✅ Fully Supported |
| CentOS / RHEL | yum/dnf | ✅ Fully Supported |
| Fedora | dnf | ✅ Fully Supported |
| Arch Linux | pacman | ✅ Fully Supported |
| openSUSE | zypper | ✅ Fully Supported |
| Linux Mint | apt | ✅ Fully Supported |
| Elementary OS | apt | ✅ Fully Supported |
| Pop!_OS | apt | ✅ Fully Supported |

### 🔐 Security Notes

- Scripts run with your current user permissions by default
- Sudo is only used when explicitly enabled for a script
- No system-wide installation means no elevated privileges needed
- All configuration stored locally in application directory
- Source code is open and auditable

### 🤝 Contributing

Contributions are welcome! Here's how you can help:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

### 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

### Development Note

This project was developed with the assistance of AI tools (DeepSeek and Claude 4). The MIT License applies to the overall work that embodies the creative input of the author.

### 🙏 Acknowledgments

- Built with [Python](https://www.python.org/) & [Tkinter](https://docs.python.org/3/library/tkinter.html)
- Inspired by modern terminal tools and system utilities
- Thanks to all contributors and users

---

## 📋 中文

### 概述

Linux脚本管理器是一个现代化的Linux脚本管理工具，提供了美观直观的GUI界面。它支持多语言切换（中英文），适配所有主流Linux发行版，帮助用户轻松组织和执行shell脚本。

### ✨ 功能特性

- 🎨 **现代化GUI界面** - 精美的深色主题，反应迅速
- 🌐 **双语支持** - 运行时无缝切换中英文，全部界面动态更新
- 📦 **通用包管理器支持** - 支持apt、yum、dnf、zypper、pacman
- 🔐 **sudo权限管理** - 一键切换脚本的管理员权限
- 🚀 **快速脚本执行** - 直接从GUI启动脚本，系统集成
- 📱 **跨平台兼容** - 支持Ubuntu、Debian、CentOS、Fedora、Arch、openSUSE等
- 📝 **中英文混合脚本** - 脚本说明支持中英文混合
- 🛠️ **本地安装** - 无需系统级安装，完全便携化
- ⚡ **零配置启动** - 自动检测系统并安装依赖

### 📸 功能展示

<img width="709" height="634" alt="截图_2025-10-27_13-42-55" src="https://github.com/user-attachments/assets/8f0ed486-c250-4da1-8018-79d5fa76289d" />


### 🚀 快速开始

#### 系统要求
- Python 3.6+
- Linux系统（任何主流发行版）
- 100MB以上可用磁盘空间

#### 安装步骤

```bash
# 克隆仓库
git clone https://github.com/yourusername/linux-script-manager.git
cd linux-script-manager

# 赋予安装脚本执行权限
chmod +x install_linux_script_manager.sh

# 运行安装（系统依赖需要sudo）
./install_linux_script_manager.sh

# 启动应用
./run.sh
```

#### 首次安装
1. 安装器自动检测Linux发行版
2. 安装必要依赖（Python3、Tkinter、Pillow）
3. 创建Python虚拟环境
4. 创建桌面快捷方式
5. 启动应用程序

### 📚 使用指南

#### 添加脚本
1. 将`.sh`脚本文件放入`scripts/`目录
2. 脚本自动扫描并显示
3. 用注释自定义脚本信息：

```bash
#!/bin/bash
# 我的备份工具 / My Backup Tool
# DESCRIPTION: 备份重要文件到外部驱动 / Backup important files
# REQUIRES_SUDO: false

# 脚本代码
echo "正在备份文件..."
```

#### 脚本元数据说明
自定义脚本在界面中的显示方式：

```bash
# DISPLAY_NAME: 自定义脚本名称           # 显示名称
# DESCRIPTION: 脚本功能说明               # 描述（支持中英混合）
# REQUIRES_SUDO: true/false               # 是否需要管理员权限（可选）
```

#### 切换脚本权限
- 点击脚本卡片上的权限标签即可一键切换管理员/普通用户模式
- 更改自动保存
- 视觉指示器显示当前权限级别

#### 语言切换
- 点击底部语言按钮（中文/English）切换语言
- 所有UI元素实时更新 - 无需重启！

#### 高级功能
- **终端集成** - 在终端中查看脚本输出
- **实时刷新** - 点击"刷新"重新加载脚本列表
- **权限管理** - 动态切换sudo需求
- **桌面快捷方式** - 创建快速启动图标

### 📁 目录结构

```
linux-script-manager/
├── linux_script_manager.py   # 主程序
├── install.sh                # 安装脚本
├── run.sh                     # 启动脚本
├── scripts/                   # 自定义脚本目录
│   ├── backup-tool.sh
│   ├── network-diag.sh
│   └── ... (添加你的脚本)
├── venv/                      # Python虚拟环境
├── tmp/                       # 临时文件
└── README.md                  # 本说明文件
```

### 🔧 配置说明

应用需要最少的配置，大多数设置自动检测：
- 自动检测系统包管理器
- 自动创建Python虚拟环境
- 自动安装依赖
- 脚本描述可直接编辑脚本头部

### ⌨️ 命令行使用

```bash
# 启动应用
./run.sh

# 或系统级安装后
linux-script-manager

# 手动激活虚拟环境
source venv/bin/activate
python3 linux_script_manager.py
```

### 🐛 常见问题排查

**问题：虚拟环境未找到**
```bash
# 重新创建虚拟环境
rm -rf venv/
python3 -m venv venv
source venv/bin/activate
pip install pillow
```

**问题：缺少依赖**
```bash
# 重新安装依赖
./install_linux_script_manager.sh
```

**问题：脚本不显示**
1. 确认脚本在`scripts/`目录中
2. 确保文件扩展名为`.sh`
3. 点击"刷新"按钮重新加载
4. 查看`install.log`中的错误信息

**问题：无法运行脚本**
1. 检查脚本有无执行权限：`chmod +x script.sh`
2. 验证脚本shebang：`#!/bin/bash`
3. 检查脚本是否需要sudo权限

### 📋 支持的发行版

| 发行版 | 包管理器 | 状态 |
|---|---|---|
| Ubuntu / Debian | apt | ✅ 完全支持 |
| CentOS / RHEL | yum/dnf | ✅ 完全支持 |
| Fedora | dnf | ✅ 完全支持 |
| Arch Linux | pacman | ✅ 完全支持 |
| openSUSE | zypper | ✅ 完全支持 |
| Linux Mint | apt | ✅ 完全支持 |
| Elementary OS | apt | ✅ 完全支持 |
| Pop!_OS | apt | ✅ 完全支持 |

### 🔐 安全说明

- 脚本默认使用当前用户权限运行
- Sudo仅在明确启用时使用
- 本地安装无需系统级权限提升
- 所有配置本地保存在应用目录
- 源代码开放，可审计

### 🤝 贡献指南

欢迎贡献代码！流程如下：

1. Fork本仓库
2. 创建功能分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'Add AmazingFeature'`)
4. 推送分支 (`git push origin feature/AmazingFeature`)
5. 开启Pull Request

### 📄 许可证

本项目采用MIT许可证 - 详见[LICENSE](LICENSE)文件

### 开发说明

本项目使用AI工具（DeepSeek和Claude 4）辅助开发。MIT许可证适用于项目中体现了作者创造性劳动的整体作品。

### 🙏 致谢

- 基于[Python](https://www.python.org/)和[Tkinter](https://docs.python.org/3/library/tkinter.html)开发
- 灵感来自现代终端工具和系统实用程序
- 感谢所有贡献者和用户的支持

---

## 📞 联系方式

- 提交Issue报告问题
- 讨论功能需求
- Pull Request贡献代码

## ⭐ 如果你觉得这个项目有帮助，请给个Star！

---

**Made with ❤️ for the Linux Community**
