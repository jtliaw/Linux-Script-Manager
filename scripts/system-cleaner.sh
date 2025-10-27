#!/bin/bash
# Linux System Cleaner
# DESCRIPTION: 通用的Linux系统清理工具，支持多个发行版
# SUPPORTS: Debian/Ubuntu, Fedora/RHEL/CentOS, Arch, openSUSE
# REQUIRES_SUDO: true

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# 统计变量
TOTAL_SIZE_BEFORE=0
TOTAL_SIZE_AFTER=0
CLEANED_ITEMS=0

# 颜色函数
print_error() { echo -e "${RED}✗ $1${NC}"; }
print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }
print_info() { echo -e "${BLUE}ℹ $1${NC}"; }
print_question() { echo -e "${PURPLE}? $1${NC}"; }
print_step() { echo -e "${CYAN}➜ $1${NC}"; }
print_header() { echo -e "${WHITE}$1${NC}"; }

# 等待函数
wait_for_exit() {
    local seconds=${1:-5}
    echo ""
    print_info "脚本将在 ${seconds} 秒后自动退出..."
    sleep $seconds
    exit 0
}

# 检查是否以root权限运行
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "请使用 sudo 运行此脚本"
        exit 1
    fi
}

# 检测Linux发行版
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "$ID"
    elif command -v lsb_release &> /dev/null; then
        lsb_release -i | awk '{print $3}' | tr '[:upper:]' '[:lower:]'
    else
        echo "unknown"
    fi
}

# 获取包管理器类型
detect_package_manager() {
    local distro=$(detect_distro)
    
    case "$distro" in
        ubuntu|debian|linuxmint|elementary)
            echo "apt"
            ;;
        fedora|rhel|centos|rocky|almalinux)
            if command -v dnf &> /dev/null; then
                echo "dnf"
            else
                echo "yum"
            fi
            ;;
        arch|manjaro|endeavouros)
            echo "pacman"
            ;;
        opensuse*|sles)
            echo "zypper"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# 计算目录大小
get_dir_size() {
    local dir=$1
    if [ -d "$dir" ]; then
        du -sh "$dir" 2>/dev/null | awk '{print $1}' | sed 's/K/KB/g; s/M/MB/g; s/G/GB/g'
    else
        echo "0B"
    fi
}

# APT系统清理（Debian/Ubuntu）
clean_apt() {
    print_header "=== APT系统清理 ==="
    echo ""
    
    print_step "更新包列表..."
    apt update -qq
    
    # 1. 清理未使用的依赖
    print_step "移除不需要的依赖包..."
    apt autoremove -y
    print_success "已移除不需要的依赖"
    
    # 2. 清理旧包缓存
    print_step "清理旧版本包缓存..."
    apt autoclean -y
    print_success "已清理旧版本包缓存"
    
    # 3. 完全清空APT缓存
    print_step "清空APT缓存..."
    apt clean -y
    print_success "已清空APT缓存"
    
    # 4. 清理内核
    clean_kernel_apt
    
    echo ""
}

# APT内核清理
clean_kernel_apt() {
    print_step "检查内核..."
    
    # 获取当前运行的内核版本
    local current_kernel=$(uname -r)
    print_info "当前运行内核: $current_kernel"
    
    # 只列出【实际安装的】内核包（状态为ii），排除当前正在运行的内核
    local installed_kernels=$(dpkg -l | grep '^ii' | grep 'linux-image-' | awk '{print $2}' | grep -v "$current_kernel")
    
    if [ -z "$installed_kernels" ]; then
        print_info "没有多余内核可以清理"
        return
    fi
    
    local kernel_count=$(echo "$installed_kernels" | wc -l)
    print_warning "发现 $kernel_count 个可移除的旧内核"
    echo ""
    
    print_question "是否删除旧内核? (y/n):"
    read -p "> " confirm
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        echo "$installed_kernels" | while read kernel; do
            if [ -n "$kernel" ]; then
                print_info "移除: $kernel"
                apt remove -y "$kernel" 2>/dev/null || true
                # 移除对应的headers包
                local headers_pkg="${kernel%-image*}-headers${kernel#*-image}"
                apt remove -y "$headers_pkg" 2>/dev/null || true
            fi
        done
        print_success "旧内核已移除"
        
        # 更新GRUB
        print_step "更新GRUB启动引导..."
        update-grub
        print_success "GRUB已更新"
    fi
}

