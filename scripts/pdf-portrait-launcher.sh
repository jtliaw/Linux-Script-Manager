#!/bin/bash
# pdf-portrait-launcher.sh
# DESCRIPTION: PDF 双向转换工具启动器
# 首次运行：自动检测并安装依赖
# 之后每次：直接启动 GUI

set +e

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
# 路径定义
###############################################################################

LAUNCHER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL_DIR="$LAUNCHER_DIR/pdf-portrait"
if [ ! -d "$TOOL_DIR" ]; then
    TOOL_DIR="$LAUNCHER_DIR"
fi

GUI_SCRIPT="$TOOL_DIR/pdf-portrait-gui.py"
HELPER_SCRIPT="$TOOL_DIR/pdf-portrait-helper.sh"

INSTALL_FLAG="$HOME/.config/linux-script-manager/pdf_portrait_installed.flag"
mkdir -p "$HOME/.config/linux-script-manager"

###############################################################################
# 发行版识别
###############################################################################

DISTRO_FAMILY="unknown"
DISTRO_NAME="Unknown Linux"
PKG_MANAGER="unknown"
PKG_UPDATE=""
PKG_INSTALL=""

detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO_NAME="${PRETTY_NAME:-${NAME:-Unknown}}"
        ID_LOWER="${ID,,}"
        ID_LIKE_LOWER="${ID_LIKE,,}"

        if [[ "$ID_LOWER" =~ ^(debian|ubuntu|linuxmint|pop|elementary|zorin|kali|parrot|mx|lmde|raspbian|lubuntu|xubuntu|kubuntu)$ ]] \
        || [[ "$ID_LIKE_LOWER" == *"debian"* ]] \
        || [[ "$ID_LIKE_LOWER" == *"ubuntu"* ]]; then
            DISTRO_FAMILY="debian"
        elif [[ "$ID_LOWER" =~ ^(rhel|centos|fedora|rocky|almalinux|ol|scientific|amzn)$ ]] \
          || [[ "$ID_LIKE_LOWER" == *"rhel"* ]] \
          || [[ "$ID_LIKE_LOWER" == *"fedora"* ]]; then
            DISTRO_FAMILY="redhat"
        elif [[ "$ID_LOWER" =~ ^(arch|manjaro|endeavouros|garuda|artix|cachyos)$ ]] \
          || [[ "$ID_LIKE_LOWER" == *"arch"* ]]; then
            DISTRO_FAMILY="arch"
        elif [[ "$ID_LOWER" =~ ^(opensuse.*|sles|sled)$ ]] \
          || [[ "$ID_LIKE_LOWER" == *"suse"* ]]; then
            DISTRO_FAMILY="suse"
        fi
    fi

    case "$DISTRO_FAMILY" in
        debian) PKG_UPDATE="sudo apt update";           PKG_INSTALL="sudo apt install -y" ;;
        redhat) command -v dnf &>/dev/null \
                && PKG_UPDATE="sudo dnf check-update || true"  && PKG_INSTALL="sudo dnf install -y" \
                || PKG_UPDATE="sudo yum check-update || true"  && PKG_INSTALL="sudo yum install -y" ;;
        arch)   PKG_UPDATE="sudo pacman -Sy";           PKG_INSTALL="sudo pacman -S --noconfirm --needed" ;;
        suse)   PKG_UPDATE="sudo zypper refresh";       PKG_INSTALL="sudo zypper install -y" ;;
    esac
}

###############################################################################
# 依赖检测与安装（仅首次）
###############################################################################

_pkg_installed() {
    local pkg="$1"
    case "$DISTRO_FAMILY" in
        debian) dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "^install ok installed" ;;
        redhat|suse) rpm -q "$pkg" &>/dev/null ;;
        arch)   pacman -Q "$pkg" &>/dev/null ;;
        *)      command -v "$pkg" &>/dev/null ;;
    esac
}

_pypdf_installed() {
    python3 -c "import pypdf" 2>/dev/null
}

_resolve_pkg() {
    # key → 实际包名（debian|redhat|arch|suse）
    case "$1" in
        python3)     echo "python3" ;;
        python3-pip) case "$DISTRO_FAMILY" in arch) echo "python-pip" ;; *) echo "python3-pip" ;; esac ;;
        python3-tk)  case "$DISTRO_FAMILY" in redhat) echo "python3-tkinter" ;; arch) echo "tk" ;; *) echo "python3-tk" ;; esac ;;
    esac
}

do_install_deps() {
    echo ""
    print_header "============================================="
    print_header "   首次启动：检测并安装所需依赖              "
    print_header "============================================="
    echo ""
    print_info "系统：${DISTRO_NAME}（${DISTRO_FAMILY} / ${PKG_MANAGER}）"
    echo ""

    if [ "$DISTRO_FAMILY" == "unknown" ]; then
        print_error "无法识别发行版，请手动安装：python3 python3-pip python3-tk"
        print_error "并执行：pip3 install pypdf --break-system-packages"
        read -p "  按 Enter 继续尝试启动..." _
        return
    fi

    local missing=()
    for key in python3 python3-pip python3-tk; do
        local pkg; pkg=$(_resolve_pkg "$key")
        if ! _pkg_installed "$pkg"; then
            missing+=("$pkg")
            echo -e "    ${RED}[✗]${NC} $pkg"
        else
            echo -e "    ${GREEN}[✓]${NC} $pkg"
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        echo ""
        print_step "正在安装缺失组件：${missing[*]}"
        sh -c "$PKG_UPDATE"
        $PKG_INSTALL "${missing[@]}"
    else
        print_success "系统依赖全部就绪！"
    fi

    if ! _pypdf_installed; then
        print_step "正在安装 pypdf..."
        pip3 install pypdf --break-system-packages 2>/dev/null \
            || pip3 install pypdf 2>/dev/null \
            || { print_error "pypdf 安装失败，请手动执行: pip3 install pypdf --break-system-packages"; read -p "按 Enter 继续..." _; return; }
        print_success "pypdf 安装完毕！"
    else
        echo -e "    ${GREEN}[✓]${NC} pypdf"
    fi

    # 写入安装完成标记
    echo "distro_family=${DISTRO_FAMILY}"  >  "$INSTALL_FLAG"
    echo "distro_name=${DISTRO_NAME}"      >> "$INSTALL_FLAG"
    echo "installed_at=$(date '+%Y-%m-%d %H:%M:%S')" >> "$INSTALL_FLAG"

    echo ""
    print_success "环境初始化完成！正在启动..."
    sleep 1
}

###############################################################################
# 启动 GUI
###############################################################################

launch_gui() {
    chmod +x "$HELPER_SCRIPT" 2>/dev/null || true
    if [ ! -f "$GUI_SCRIPT" ]; then
        print_error "找不到图形程序：$GUI_SCRIPT"
        exit 1
    fi
    python3 "$GUI_SCRIPT"
}

###############################################################################
# 入口
###############################################################################

detect_distro

if [ ! -f "$INSTALL_FLAG" ]; then
    do_install_deps
fi

launch_gui
