#!/bin/bash
# Screen Brightness Launcher
# DESCRIPTION: 屏幕亮度控制工具 - 安装、启动与卸载管理器
# REQUIRES_SUDO: false

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
NC='\033[0m'

print_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
print_step()    { echo -e "${CYAN}➜${NC} $1"; }
print_header()  { echo -e "${WHITE}$1${NC}"; }

###############################################################################
# 路径定义
###############################################################################

# 启动器自身所在目录（scripts/）
LAUNCHER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 核心文件所在目录（scripts/screen-brightness/）
TOOL_DIR="$(cd "$LAUNCHER_DIR/screen-brightness" 2>/dev/null && pwd || echo "")"

# 如果 screen-brightness 目录不存在，尝试同层目录
if [ -z "$TOOL_DIR" ] || [ ! -d "$TOOL_DIR" ]; then
    TOOL_DIR="$LAUNCHER_DIR/../screen-brightness"
fi

CORE_SCRIPT="$TOOL_DIR/screen-brightness.sh"
TRAY_SCRIPT="$TOOL_DIR/screen-brightness-tray.py"

# 用户设定目录（记录是否已安装）
CONFIG_DIR="$HOME/.config/screen-brightness"
INSTALL_FLAG="$CONFIG_DIR/.installed"

# 开机自动启动档案
AUTOSTART_FILE="$HOME/.config/autostart/screen-brightness.desktop"

###############################################################################
# 工具函数
###############################################################################

is_installed() {
    [ -f "$INSTALL_FLAG" ] && \
    [ -f "$CORE_SCRIPT" ] && \
    [ -f "$TRAY_SCRIPT" ]
}

is_tray_running() {
    pgrep -f "screen-brightness-tray.py" >/dev/null 2>&1
}

check_tool_files() {
    if [ ! -f "$CORE_SCRIPT" ] || [ ! -f "$TRAY_SCRIPT" ]; then
        echo ""
        print_error "找不到核心文件！"
        print_error "请确认以下文件存在："
        echo -e "  ${CYAN}$CORE_SCRIPT${NC}"
        echo -e "  ${CYAN}$TRAY_SCRIPT${NC}"
        echo ""
        print_info "目录结构应该是："
        echo -e "  ${WHITE}你的软件目录/${NC}"
        echo -e "  ├── scripts/"
        echo -e "  │   └── screen-brightness-launcher.sh"
        echo -e "  └── screen-brightness/"
        echo -e "      ├── screen-brightness.sh"
        echo -e "      └── screen-brightness-tray.py"
        echo ""
        read -p "按 Enter 退出..." _
        exit 1
    fi
}

###############################################################################
# 安装流程
###############################################################################