# DNF/YUM系统清理（Fedora/RHEL）
clean_dnf() {
    print_header "=== DNF系统清理 ==="
    echo ""
    
    print_step "清理包缓存..."
    dnf clean all -y
    print_success "已清理包缓存"
    
    print_step "移除不需要的依赖..."
    dnf autoremove -y
    print_success "已移除不需要的依赖"
    
    # 清理内核
    clean_kernel_dnf
    
    echo ""
}

# DNF内核清理
clean_kernel_dnf() {
    print_step "检查内核..."
    
    # 获取当前运行的内核版本
    local current_kernel=$(uname -r)
    print_info "当前运行内核: $current_kernel"
    
    # 列出旧内核
    local old_kernels=$(rpm -q kernel 2>/dev/null | grep -v "$current_kernel" || true)
    
    if [ -z "$old_kernels" ]; then
        print_info "没有多余内核可以清理"
        return
    fi
    
    local kernel_count=$(echo "$old_kernels" | wc -l)
    print_warning "发现 $kernel_count 个可移除的旧内核"
    echo ""
    
    print_question "是否删除旧内核? (y/n):"
    read -p "> " confirm
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        dnf remove -y $old_kernels 2>/dev/null || true
        print_success "旧内核已移除"
        
        # 更新GRUB
        print_step "更新GRUB启动引导..."
        if command -v grub2-mkconfig &> /dev/null; then
            grub2-mkconfig -o /boot/grub2/grub.cfg
        fi
        print_success "GRUB已更新"
    fi
}

# Pacman系统清理（Arch）
clean_pacman() {
    print_header "=== Pacman系统清理 ==="
    echo ""
    
    # 1. 删除未跟踪的包文件
    print_step "清理包缓存..."
    pacman -Sc --noconfirm
    print_success "已清理包缓存"
    
    # 2. 删除所有包缓存
    print_question "是否完全清空包缓存? (y/n):"
    read -p "> " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        pacman -Scc --noconfirm
        print_success "已完全清空包缓存"
    fi
    
    # 3. 删除孤立包
    print_step "检查孤立包..."
    local orphaned=$(pacman -Qdtq 2>/dev/null || true)
    
    if [ -n "$orphaned" ]; then
        local orphan_count=$(echo "$orphaned" | wc -l)
        print_warning "发现 $orphan_count 个孤立包"
        echo ""
        
        print_question "是否删除孤立包? (y/n):"
        read -p "> " confirm
        
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            pacman -R $(pacman -Qdtq) --noconfirm
            print_success "孤立包已删除"
        fi
    else
        print_info "没有孤立包"
    fi
    
    # 4. 清理内核
    clean_kernel_pacman
    
    echo ""
}

# Pacman内核清理
clean_kernel_pacman() {
    print_step "检查内核..."
    
    # 获取当前运行的内核版本
    local current_kernel=$(uname -r)
    print_info "当前运行内核: $current_kernel"
    
    # 列出已安装的内核
    local installed_kernels=$(pacman -Qs linux | grep installed | awk '{print $1}' | grep '^linux' || true)
    
    if [ -z "$installed_kernels" ]; then
        print_info "没有多余内核可以清理"
        return
    fi
    
    # 这里通常只有一个内核，但显示信息
    print_info "已安装内核: $installed_kernels"
}

# Zypper系统清理（openSUSE）
clean_zypper() {
    print_header "=== Zypper系统清理 ==="
    echo ""
    
    print_step "清理包缓存..."
    zypper clean --all
    print_success "已清理包缓存"
    
    print_step "移除不需要的包..."
    zypper remove -u --no-confirm
    print_success "已移除不需要的包"
    
    # 清理内核
    clean_kernel_zypper
    
    echo ""
}

