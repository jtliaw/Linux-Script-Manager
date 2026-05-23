#!/bin/bash
# printer-manager-launcher.sh
# 描述: 智能打印机助手的外壳启动与环境安装管理器 (组件套壳完全体)
# 支持: Debian/Ubuntu 系 · Red Hat/Fedora 系 · Arch 系 · openSUSE 系

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

INSTALL_FLAG="$HOME/.config/linux-script-manager/printer_installed.flag"
mkdir -p "$HOME/.config/linux-script-manager"

is_installed() {
    [ -f "$INSTALL_FLAG" ]
}

###############################################################################
# ❶ 发行版自动识别
# 识别结果写入全局变量：
#   DISTRO_FAMILY  → debian | redhat | arch | suse | unknown
#   DISTRO_NAME    → 人类可读名称（用于日志显示）
#   PKG_MANAGER    → 包管理器命令
#   PKG_UPDATE     → 更新索引的完整命令
#   PKG_INSTALL    → 安装命令前缀（后接包名列表）
#   PKG_QUERY_CMD  → 查询单包是否已安装的函数名（各系不同）
###############################################################################

DISTRO_FAMILY="unknown"
DISTRO_NAME="Unknown Linux"

detect_distro() {
    # 优先读 /etc/os-release（现代发行版通用）
    if [ -f /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        DISTRO_NAME="${PRETTY_NAME:-${NAME:-Unknown}}"
        ID_LOWER="${ID,,}"          # 转小写
        ID_LIKE_LOWER="${ID_LIKE,,}"

        # ── Debian 系判断 ────────────────────────────────────────────────────
        if [[ "$ID_LOWER" =~ ^(debian|ubuntu|linuxmint|pop|elementary|zorin|kali|parrot|mx|lmde|raspbian|lubuntu|xubuntu|kubuntu)$ ]] \
        || [[ "$ID_LIKE_LOWER" == *"debian"* ]] \
        || [[ "$ID_LIKE_LOWER" == *"ubuntu"* ]]; then
            DISTRO_FAMILY="debian"

        # ── Red Hat 系判断 ───────────────────────────────────────────────────
        elif [[ "$ID_LOWER" =~ ^(rhel|centos|fedora|rocky|almalinux|ol|scientific|amzn)$ ]] \
          || [[ "$ID_LIKE_LOWER" == *"rhel"* ]] \
          || [[ "$ID_LIKE_LOWER" == *"fedora"* ]]; then
            DISTRO_FAMILY="redhat"

        # ── Arch 系判断 ──────────────────────────────────────────────────────
        elif [[ "$ID_LOWER" =~ ^(arch|manjaro|endeavouros|garuda|artix|cachyos)$ ]] \
          || [[ "$ID_LIKE_LOWER" == *"arch"* ]]; then
            DISTRO_FAMILY="arch"

        # ── SUSE 系判断 ──────────────────────────────────────────────────────
        elif [[ "$ID_LOWER" =~ ^(opensuse.*|sles|sled)$ ]] \
          || [[ "$ID_LIKE_LOWER" == *"suse"* ]]; then
            DISTRO_FAMILY="suse"
        fi

    # 兜底：读旧式 /etc/issue
    elif [ -f /etc/issue ]; then
        local issue
        issue=$(cat /etc/issue | tr '[:upper:]' '[:lower:]')
        if   [[ "$issue" == *"ubuntu"*  ]] || [[ "$issue" == *"debian"* ]]; then DISTRO_FAMILY="debian"
        elif [[ "$issue" == *"fedora"*  ]] || [[ "$issue" == *"centos"* ]] || [[ "$issue" == *"red hat"* ]]; then DISTRO_FAMILY="redhat"
        elif [[ "$issue" == *"arch"*    ]]; then DISTRO_FAMILY="arch"
        elif [[ "$issue" == *"opensuse"* ]]; then DISTRO_FAMILY="suse"
        fi
    fi

    # ── 根据发行版族设置包管理器变量 ────────────────────────────────────────
    case "$DISTRO_FAMILY" in
        debian)
            PKG_MANAGER="apt"
            PKG_UPDATE="sudo apt update"
            PKG_INSTALL="sudo apt install -y"
            ;;
        redhat)
            # Fedora 22+ / RHEL 8+ 用 dnf；老版本用 yum 兜底
            if command -v dnf &>/dev/null; then
                PKG_MANAGER="dnf"
                PKG_UPDATE="sudo dnf check-update || true"
                PKG_INSTALL="sudo dnf install -y"
            else
                PKG_MANAGER="yum"
                PKG_UPDATE="sudo yum check-update || true"
                PKG_INSTALL="sudo yum install -y"
            fi
            ;;
        arch)
            PKG_MANAGER="pacman"
            PKG_UPDATE="sudo pacman -Sy"
            PKG_INSTALL="sudo pacman -S --noconfirm --needed"
            ;;
        suse)
            PKG_MANAGER="zypper"
            PKG_UPDATE="sudo zypper refresh"
            PKG_INSTALL="sudo zypper install -y"
            ;;
        *)
            PKG_MANAGER="unknown"
            PKG_UPDATE=""
            PKG_INSTALL=""
            ;;
    esac
}

