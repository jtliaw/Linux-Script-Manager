#!/bin/bash
# printer-manager-launcher.sh
# DESCRIPTION: 智能打印机助手 (包含Samba/Linux网络共享全依赖自愈补齐)

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

print_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
print_step()    { echo -e "${CYAN}➜${NC} $1"; }
print_header()  { echo -e "${WHITE}$1${NC}"; }

###############################################################################
# 路径定义（动态适配 Linux-Script-Manager 架构）
###############################################################################

LAUNCHER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL_DIR="$LAUNCHER_DIR/printer"

if [ ! -d "$TOOL_DIR" ]; then
    TOOL_DIR="$LAUNCHER_DIR"
fi

GUI_SCRIPT="$TOOL_DIR/printer-manager-gui.py"
BASH_SCRIPT="$TOOL_DIR/printer-helper.sh"

# 独立的标记文件，防止软件升级、改名时清除安装记录
INSTALL_FLAG="$HOME/.config/linux-script-manager/printer_installed.flag"

mkdir -p "$HOME/.config/linux-script-manager"

# 🛠️ 核心功能：智能体检全套底层插件（含Windows共享与Linux间IPP互联依赖）
check_all_plugins() {
    local missing=0
    
    # 1. 基础打印核心
    if ! command -v cups-config &>/dev/null && ! command -v lpadmin &>/dev/null; then missing=1; fi
    # 2. Windows 共享打印依赖
    if ! command -v smbclient &>/dev/null; then missing=1; fi
    if ! python3 -c "import smbc" &>/dev/null 2>&1; then missing=1; fi
    # 3. Linux 之间相互共享、网络广播探测依赖 (防轻量系统阉割)
    if ! command -v avahi-browse &>/dev/null; then missing=1; fi
    
    return $missing
}

is_installed() {
    # 只有标记文件存在，且全套核心插件体检通过，才算真正安装完整
    if [ -f "$INSTALL_FLAG" ] && check_all_plugins; then
        return 0
    else
        return 1
    fi
}

# 首次运行、环境不全或手动重装时，提权装配全套全功能万能打印环境
do_install_deps() {
    echo ""
    print_header "========================================================="
    print_header "   正在初始化 Linux 智能打印万能驱动与共享网络环境...   "
    print_header "========================================================="
    print_step "此操作将为您全面检测并补齐所有缺失的底层插件："
    echo -e "   - ${CYAN}打印核心${NC}: CUPS 守护进程与万能开源驱动库 (Gutenprint 等)"
    echo -e "   - ${CYAN}Windows 共享${NC}: smbclient 与 Python-smbc 核心交互协议"
    echo -e "   - ${CYAN}Linux 间共享${NC}: Avahi 局域网智能广播发现与万能转换过滤器"
    echo ""
    print_warning "由于需要向系统部署驱动和底层组件，接下来请配合输入系统管理员密码："
    
    # 执行静默环境构建与满血补全
    if command -v apt-get &>/dev/null; then
        sudo apt-get update
        # 一口气把 Windows 共享和 Linux 广播、过滤器依赖全部焊死补齐
        sudo apt-get install -y cups cups-client printer-driver-gutenprint printer-driver-all \
                               foomatic-db-engine smbclient python3-smbc python3-tk \
                               avahi-utils cups-browsed cups-filters libsmbclient
    elif command -v dnf &>/dev/null; then
        sudo dnf install -y cups cups-client samba-client python3-smbc python3-tkinter avahi
    else
        # 其余系统尝试通用安装基础项
        if command -v pacman &>/dev/null; then
            sudo pacman -Sy --noconfirm cups smbclient python-pmw
        fi
    fi
    
    # 强力唤醒并锁定后端核心服务
    log_status="激活后端服务..."
    sudo systemctl enable cups &>/dev/null || true
    sudo systemctl start cups &>/dev/null || true
    sudo systemctl enable avahi-daemon &>/dev/null || true
    sudo systemctl start avahi-daemon &>/dev/null || true
    
    touch "$INSTALL_FLAG"
    print_success "所有底层插件、共享协议库与网络广播环境配置成功！"
    echo ""
}

do_launch_gui() {
    chmod +x "$BASH_SCRIPT" 2>/dev/null
    chmod +x "$GUI_SCRIPT" 2>/dev/null
    if [ ! -f "$GUI_SCRIPT" ]; then
        print_error "找不到图形主程序，请检查路径: $GUI_SCRIPT"
        exit 1
    fi
    print_info "正在为您唤醒智能打印机助手图形面板..."
    python3 "$GUI_SCRIPT" &
}

show_menu() {
    while true; do
        echo ""
        print_header "--------------------------------------"
        print_header "   打印机助手插件控制台"
        print_header "--------------------------------------"
        echo -e "  ${GREEN}[1]${NC} 打开智能打印机管理器窗口"
        echo -e "  ${GREEN}[2]${NC} 强力强制重检/修复全套网络共享与驱动环境"
        echo -e "  ${GREEN}[3]${NC} 强力重启系统 CUPS 打印服务后端"
        echo -e "  ${RED}[0]${NC} 返回主程序"
        echo ""
        read -p "  请输入选项 [0-3]: " choice

        case "$choice" in
            1)
                do_launch_gui
                ;;
            2)
                do_install_deps
                ;;
            3)
                print_step "正在尝试提权重启系统 CUPS 后端与广播服务..."
                sudo systemctl restart cups && sudo systemctl restart avahi-daemon && print_success "后端基础服务全部重启就绪"
                ;;
            0)
                print_info "退出组件控制台。"
                exit 0
                ;;
            *)
                print_warning "无效选项，请重新输入"
                ;;
        esac
    done
}

###############################################################################
# 入口逻辑
###############################################################################
main() {
    # 只要检测到没装过，或者底层有任何组件被系统偷偷阉割了，首次进来直接强制自动补齐
    if ! is_installed; then
        do_install_deps
    fi
    
    show_menu
}

main "$@"
