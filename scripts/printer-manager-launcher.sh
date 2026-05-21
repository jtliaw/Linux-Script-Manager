#!/bin/bash
# printer-manager-launcher.sh
# 描述: 智能打印机助手的外壳启动与环境安装管理器 (组件套壳完全体)

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
# 已修复：彻底移除末尾导致 EOF 报错的错误转义符号
print_header()  { echo -e "${WHITE}$1${NC}"; }

###############################################################################
# 路径定义（动态适配 Linux-Script-Manager 架构）
###############################################################################

# 启动器自身所在目录（即 scripts/）
LAUNCHER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 打印机组件实际存放的子目录（即 scripts/printer/）
# 建议将 GUI 和 Helper 脚本放在这个专门的子文件夹内
TOOL_DIR="$LAUNCHER_DIR/printer"

# 兼容性兜底：如果用户直接把文件全丢在 scripts 目录下，则自动对齐 LAUNCHER_DIR
if [ ! -d "$TOOL_DIR" ]; then
    TOOL_DIR="$LAUNCHER_DIR"
fi

GUI_SCRIPT="$TOOL_DIR/printer-manager-gui.py"
BASH_SCRIPT="$TOOL_DIR/printer-helper.sh"

# 独立的标记文件，防止软件升级、改名时清除安装记录
INSTALL_FLAG="$HOME/.config/linux-script-manager/printer_installed.flag"

mkdir -p "$HOME/.config/linux-script-manager"

is_installed() {
    if [ -f "$INSTALL_FLAG" ]; then
        return 0
    else
        return 1
    fi
}

# 首次运行或手动重装时，静默装配全套万能驱动环境
do_install_deps() {
    echo ""
    print_header "============================================="
    print_header "   正在初始化 Linux 智能打印万能驱动环境...   "
    print_header "============================================="
    print_step "此操作将为您装配全套开源驱动库（Gutenprint, HP, IPP everywhere...）"
    print_warning "由于需要向系统部署驱动组件，接下来请配合输入您的系统用户密码："
    
    # 执行静默环境构建
    sudo apt update
    sudo apt install -y cups cups-client printer-driver-gutenprint printer-driver-all hplip foomatic-db-engine smbclient python3-tk
    
    # 唤醒并锁定后端 CUPS 守护进程
    sudo systemctl enable cups
    sudo systemctl start cups
    
    touch "$INSTALL_FLAG"
    print_success "万能打印驱动库与底层环境配置成功！"
    echo ""
}

do_launch_gui() {
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
        echo -e "  ${GREEN}[2]${NC} 重新强制检测/修复全套核心驱动环境"
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
                print_step "正在尝试提权重启系统 CUPS 后端..."
                sudo systemctl restart cups && print_success "后端服务重启就绪"
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
    # 严格契合核心要求：如果没安装过，首次进来直接默认强制安装所有驱动
    if ! is_installed; then
        do_install_deps
    fi
    
    # 环境准备完毕，进入控制台菜单
    show_menu
}

main "$@"
