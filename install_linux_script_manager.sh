#!/bin/bash

###############################################################################
# Linux Script Manager - 本地安装脚本
# 无需系统权限，支持所有主流Linux发行版
# 自动检测系统并安装到本地目录
###############################################################################

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# 脚本名称和版本
SCRIPT_NAME="linux_script_manager.py"
APP_NAME="Linux Script Manager"
VENV_DIR="venv"
LOG_FILE="install.log"
LOCAL_TMP_DIR="tmp"
DESKTOP_FILE="linux-script-manager.desktop"

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 日志函数
log() {
    echo -e "${GREEN}[$(date +'%H:%M:%S')]${NC} $1" | tee -a "$SCRIPT_DIR/$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[$(date +'%H:%M:%S')] WARNING:${NC} $1" | tee -a "$SCRIPT_DIR/$LOG_FILE"
}

error() {
    echo -e "${RED}[$(date +'%H:%M:%S')] ERROR:${NC} $1" | tee -a "$SCRIPT_DIR/$LOG_FILE"
}

info() {
    echo -e "${BLUE}[$(date +'%H:%M:%S')] INFO:${NC} $1" | tee -a "$SCRIPT_DIR/$LOG_FILE"
}

success() {
    echo -e "${PURPLE}[$(date +'%H:%M:%S')] SUCCESS:${NC} $1" | tee -a "$SCRIPT_DIR/$LOG_FILE"
}

# 创建本地临时目录
setup_local_tmp() {
    mkdir -p "$SCRIPT_DIR/$LOCAL_TMP_DIR"
    log "创建本地临时目录: $SCRIPT_DIR/$LOCAL_TMP_DIR"
}

# 检测Linux发行版
detect_distro() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        DISTRO=$ID
        VERSION=$VERSION_ID
    elif [[ -f /etc/debian_version ]]; then
        DISTRO="debian"
    elif [[ -f /etc/redhat-release ]]; then
        DISTRO="rhel"
    elif [[ -f /etc/arch-release ]]; then
        DISTRO="arch"
    else
        DISTRO="unknown"
    fi
    
    log "检测到系统: $DISTRO ${VERSION:-unknown}"
}

# 检查包管理器
setup_package_manager() {
    case $DISTRO in
        ubuntu|debian|linuxmint|pop)
            PKG_MANAGER="apt"
            PKG_UPDATE="apt update"
            PKG_INSTALL="apt install -y"
            PKG_SEARCH="apt-cache search"
            PYTHON_PKG="python3"
            ;;
        fedora|centos|rhel|rocky|almalinux)
            if command -v dnf &> /dev/null; then
                PKG_MANAGER="dnf"
                PKG_UPDATE="dnf check-update || true"
                PKG_INSTALL="dnf install -y"
                PKG_SEARCH="dnf search"
            else
                PKG_MANAGER="yum"
                PKG_UPDATE="yum check-update || true"
                PKG_INSTALL="yum install -y"
                PKG_SEARCH="yum search"
            fi
            PYTHON_PKG="python3"
            ;;
        arch|manjaro|endeavouros)
            PKG_MANAGER="pacman"
            PKG_UPDATE="pacman -Sy"
            PKG_INSTALL="pacman -S --noconfirm"
            PKG_SEARCH="pacman -Ss"
            PYTHON_PKG="python"
            ;;
        opensuse*|suse)
            PKG_MANAGER="zypper"
            PKG_UPDATE="zypper refresh"
            PKG_INSTALL="zypper install -y"
            PKG_SEARCH="zypper search"
            PYTHON_PKG="python3"
            ;;
        *)
            error "不支持的发行版: $DISTRO"
            exit 1
            ;;
    esac
    
    log "包管理器: $PKG_MANAGER"
}

# 检查脚本文件
check_script() {
    if [[ ! -f "$SCRIPT_DIR/$SCRIPT_NAME" ]]; then
        error "找不到脚本文件: $SCRIPT_DIR/$SCRIPT_NAME"
        error "请确保 $SCRIPT_NAME 与此安装脚本在同一目录下"
        exit 1
    fi
    log "脚本文件检查通过: $SCRIPT_DIR/$SCRIPT_NAME"
}