###############################################################################
# ❷ 跨发行版包检测函数
# 每个发行版族使用对应的查询工具，不互相依赖
###############################################################################

_pkg_installed() {
    local pkg="$1"
    case "$DISTRO_FAMILY" in
        debian)
            dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "^install ok installed"
            ;;
        redhat)
            rpm -q "$pkg" &>/dev/null
            ;;
        arch)
            pacman -Q "$pkg" &>/dev/null
            ;;
        suse)
            rpm -q "$pkg" &>/dev/null
            ;;
        *)
            # 未知发行版：用 command 命令名探测（粗略兜底）
            command -v "$pkg" &>/dev/null
            ;;
    esac
}

###############################################################################
# ❸ 跨发行版包名映射表
# 格式：每行 "通用键  debian包名  redhat包名  arch包名  suse包名"
# 通用键用于逻辑分组，实际安装时取对应列的包名
# 若某发行版无对应包则填 "-"（安装阶段会自动跳过）
###############################################################################

# 每项格式：  "逻辑键|debian名|redhat名|arch名|suse名"
PKG_MAP=(
    # ── CUPS 核心 ────────────────────────────────────────────────────────────
    "cups|cups|cups|cups|cups"
    "cups-client|cups-client|cups-client|cups|cups-client"
    "cups-filters|cups-filters|cups-filters|cups-filters|cups-filters"
    "cups-browsed|cups-browsed|cups-browsed|cups-browsed|cups-browsed"

    # ── 通用驱动库 ───────────────────────────────────────────────────────────
    "gutenprint|printer-driver-gutenprint|gutenprint|gutenprint|gutenprint"
    "printer-driver-all|printer-driver-all|-|-|-"
    "hplip|hplip|hplip|hplip|hplip"
    "foomatic|foomatic-db-engine|foomatic|foomatic-db|foomatic-filters"

    # ── Windows 共享打印（SMB / Samba）───────────────────────────────────────
    "samba|samba|samba|samba|samba"
    "smbclient|smbclient|samba-client|smbclient|samba-client"
    "libsmbclient|libsmbclient|libsmbclient|smbclient|libsmbclient0"
    "python3-smbc|python3-smbc|-|python-smbc|python3-smbc"

    # ── Linux 网络发现（Avahi / mDNS）────────────────────────────────────────
    "avahi-daemon|avahi-daemon|avahi|avahi|avahi"
    "avahi-utils|avahi-utils|avahi-tools|avahi|avahi-utils"
    "libnss-mdns|libnss-mdns|nss-mdns|nss-mdns|nss-mdns"

    # ── GUI 依赖 ─────────────────────────────────────────────────────────────
    "python3-tk|python3-tk|python3-tkinter|tk|python3-tk"
)

# 根据当前发行版族从映射表取出实际包名，写入数组
# 用法：resolve_pkg_name "逻辑键"  → 输出实际包名，"-" 表示跳过
resolve_pkg_name() {
    local key="$1"
    for entry in "${PKG_MAP[@]}"; do
        IFS='|' read -r k deb rh arch suse <<< "$entry"
        if [ "$k" == "$key" ]; then
            case "$DISTRO_FAMILY" in
                debian) echo "$deb"  ;;
                redhat) echo "$rh"   ;;
                arch)   echo "$arch" ;;
                suse)   echo "$suse" ;;
                *)      echo "-"     ;;
            esac
            return
        fi
    done
    echo "-"
}

###############################################################################
# ❹ 分组检测 + 缺失包收集
###############################################################################

MISSING_PKGS=()

# 用法：check_pkg_group "分组标题" 逻辑键1 逻辑键2 ...
check_pkg_group() {
    local group_label="$1"
    shift
    local keys=("$@")
    local missing_in_group=()
    local all_ok=true

    print_step "检测分组：${group_label}"

    for key in "${keys[@]}"; do
        local real_pkg
        real_pkg=$(resolve_pkg_name "$key")

        # 该发行版无对应包，直接跳过
        if [ "$real_pkg" == "-" ]; then
            echo -e "    ${CYAN}[–]${NC} ${key}  （当前发行版无对应包，跳过）"
            continue
        fi

        if _pkg_installed "$real_pkg"; then
            echo -e "    ${GREEN}[✓]${NC} ${real_pkg}"
        else
            echo -e "    ${RED}[✗]${NC} ${real_pkg}  ← 缺失，将自动补装"
            missing_in_group+=("$real_pkg")
            all_ok=false
        fi
    done

    if $all_ok; then
        echo -e "    ${GREEN}→ 本组全部就绪，跳过安装${NC}"
    fi

    MISSING_PKGS+=("${missing_in_group[@]}")
}