do_install() {
    echo ""
    print_header "======================================"
    print_header "   屏幕亮度控制工具 - 首次安装"
    print_header "======================================"
    echo ""
    print_info "这是首次启动，需要先完成安装设定"
    print_info "整个过程约需 1~2 分钟"
    echo ""

    check_tool_files

    # 设定执行权限
    print_step "设定执行权限..."
    chmod +x "$CORE_SCRIPT"
    chmod +x "$TRAY_SCRIPT"
    print_success "权限设定完成"

    # 检查 Python3 + tkinter
    print_step "检查 Python3 环境..."
    if ! command -v python3 >/dev/null 2>&1; then
        print_error "未找到 Python3，请先安装："
        echo -e "  ${CYAN}sudo apt install python3${NC}"
        read -p "按 Enter 退出..." _
        exit 1
    fi
    python3 -c "import tkinter" 2>/dev/null || {
        print_warning "未找到 python3-tk，正在安装..."
        sudo apt install -y python3-tk
    }
    print_success "Python3 环境就绪"
    echo ""

    # 安装建议工具
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_header "   推荐工具安装（影响亮度控制效果）"
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    print_step "安装必要工具（brightnessctl、ddcutil）..."
    local pkgs_to_install=()
    command -v brightnessctl >/dev/null 2>&1 && print_success "brightnessctl 已安装 ✓" || pkgs_to_install+=("brightnessctl")
    command -v ddcutil       >/dev/null 2>&1 && print_success "ddcutil 已安装 ✓"       || pkgs_to_install+=("ddcutil")

    if [ ${#pkgs_to_install[@]} -gt 0 ]; then
        print_step "正在安装: ${pkgs_to_install[*]}"
        sudo apt install -y "${pkgs_to_install[@]}" 2>/dev/null &&             print_success "工具安装完成" ||             print_warning "部分工具安装失败，将以有限功能运行"
    fi

    # 执行硬件检测
    echo ""
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_header "   硬件检测"
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    bash "$CORE_SCRIPT" detect

    # 写入安装标记
    mkdir -p "$CONFIG_DIR"
    echo "installed=$(date)" > "$INSTALL_FLAG"
    echo "tool_dir=$TOOL_DIR"   >> "$INSTALL_FLAG"

    echo ""
    print_success "安装完成！正在启动托盘图标..."
    sleep 1

    do_launch
}

###############################################################################
# 启动托盘（正确传递 X11 环境变量）
###############################################################################

start_tray() {
    local display="${DISPLAY:-:0}"

    local dbus_addr="${DBUS_SESSION_BUS_ADDRESS:-}"
    if [ -z "$dbus_addr" ]; then
        dbus_addr=$(grep -z DBUS_SESSION_BUS_ADDRESS \
                    /proc/$(pgrep -u "$USER" dbus-daemon | head -1)/environ \
                    2>/dev/null | tr '\0' '\n' | grep DBUS | cut -d= -f2- || true)
    fi

    # 用 setsid 建立新会话，完全脱离父进程
    # 即使启动脚本或终端关闭，托盘进程仍然存活
    setsid env \
        DISPLAY="$display" \
        DBUS_SESSION_BUS_ADDRESS="$dbus_addr" \
        XAUTHORITY="${XAUTHORITY:-$HOME/.Xauthority}" \
        python3 "$TRAY_SCRIPT" \
        > /tmp/screen-brightness-tray.log 2>&1 &

    disown $! 2>/dev/null || true
}

###############################################################################
# 启动托盘
###############################################################################

do_launch() {
    check_tool_files

    if is_tray_running; then
        echo ""
        print_warning "屏幕亮度控制托盘已在运行中"
        echo ""
        print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        print_header "   请选择操作"
        print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo -e "  ${GREEN}[1]${NC} 重新启动托盘（关掉旧的，开新的）"
        echo -e "  ${BLUE}[2]${NC} 套用已储存的亮度设定"
        echo -e "  ${RED}[0]${NC} 取消"
        echo ""
        read -p "  请输入选项 [0-2]: " choice
        case "$choice" in
            1)
                pkill -f "screen-brightness-tray.py" 2>/dev/null || true
                sleep 1
                start_tray
                print_success "托盘已重新启动"
                ;;
            2)
                bash "$CORE_SCRIPT" load
                print_success "已套用储存的亮度设定"
                ;;
            *)
                print_info "已取消"
                ;;
        esac
    else
        # 套用上次储存的设定
        bash "$CORE_SCRIPT" load 2>/dev/null || true

        # 启动托盘图标（背景运行）
        start_tray
        echo ""
        print_success "屏幕亮度控制托盘已启动！"
        print_info "在屏幕角落找到 ☀ 图标，点击即可调整亮度"
    fi

    echo ""
    sleep 2
}

###############################################################################
# 开机自动启动管理
###############################################################################

manage_autostart() {
    echo ""
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_header "   开机自动启动管理"
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    if [ -f "$AUTOSTART_FILE" ]; then
        echo -e "  目前状态 : ${GREEN}已启用${NC}"
        echo ""
        echo -e "  ${RED}[1]${NC} 关闭开机自动启动"
        echo -e "  ${RED}[0]${NC} 返回"
        echo ""
        read -p "  请输入选项 [0-1]: " choice
        case "$choice" in
            1)
                bash "$CORE_SCRIPT" autostart remove
                print_success "已关闭开机自动启动"
                ;;
            *) print_info "已返回" ;;
        esac
    else
        echo -e "  目前状态 : ${RED}未启用${NC}"
        echo ""
        echo -e "  ${GREEN}[1]${NC} 启用开机自动启动"
        echo -e "  ${RED}[0]${NC} 返回"
        echo ""
        read -p "  请输入选项 [0-1]: " choice
        case "$choice" in
            1)
                bash "$CORE_SCRIPT" autostart install
                print_success "已启用开机自动启动"
                ;;
            *) print_info "已返回" ;;
        esac
    fi
}

###############################################################################
# 卸载流程
###############################################################################