# 检查命令
check_command() {
    command -v "$1" &> /dev/null
}

# 检查Python模块
check_python_module() {
    local module=$1
    local venv_python="$SCRIPT_DIR/$VENV_DIR/bin/python3"
    
    if [[ -f "$venv_python" ]]; then
        "$venv_python" -c "import $module" 2>/dev/null
    else
        python3 -c "import $module" 2>/dev/null
    fi
}

# 检查虚拟环境
check_virtual_env() {
    local venv_path="$SCRIPT_DIR/$VENV_DIR"
    if [[ -d "$venv_path" ]] && [[ -f "$venv_path/bin/python3" ]]; then
        log "虚拟环境已存在: $venv_path"
        return 0
    else
        return 1
    fi
}

# 检查系统包是否已安装
check_system_package() {
    local package=$1
    case $PKG_MANAGER in
        apt)
            dpkg -l | grep -q "^ii.*$package " 2>/dev/null || return 1
            ;;
        dnf|yum)
            rpm -q "$package" &>/dev/null || return 1
            ;;
        pacman)
            pacman -Q "$package" &>/dev/null || return 1
            ;;
        zypper)
            zypper search -i "$package" | grep -q "^i " 2>/dev/null || return 1
            ;;
        *)
            return 1
            ;;
    esac
}

# 检查系统依赖
check_system_dependencies() {
    info "检查系统依赖..."
    
    local required_packages=("python3" "python3-pip" "python3-venv" "python3-tk")
    local missing_packages=()
    
    for package in "${required_packages[@]}"; do
        # 转换包名为系统特定的名称
        local pkg_name="$package"
        case $PKG_MANAGER in
            dnf|yum|zypper)
                pkg_name=$(echo "$package" | sed 's/-/_/g')
                ;;
            pacman)
                if [[ "$package" == "python3-pip" ]]; then
                    pkg_name="python-pip"
                elif [[ "$package" == "python3-venv" ]]; then
                    pkg_name="python-virtualenv"
                elif [[ "$package" == "python3-tk" ]]; then
                    pkg_name="python-tkinter"
                elif [[ "$package" == "python3" ]]; then
                    pkg_name="python"
                fi
                ;;
        esac
        
        if ! check_system_package "$pkg_name"; then
            missing_packages+=("$package")
        else
            log "✓ $package 已安装"
        fi
    done
    
    if [[ ${#missing_packages[@]} -gt 0 ]]; then
        warn "缺少以下系统包: ${missing_packages[*]}"
        return 1
    else
        log "所有系统依赖已安装"
        return 0
    fi
}

# 安装系统依赖
install_system_dependencies() {
    info "准备安装系统依赖..."
    
    local required_packages=("python3" "python3-pip" "python3-venv" "python3-tk")
    
    case $PKG_MANAGER in
        apt)
            packages="python3 python3-pip python3-venv python3-tk python3-pil"
            ;;
        dnf|yum)
            packages="python3 python3-pip python3-venv python3-tkinter python3-pillow"
            ;;
        pacman)
            packages="python python-pip python-virtualenv python-tkinter python-pillow"
            ;;
        zypper)
            packages="python3 python3-pip python3-virtualenv python3-tk python3-Pillow"
            ;;
    esac
    
    warn "需要管理员权限安装系统包: $packages"
    warn "请输入密码以继续..."
    echo
    
    if sudo $PKG_INSTALL $packages; then
        success "系统依赖安装完成"
    else
        error "系统依赖安装失败"
        return 1
    fi
}

# 创建虚拟环境
setup_virtual_env() {
    local venv_path="$SCRIPT_DIR/$VENV_DIR"
    
    if ! check_virtual_env; then
        log "创建Python虚拟环境: $venv_path"
        cd "$SCRIPT_DIR"
        python3 -m venv "$VENV_DIR"
    fi
    
    # 激活虚拟环境并升级pip
    source "$venv_path/bin/activate"
    log "升级pip..."
    pip install --upgrade pip setuptools wheel
    
    success "虚拟环境设置完成"
}