# 执行完整检测
run_pkg_detection() {
    echo ""
    print_header "============================================="
    print_header "   正在扫描打印机驱动环境完整性...           "
    print_header "============================================="
    echo ""

    MISSING_PKGS=()

    # ── 1. CUPS 核心打印后端 ──────────────────────────────────────────────────
    check_pkg_group "CUPS 核心打印后端" \
        cups cups-client cups-filters cups-browsed

    # ── 2. 通用开源驱动库 ────────────────────────────────────────────────────
    check_pkg_group "通用开源驱动库（Gutenprint / Foomatic / HP）" \
        gutenprint printer-driver-all hplip foomatic

    # ── 3. Windows 网络共享打印（Samba / SMB）────────────────────────────────
    check_pkg_group "Windows 共享打印支持（Samba / SMB）" \
        samba smbclient libsmbclient python3-smbc

    # ── 4. Linux 局域网打印自动发现（Avahi / mDNS）───────────────────────────
    check_pkg_group "Linux 网络打印自动发现（Avahi / mDNS）" \
        avahi-daemon avahi-utils libnss-mdns

    # ── 5. GUI 界面依赖 ──────────────────────────────────────────────────────
    check_pkg_group "Python GUI 界面依赖" \
        python3-tk

    echo ""
}

###############################################################################
# ❺ 主安装流程
###############################################################################

do_install_deps() {
    echo ""
    print_header "============================================="
    print_header "   正在初始化 Linux 智能打印万能驱动环境...   "
    print_header "============================================="

    # 检测发行版（确保变量已就绪）
    detect_distro

    echo ""
    print_info  "检测到当前系统：${DISTRO_NAME}"
    print_info  "发行版族：${DISTRO_FAMILY}  |  包管理器：${PKG_MANAGER}"
    echo ""

    # 未知发行版，无法自动安装，给出提示后退出
    if [ "$DISTRO_FAMILY" == "unknown" ] || [ "$PKG_MANAGER" == "unknown" ]; then
        print_error "无法识别当前发行版，自动安装不可用。"
        print_warning "请手动参考以下包清单，使用系统包管理器安装："
        for entry in "${PKG_MAP[@]}"; do
            IFS='|' read -r k deb rh arch suse <<< "$entry"
            echo -e "    ${YELLOW}·${NC} ${k}"
        done
        return 1
    fi

    print_step "此操作将为您装配全套开源驱动库（Gutenprint, HP, IPP everywhere...）"
    print_warning "由于需要向系统部署驱动组件，接下来请配合输入您的系统用户密码："

    # ── 智能检测阶段 ─────────────────────────────────────────────────────────
    run_pkg_detection

    # ── 仅安装缺失的包 ───────────────────────────────────────────────────────
    if [ ${#MISSING_PKGS[@]} -eq 0 ]; then
        print_success "检测完毕：所有打印机驱动组件均已就绪，无需重复安装！"
    else
        echo ""
        print_warning "检测到以下 ${#MISSING_PKGS[@]} 个组件缺失，即将自动补装："
        for pkg in "${MISSING_PKGS[@]}"; do
            echo -e "    ${YELLOW}·${NC} $pkg"
        done
        echo ""

        # 更新包索引
        print_step "正在更新包索引..."
        eval "$PKG_UPDATE"

        # 安装缺失包
        $PKG_INSTALL "${MISSING_PKGS[@]}"

        echo ""
        print_success "缺失组件补装完毕！"
    fi

    # ── 唤醒并锁定后端 CUPS 守护进程 ────────────────────────────────────────
    print_step "正在确保 CUPS 守护进程开机自启并运行中..."
    sudo systemctl enable cups 2>/dev/null || true
    sudo systemctl start  cups 2>/dev/null || true

    # ── 写入安装标记 ─────────────────────────────────────────────────────────
    # 同时记录检测时的发行版，便于将来排查
    echo "distro_family=${DISTRO_FAMILY}" >  "$INSTALL_FLAG"
    echo "distro_name=${DISTRO_NAME}"     >> "$INSTALL_FLAG"
    echo "installed_at=$(date '+%Y-%m-%d %H:%M:%S')" >> "$INSTALL_FLAG"

    print_success "万能打印驱动库与底层环境配置成功！"
    echo ""
}

###############################################################################
# ❻ GUI 启动 / 菜单
###############################################################################

do_launch_gui() {
    chmod +x "$BASH_SCRIPT" 2>/dev/null || true
    chmod +x "$GUI_SCRIPT"  2>/dev/null || true
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
                # 手动重检：清除标记，强制走完整检测流程
                rm -f "$INSTALL_FLAG"
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
    # 首次运行：识别发行版 → 智能检测 → 仅补装缺失 → 写标记
    # 已安装过：直接跳过检测，进入菜单
    if ! is_installed; then
        detect_distro
        do_install_deps
    else
        detect_distro   # 菜单里"重新检测"也需要这些变量
        print_success "驱动环境已就绪（跳过检测），直接进入控制台..."
        print_info    "当前系统：${DISTRO_NAME}（${DISTRO_FAMILY} 系 / ${PKG_MANAGER}）"
    fi

    show_menu
}

main "$@"