# Zypper内核清理
clean_kernel_zypper() {
    print_step "检查内核..."
    
    # 获取当前运行的内核版本
    local current_kernel=$(uname -r)
    print_info "当前运行内核: $current_kernel"
    
    # 列出旧内核
    local old_kernels=$(zypper se -i 'kernel-*' | grep installed | grep -v "$current_kernel" || true)
    
    if [ -z "$old_kernels" ]; then
        print_info "没有多余内核可以清理"
        return
    fi
    
    print_warning "发现可移除的旧内核"
    echo ""
    
    print_question "是否删除旧内核? (y/n):"
    read -p "> " confirm
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        zypper remove -u kernel --no-confirm 2>/dev/null || true
        print_success "旧内核已移除"
        
        # 更新GRUB
        print_step "更新GRUB启动引导..."
        if command -v grub2-mkconfig &> /dev/null; then
            grub2-mkconfig -o /boot/grub2/grub.cfg
        fi
        print_success "GRUB已更新"
    fi
}

# 通用系统清理
clean_system() {
    print_header "=== 通用系统清理 ==="
    echo ""
    
    # 1. 清理系统日志
    print_step "清理系统日志..."
    journalctl --vacuum=7d
    print_success "已清理7天以前的日志"
    
    # 2. 清理临时文件
    print_step "清理临时文件..."
    rm -rf /tmp/* 2>/dev/null || true
    rm -rf /var/tmp/* 2>/dev/null || true
    print_success "已清理临时文件"
    
    # 3. 清理缓存
    print_step "清理系统缓存..."
    sync && sysctl -w vm.drop_caches=3 > /dev/null 2>&1 || true
    print_success "已清理缓存"
    
    echo ""
}

# 用户缓存清理
clean_user_cache() {
    print_header "=== 用户缓存清理 ==="
    echo ""
    
    print_question "是否清理用户缓存? (y/n):"
    read -p "> " confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        return
    fi
    
    # 清理缩略图
    print_step "清理缩略图缓存..."
    rm -rf ~/.cache/thumbnails/* 2>/dev/null || true
    print_success "已清理缩略图缓存"
    
    # 清理浏览器缓存（如果存在）
    print_step "清理浏览器缓存..."
    rm -rf ~/.cache/google-chrome/* 2>/dev/null || true
    rm -rf ~/.mozilla/firefox/*/cache* 2>/dev/null || true
    print_success "已清理浏览器缓存"
    
    echo ""
}

# 显示清理统计
show_statistics() {
    print_header "=== 清理完成 ==="
    echo ""
    print_success "系统清理已完成!"
    echo ""
    print_info "已执行的清理操作:"
    echo -e "  ${CYAN}✓ 移除不需要的依赖${NC}"
    echo -e "  ${CYAN}✓ 清理包管理器缓存${NC}"
    echo -e "  ${CYAN}✓ 清理系统日志${NC}"
    echo -e "  ${CYAN}✓ 清理临时文件${NC}"
    echo -e "  ${CYAN}✓ 清理系统缓存${NC}"
    echo ""
    print_info "建议定期运行此脚本以保持系统整洁"
}

# 主函数
main() {
    print_header "========================================"
    print_header "       Linux 系统清理工具"
    print_header "========================================"
    echo ""
    print_info "安全的系统清理助手"
    print_info "支持: Debian/Ubuntu, Fedora/RHEL, Arch, openSUSE"
    echo ""
    
    # 检查权限
    check_root
    
    # 检测发行版
    local distro=$(detect_distro)
    local pkg_manager=$(detect_package_manager)
    
    print_info "检测到系统: $distro"
    print_info "包管理器: $pkg_manager"
    echo ""
    
    if [ "$pkg_manager" == "unknown" ]; then
        print_error "不支持的系统或包管理器"
        wait_for_exit 5
        exit 1
    fi
    
    # 显示警告
    echo ""
    print_warning "========================================"
    print_warning "          清理前请备份重要数据!"
    print_warning "========================================"
    echo ""
    
    print_question "确认继续? (y/n):"
    read -p "> " confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_info "操作已取消"
        exit 0
    fi
    
    echo ""
    echo ""
    
    # 执行相应的清理
    case "$pkg_manager" in
        apt)
            clean_apt
            ;;
        dnf)
            clean_dnf
            ;;
        yum)
            clean_dnf
            ;;
        pacman)
            clean_pacman
            ;;
        zypper)
            clean_zypper
            ;;
    esac
    
    # 通用清理
    clean_system
    
    # 用户缓存清理
    clean_user_cache
    
    # 显示统计
    show_statistics
    
    wait_for_exit 10
}

# 运行主函数
main "$@"