# 检查Python依赖
check_python_dependencies() {
    info "检查Python依赖..."
    
    local modules=(
        "tkinter"
        "PIL"
    )
    
    for module in "${modules[@]}"; do
        if check_python_module "$module"; then
            log "✓ $module 已安装"
        else
            return 1
        fi
    done
    
    return 0
}

# 安装Python依赖
install_python_dependencies() {
    log "安装Python依赖包..."
    
    # 激活虚拟环境
    source "$SCRIPT_DIR/$VENV_DIR/bin/activate"
    
    # 设置临时目录
    export TMPDIR="$SCRIPT_DIR/$LOCAL_TMP_DIR"
    
    # 安装依赖
    local packages=(
        "Pillow"
    )
    
    for package in "${packages[@]}"; do
        log "安装 $package..."
        if pip install "$package"; then
            log "✓ $package 安装成功"
        else
            warn "✗ $package 安装失败"
        fi
    done
    
    success "Python依赖安装完成"
}

# 验证安装
verify_installation() {
    info "验证安装..."
    
    source "$SCRIPT_DIR/$VENV_DIR/bin/activate"
    
    local test_modules=(
        "tkinter"
        "PIL:Pillow图像库"
    )
    
    for test in "${test_modules[@]}"; do
        module=${test%%:*}
        description=${test##*:}
        
        if python3 -c "import $module" 2>/dev/null; then
            log "✓ $description ($module)"
        else
            error "✗ $description ($module) - 导入失败"
            return 1
        fi
    done
    
    success "环境验证通过"
    return 0
}

# 创建启动脚本
create_launcher() {
    local launcher="$SCRIPT_DIR/run.sh"
    
    cat > "$launcher" << 'EOF'
#!/bin/bash
# Linux Script Manager - 本地启动脚本

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 激活虚拟环境
if [[ -f "$SCRIPT_DIR/venv/bin/activate" ]]; then
    source "$SCRIPT_DIR/venv/bin/activate"
else
    echo "错误: 虚拟环境未找到，请重新运行安装脚本"
    exit 1
fi

# 设置环境变量
export TMPDIR="$SCRIPT_DIR/tmp"
export PATH="$(pwd)/venv/bin:$PATH"

# 启动应用
exec python3 "linux_script_manager.py"
EOF
    
    chmod +x "$launcher"
    success "启动脚本已创建: $launcher"
}

# 创建桌面快捷方式
create_desktop_shortcut() {
    local launcher="$SCRIPT_DIR/run.sh"
    local icon_path="$SCRIPT_DIR/linux-tool-menu-ico.png"
    
    # 创建直接启动脚本到home目录
    local direct_launcher="$HOME/.local/bin/linux-script-manager"
    mkdir -p "$HOME/.local/bin"
    
    cat > "$direct_launcher" << EOF
#!/bin/bash
cd "$SCRIPT_DIR"
./run.sh
EOF
    
    chmod +x "$direct_launcher"
    log "创建启动器: $direct_launcher"
    
    # 创建桌面快捷方式
    local desktop_file="$HOME/Desktop/$DESKTOP_FILE"
    local menu_dir="$HOME/.local/share/applications"
    
    mkdir -p "$HOME/Desktop" "$menu_dir"
    
    local desktop_content="[Desktop Entry]
Version=1.0
Type=Application
Name=$APP_NAME
Comment=Quick access and manage Linux scripts
Exec=$direct_launcher
Icon=$icon_path
Terminal=false
StartupNotify=true
Categories=Utility;System;
Path=$SCRIPT_DIR"
    
    echo "$desktop_content" > "$desktop_file"
    chmod +x "$desktop_file"
    
    cp "$desktop_file" "$menu_dir/$DESKTOP_FILE"
    
    success "桌面快捷方式已创建: $desktop_file"
    log "应用菜单快捷方式: $menu_dir/$DESKTOP_FILE"
}

# 显示完成信息
show_completion_info() {
    echo
    echo -e "${CYAN}=========================================${NC}"
    echo -e "${CYAN}  $APP_NAME 安装完成${NC}"
    echo -e "${CYAN}=========================================${NC}"
    echo
    echo -e "${GREEN}✓ 虚拟环境已配置${NC}"
    echo -e "${GREEN}✓ 依赖已安装${NC}"
    echo -e "${GREEN}✓ 启动脚本已创建${NC}"
    echo
    echo -e "${YELLOW}使用方法:${NC}"
    echo -e "  1. 双击桌面快捷方式启动"
    echo -e "  2. 或运行: ${BLUE}$SCRIPT_DIR/run.sh${NC}"
    echo -e "  3. 或在终端: ${BLUE}linux-script-manager${NC}"
    echo
    echo -e "${YELLOW}目录结构:${NC}"
    echo -e "  $SCRIPT_DIR/"
    echo -e "  ├── linux_script_manager.py     # 主程序"
    echo -e "  ├── run.sh                       # 启动脚本"
    echo -e "  ├── venv/                        # Python虚拟环境"
    echo -e "  ├── scripts/                     # 脚本目录"
    echo -e "  ├── tmp/                         # 临时文件目录"
    echo -e "  └── install.log                  # 安装日志"
    echo
    echo -e "${YELLOW}首次使用:${NC}"
    echo -e "  1. 将 .sh 脚本文件放入 scripts/ 目录"
    echo -e "  2. 应用会自动扫描并显示脚本"
    echo -e "  3. 点击按钮快速运行脚本"
    echo
    echo -e "${YELLOW}注意:${NC}"
    echo -e "  • 这是本地安装，不需要系统权限"
    echo -e "  • 所有文件保存在: $SCRIPT_DIR"
    echo -e "  • 可直接删除目录卸载"
    echo -e "  • 详细日志: $SCRIPT_DIR/install.log"
    echo
}

# 清理旧日志
cleanup_old_logs() {
    > "$SCRIPT_DIR/$LOG_FILE"
}

# 主函数
main() {
    echo -e "${CYAN}=========================================${NC}"
    echo -e "${CYAN}  $APP_NAME - 本地安装程序${NC}"
    echo -e "${CYAN}  支持: Ubuntu/Debian, CentOS, Fedora, Arch, openSUSE${NC}"
    echo -e "${CYAN}  无需系统权限，本地安装模式${NC}"
    echo -e "${CYAN}=========================================${NC}"
    echo
    
    cleanup_old_logs
    
    # 系统检测
    detect_distro
    setup_package_manager
    
    # 基础检查
    check_script
    
    # 创建本地临时目录
    setup_local_tmp
    
    # 环境检查
    local need_system_install=false
    local need_venv_setup=false
    local need_python_install=false
    
    # 检查系统依赖
    if ! check_system_dependencies; then
        need_system_install=true
    fi
    
    # 检查虚拟环境
    if ! check_virtual_env; then
        need_venv_setup=true
        need_python_install=true
    else
        if ! check_python_dependencies; then
            need_python_install=true
        fi
    fi
    
    # 执行安装
    if [[ "$need_system_install" == "true" ]]; then
        echo
        read -p "需要安装系统依赖，是否继续? (Y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            install_system_dependencies
        else
            error "用户取消安装"
            exit 1
        fi
    fi
    
    if [[ "$need_venv_setup" == "true" ]]; then
        setup_virtual_env
    fi
    
    if [[ "$need_python_install" == "true" ]]; then
        install_python_dependencies
    fi
    
    # 验证安装
    if ! verify_installation; then
        error "环境验证失败"
        exit 1
    fi
    
    # 创建启动脚本
    create_launcher
    
    # 创建桌面快捷方式
    create_desktop_shortcut
    
    # 显示完成信息
    show_completion_info
    
    # 询问是否立即启动
    echo
    read -p "是否立即启动应用? (Y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        echo
        "$SCRIPT_DIR/run.sh"
    else
        success "安装完成，随时可通过快捷方式启动应用"
    fi
}

# 信号处理
trap 'error "脚本被中断"; exit 1' INT TERM

# 运行主函数
main "$@"