do_uninstall() {
    echo ""
    print_header "======================================"
    print_header "   屏幕亮度控制工具 - 卸载"
    print_header "======================================"
    echo ""
    print_warning "此操作将彻底删除屏幕亮度控制工具的所有相关内容："
    echo ""
    echo -e "  ${RED}•${NC} 停止正在运行的托盘图标"
    echo -e "  ${RED}•${NC} 移除开机自动启动设定"
    echo -e "  ${RED}•${NC} 删除所有用户设定与储存的亮度数据"
    echo -e "  ${RED}•${NC} 删除硬件检测缓存"
    echo ""
    echo -e "  ${YELLOW}注意：核心程序文件不会被删除${NC}"
    echo -e "  ${YELLOW}（screen-brightness.sh 和 tray.py 保留）${NC}"
    echo -e "  ${YELLOW}如需彻底删除，手动删除 screen-brightness/ 目录即可${NC}"
    echo ""
    read -p "  确定要卸载吗? [y/N]: " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_info "已取消卸载"
        return
    fi

    echo ""

    # 停止托盘
    print_step "停止托盘图标..."
    if is_tray_running; then
        pkill -f "screen-brightness-tray.py" 2>/dev/null || true
        sleep 1
        print_success "托盘已停止"
    else
        print_info "托盘未在运行，跳过"
    fi

    # 移除开机自动启动
    print_step "移除开机自动启动..."
    if [ -f "$AUTOSTART_FILE" ]; then
        rm -f "$AUTOSTART_FILE"
        print_success "已移除开机自动启动"
    else
        print_info "无开机启动设定，跳过"
    fi

    # 还原屏幕亮度（避免卸载后亮度卡住）
    print_step "还原屏幕亮度为 100%..."
    if [ -f "$CORE_SCRIPT" ]; then
        bash "$CORE_SCRIPT" load 2>/dev/null || true
        # 尝试对所有 xrandr 输出还原
        if command -v xrandr >/dev/null 2>&1; then
            xrandr --listmonitors 2>/dev/null | awk 'NR>1{print $NF}' | while read -r output; do
                xrandr --output "$output" --brightness 1.0 --gamma 1:1:1 2>/dev/null || true
            done
        fi
    fi
    print_success "屏幕亮度已还原"

    # 删除用户设定目录
    print_step "删除用户设定与检测缓存..."
    if [ -d "$CONFIG_DIR" ]; then
        rm -rf "$CONFIG_DIR"
        print_success "已删除: $CONFIG_DIR"
    else
        print_info "设定目录不存在，跳过"
    fi

    echo ""
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_success "卸载完成！"
    echo ""
    print_info "如需彻底删除程序文件，请手动执行："
    echo -e "  ${CYAN}rm -rf $TOOL_DIR${NC}"
    echo ""
}

###############################################################################
# 主选单
###############################################################################

show_main_menu() {
    echo ""
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_header "   请选择操作"
    print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    local tray_status
    if is_tray_running; then
        tray_status="${GREEN}运行中 ●${NC}"
    else
        tray_status="${RED}未运行 ○${NC}"
    fi

    echo -e "  托盘状态 : $(echo -e $tray_status)"
    echo ""
    # 开机启动目前状态
    local autostart_status
    if [ -f "$AUTOSTART_FILE" ]; then
        autostart_status="${GREEN}已启用 ●${NC}"
    else
        autostart_status="${RED}未启用 ○${NC}"
    fi
    echo -e "  开机启动 : $(echo -e $autostart_status)"
    echo ""
    echo -e "  ${GREEN}[1]${NC} 启动亮度控制托盘"
    echo -e "  ${BLUE}[2]${NC} 重新检测显示器硬件"
    echo -e "  ${CYAN}[3]${NC} 套用储存的亮度设定"
    echo -e "  ${MAGENTA}[4]${NC} 开机自动启动管理"
    echo -e "  ${YELLOW}[5]${NC} 重新安装（修复问题用）"
    echo -e "  ${RED}[6]${NC} 卸载并删除所有设定"
    echo -e "  ${RED}[0]${NC} 退出"
    echo ""
    read -p "  请输入选项 [0-6]: " choice

    case "$choice" in
        1) do_launch ;;
        2)
            echo ""
            print_step "重新检测显示器..."
            bash "$CORE_SCRIPT" detect
            ;;
        3)
            echo ""
            bash "$CORE_SCRIPT" load
            print_success "已套用储存的亮度设定"
            ;;
        4)
            manage_autostart
            ;;
        5)
            rm -f "$INSTALL_FLAG"
            do_install
            ;;
        6) do_uninstall ;;
        0)
            print_info "已退出"
            exit 0
            ;;
        *)
            print_warning "无效选项"
            ;;
    esac
}

###############################################################################
# 主程序
###############################################################################

main() {
    echo ""
    print_header "======================================"
    print_header "   屏幕亮度控制工具"
    print_header "======================================"

    # 第一次运行：自动进入安装流程
    if ! is_installed; then
        do_install
        exit 0
    fi

    # 已安装：显示主选单
    while true; do
        show_main_menu
        echo ""
        read -p "  是否继续操作? [y/N]: " again
        [[ "$again" =~ ^[Yy]$ ]] || break
    done

    print_info "再见！"
    sleep 1
}

main "$@"
