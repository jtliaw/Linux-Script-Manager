#!/bin/bash
# Format Usb
# DESCRIPTION: 快速格式化USB设备（全Linux发行版兼容）
# REQUIRES_SUDO: true

# USB盘极简格式化工具 - 修复版

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

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

# 错误处理函数
error_handler() {
    print_error "脚本执行出错，错误发生在第 $1 行"
    print_info "请检查:"
    print_info "1. 是否所有依赖工具已安装"
    print_info "2. 是否有足够的权限"
    print_info "3. 设备是否可用"
    wait_for_exit 10
}

trap 'error_handler $LINENO' ERR

check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "请使用 sudo 运行此脚本"
        exit 1
    fi
}

# 改进的设备显示函数 - 使用多种方法检测只读状态
show_devices() {
    print_header "=== 选择USB设备 ==="
    echo ""
    
    # 使用更简单的方法列出USB设备
    local count=0
    
    # 获取所有非系统磁盘
    while IFS= read -r device; do
        # 跳过空行和系统磁盘
        if [ -z "$device" ] || [[ "$device" =~ ^(sda|nvme0n1|mmcblk0) ]]; then
            continue
        fi
        
        count=$((count + 1))
        
        # 获取设备信息
        local size=$(lsblk -n -o SIZE "/dev/$device" 2>/dev/null | head -1)
        local model=$(lsblk -n -o MODEL "/dev/$device" 2>/dev/null | head -1)
        
        # 多种方法检测只读状态
        local ro_status="0"
        
        # 方法1: 使用lsblk
        local lsblk_ro=$(lsblk -n -o RO "/dev/$device" 2>/dev/null | head -1)
        if [ "$lsblk_ro" == "1" ]; then
            ro_status="1"
        fi
        
        # 方法2: 检查sys文件系统
        if [ -f "/sys/block/$device/ro" ]; then
            local sys_ro=$(cat "/sys/block/$device/ro" 2>/dev/null)
            if [ "$sys_ro" == "1" ]; then
                ro_status="1"
            fi
        fi
        
        # 方法3: 尝试写入测试（最终验证）
        local test_file="/dev/${device}_test_write"
        if timeout 5s touch "$test_file" 2>/dev/null; then
            rm -f "$test_file" 2>/dev/null
        else
            ro_status="1"
        fi
        
        # 显示设备信息
        echo -e "  ${GREEN}[$count]${NC} ${CYAN}/dev/$device${NC}"
        echo -e "      ${BLUE}大小:${NC} $size"
        [ -n "$model" ] && echo -e "      ${BLUE}型号:${NC} $model"
        
        if [ "$ro_status" == "1" ]; then
            echo -e "      ${RED}状态: 只读(无法格式化)${NC}"
        else
            echo -e "      ${GREEN}状态: 可读写${NC}"
        fi
        
        # 显示分区信息（如果有）
        local partitions=$(lsblk -n -o NAME "/dev/$device" | grep -E "^${device}[0-9]+")
        if [ -n "$partitions" ]; then
            echo -e "      ${BLUE}分区:${NC}"
            while IFS= read -r part; do
                local part_size=$(lsblk -n -o SIZE "/dev/$part" 2>/dev/null | head -1)
                local part_fs=$(lsblk -n -o FSTYPE "/dev/$part" 2>/dev/null | head -1)
                local part_mount=$(lsblk -n -o MOUNTPOINT "/dev/$part" 2>/dev/null | head -1)
                local mount_info=""
                [ -n "$part_mount" ] && [ "$part_mount" != "-" ] && mount_info=" (挂载于: $part_mount)"
                echo -e "        ${YELLOW}•${NC} /dev/$part - $part_size - ${part_fs:-未知}${mount_info}"
            done <<< "$partitions"
        fi
        
        echo ""
    done < <(lsblk -n -o NAME,TYPE | awk '$2=="disk"{print $1}' | grep -vE '^(sda|nvme0n1|mmcblk0)')
    
    if [ $count -eq 0 ]; then
        print_error "未找到USB设备"
        wait_for_exit 5
        return 1
    fi
    
    return 0
}

get_device_by_index() {
    local index=$1
    local count=0
    
    while IFS= read -r device; do
        # 跳过空行和系统磁盘
        if [ -z "$device" ] || [[ "$device" =~ ^(sda|nvme0n1|mmcblk0) ]]; then
            continue
        fi
        
        count=$((count + 1))
        if [ $count -eq $index ]; then
            echo "/dev/$device"
            return 0
        fi
    done < <(lsblk -n -o NAME,TYPE | awk '$2=="disk"{print $1}' | grep -vE '^(sda|nvme0n1|mmcblk0)')
    
    return 1
}

count_devices() {
    local count=0
    
    while IFS= read -r device; do
        # 跳过空行和系统磁盘
        if [ -z "$device" ] || [[ "$device" =~ ^(sda|nvme0n1|mmcblk0) ]]; then
            continue
        fi
        count=$((count + 1))
    done < <(lsblk -n -o NAME,TYPE | awk '$2=="disk"{print $1}' | grep -vE '^(sda|nvme0n1|mmcblk0)')
    
    echo $count
}

# 改进的只读状态检测函数
get_device_ro_status() {
    local device=$1
    local device_name=$(basename "$device")
    
    # 方法1: 使用lsblk
    local lsblk_ro=$(lsblk -n -o RO "$device" 2>/dev/null | head -1)
    if [ "$lsblk_ro" == "1" ]; then
        echo "1"
        return 0
    fi
    
    # 方法2: 检查sys文件系统
    if [ -f "/sys/block/$device_name/ro" ]; then
        local sys_ro=$(cat "/sys/block/$device_name/ro" 2>/dev/null)
        if [ "$sys_ro" == "1" ]; then
            echo "1"
            return 0
        fi
    fi
    
    # 方法3: 尝试写入测试
    local test_file="${device}_test_write_$(date +%s)"
    if timeout 3s touch "$test_file" 2>/dev/null; then
        rm -f "$test_file" 2>/dev/null
        echo "0"
    else
        echo "1"
    fi
}

install_tools() {
    local fs_type=$1
    
    case "$fs_type" in
        fat16|fat32)
            if ! command -v mkfs.fat &> /dev/null && ! command -v mkfs.vfat &> /dev/null; then
                print_step "安装 dosfstools..."
                if command -v apt-get &> /dev/null; then
                    apt-get update && apt-get install -y dosfstools
                elif command -v dnf &> /dev/null; then
                    dnf install -y dosfstools
                elif command -v yum &> /dev/null; then
                    yum install -y dosfstools
                elif command -v pacman &> /dev/null; then
                    pacman -Sy --noconfirm dosfstools
                elif command -v zypper &> /dev/null; then
                    zypper install -y dosfstools
                else
                    print_error "无法自动安装dosfstools，请手动安装"
                    return 1
                fi
            fi
            ;;
        exfat)
            if ! command -v mkfs.exfat &> /dev/null; then
                print_step "安装 exfat工具..."
                if command -v apt-get &> /dev/null; then
                    apt-get update && apt-get install -y exfatprogs
                elif command -v dnf &> /dev/null; then
                    dnf install -y exfatprogs
                elif command -v yum &> /dev/null; then
                    yum install -y exfatprogs
                elif command -v pacman &> /dev/null; then
                    pacman -Sy --noconfirm exfatprogs
                elif command -v zypper &> /dev/null; then
                    zypper install -y exfatprogs
                else
                    print_error "无法自动安装exfatprogs，请手动安装"
                    return 1
                fi
            fi
            ;;
        ntfs)
            if ! command -v mkfs.ntfs &> /dev/null; then
                print_step "安装 ntfs-3g..."
                if command -v apt-get &> /dev/null; then
                    apt-get update && apt-get install -y ntfs-3g
                elif command -v dnf &> /dev/null; then
                    dnf install -y ntfs-3g
                elif command -v yum &> /dev/null; then
                    yum install -y ntfs-3g
                elif command -v pacman &> /dev/null; then
                    pacman -Sy --noconfirm ntfs-3g
                elif command -v zypper &> /dev/null; then
                    zypper install -y ntfs-3g
                else
                    print_error "无法自动安装ntfs-3g，请手动安装"
                    return 1
                fi
            fi
            ;;
        ext4)
            if ! command -v mkfs.ext4 &> /dev/null; then
                print_step "安装 e2fsprogs..."
                if command -v apt-get &> /dev/null; then
                    apt-get update && apt-get install -y e2fsprogs
                elif command -v dnf &> /dev/null; then
                    dnf install -y e2fsprogs
                elif command -v yum &> /dev/null; then
                    yum install -y e2fsprogs
                elif command -v pacman &> /dev/null; then
                    pacman -Sy --noconfirm e2fsprogs
                elif command -v zypper &> /dev/null; then
                    zypper install -y e2fsprogs
                else
                    print_error "无法自动安装e2fsprogs，请手动安装"
                    return 1
                fi
            fi
            ;;
        btrfs)
            if ! command -v mkfs.btrfs &> /dev/null; then
                print_step "安装 btrfs-progs..."
                if command -v apt-get &> /dev/null; then
                    apt-get update && apt-get install -y btrfs-progs
                elif command -v dnf &> /dev/null; then
                    dnf install -y btrfs-progs
                elif command -v yum &> /dev/null; then
                    yum install -y btrfs-progs
                elif command -v pacman &> /dev/null; then
                    pacman -Sy --noconfirm btrfs-progs
                elif command -v zypper &> /dev/null; then
                    zypper install -y btrfs-progs
                else
                    print_error "无法自动安装btrfs-progs，请手动安装"
                    return 1
                fi
            fi
            ;;
        xfs)
            if ! command -v mkfs.xfs &> /dev/null; then
                print_step "安装 xfsprogs..."
                if command -v apt-get &> /dev/null; then
                    apt-get update && apt-get install -y xfsprogs
                elif command -v dnf &> /dev/null; then
                    dnf install -y xfsprogs
                elif command -v yum &> /dev/null; then
                    yum install -y xfsprogs
                elif command -v pacman &> /dev/null; then
                    pacman -Sy --noconfirm xfsprogs
                elif command -v zypper &> /dev/null; then
                    zypper install -y xfsprogs
                else
                    print_error "无法自动安装xfsprogs，请手动安装"
                    return 1
                fi
            fi
            ;;
    esac
    return 0
}

# 简化卸载函数
unmount_device() {
    local device=$1
    
    print_step "卸载设备..."
    
    # 卸载所有相关分区
    for part in ${device}*; do
        if [ -b "$part" ] && mountpoint -q "$(lsblk -n -o MOUNTPOINT "$part" 2>/dev/null)" 2>/dev/null; then
            print_info "卸载: $part"
            umount "$part" 2>/dev/null || umount -l "$part" 2>/dev/null || true
        fi
    done
    
    sync
    sleep 1
    print_success "卸载完成"
}

# 格式化函数
format_device() {
    local device=$1
    local fs_type=$2
    local label=$3
    
    print_step "开始格式化..."
    
    # 清除设备签名
    wipefs -a "$device" 2>/dev/null || true
    
    # 设置格式化命令和参数
    local safe_label=$(echo "$label" | tr -cd '[:alnum:]_-' | cut -c1-11)
    local fs_cmd=""
    local fs_args=""
    
    case $fs_type in
        fat16)
            if command -v mkfs.fat &> /dev/null; then
                fs_cmd="mkfs.fat"
            else
                fs_cmd="mkfs.vfat"
            fi
            fs_args="-F 16"
            [ -n "$label" ] && fs_args="$fs_args -n $safe_label"
            ;;
        fat32)
            if command -v mkfs.fat &> /dev/null; then
                fs_cmd="mkfs.fat"
            else
                fs_cmd="mkfs.vfat"
            fi
            fs_args="-F 32"
            [ -n "$label" ] && fs_args="$fs_args -n $safe_label"
            ;;
        exfat)
            fs_cmd="mkfs.exfat"
            [ -n "$label" ] && fs_args="-n $safe_label"
            ;;
        ntfs)
            fs_cmd="mkfs.ntfs"
            fs_args="-f"
            [ -n "$label" ] && fs_args="$fs_args -L $safe_label"
            ;;
        ext4)
            fs_cmd="mkfs.ext4"
            fs_args="-F"
            [ -n "$label" ] && fs_args="$fs_args -L $safe_label"
            ;;
        btrfs)
            fs_cmd="mkfs.btrfs"
            fs_args="-f"
            [ -n "$label" ] && fs_args="$fs_args -L $safe_label"
            ;;
        xfs)
            fs_cmd="mkfs.xfs"
            fs_args="-f"
            [ -n "$label" ] && fs_args="$fs_args -L $safe_label"
            ;;
        *)
            print_error "不支持的文件系统: $fs_type"
            return 1
            ;;
    esac
    
    # 执行格式化
    echo -e "${CYAN}命令: $fs_cmd $fs_args $device${NC}"
    
    if $fs_cmd $fs_args "$device"; then
        print_success "格式化成功"
        return 0
    else
        print_error "格式化失败"
        return 1
    fi
}

main() {
    # 检查权限
    check_root
    
    print_header "========================================"
    print_header "          USB盘快速格式化工具"
    print_header "========================================"
    echo ""
    
    # 显示设备列表
    if ! show_devices; then
        wait_for_exit 5
        exit 1
    fi
    
    # 计算设备数量
    DEVICE_COUNT=$(count_devices)
    
    print_question "请选择要格式化的设备编号 [1-${DEVICE_COUNT}]"
    read -p "> " dev_choice
    
    # 验证输入
    if ! [[ "$dev_choice" =~ ^[0-9]+$ ]] || [ "$dev_choice" -lt 1 ] || [ "$dev_choice" -gt "$DEVICE_COUNT" ]; then
        print_error "无效的选择"
        wait_for_exit 5
        exit 1
    fi
    
    # 获取选择的设备
    DEVICE=$(get_device_by_index "$dev_choice")
    
    if [ -z "$DEVICE" ] || [ ! -b "$DEVICE" ]; then
        print_error "设备不存在: $DEVICE"
        wait_for_exit 5
        exit 1
    fi
    
    # 检查设备是否只读
    print_step "检查设备状态..."
    RO_STATUS=$(get_device_ro_status "$DEVICE")
    if [ "$RO_STATUS" == "1" ]; then
        echo ""
        print_error "========================================"
        print_error "          设备写保护，无法格式化!"
        print_error "========================================"
        echo ""
        print_info "设备 ${CYAN}$DEVICE${NC} 被设置为只读模式"
        print_info "这种情况通常是因为："
        echo -e "  ${YELLOW}•${NC} 厂家写保护的固件分区"
        echo -e "  ${YELLOW}•${NC} 物理写保护开关开启"
        echo -e "  ${YELLOW}•${NC} 设备硬件故障"
        echo ""
        print_info "请选择其他可写设备进行格式化"
        wait_for_exit 10
        exit 1
    else
        print_success "设备可写，可以继续格式化"
    fi
    
    echo ""
    print_header "选择文件系统:"
    echo -e "  ${GREEN}1)${NC} FAT16   ${YELLOW}(适用于老设备)${NC}"
    echo -e "  ${GREEN}2)${NC} FAT32   ${YELLOW}(最佳兼容性)${NC}"
    echo -e "  ${GREEN}3)${NC} exFAT   ${YELLOW}(大文件支持)${NC}"
    echo -e "  ${GREEN}4)${NC} NTFS    ${YELLOW}(Windows首选)${NC}"
    echo -e "  ${GREEN}5)${NC} Ext4    ${YELLOW}(Linux首选)${NC}"
    echo -e "  ${GREEN}6)${NC} Btrfs   ${YELLOW}(高级功能)${NC}"
    echo -e "  ${GREEN}7)${NC} XFS     ${YELLOW}(高性能)${NC}"
    echo ""
    
    print_question "请选择文件系统 [1-7]"
    read -p "> " fs_choice
    
    # 验证文件系统选择
    case $fs_choice in
        1) fs_type="fat16" ;;
        2) fs_type="fat32" ;;
        3) fs_type="exfat" ;;
        4) fs_type="ntfs" ;;
        5) fs_type="ext4" ;;
        6) fs_type="btrfs" ;;
        7) fs_type="xfs" ;;
        *) 
            print_error "无效选择"
            wait_for_exit 5
            exit 1 
            ;;
    esac
    
    echo ""
    print_question "请输入卷标 (直接回车跳过)"
    read -p "> " label
    
    # 安装必要工具
    if ! install_tools "$fs_type"; then
        print_error "工具安装失败"
        wait_for_exit 5
        exit 1
    fi
    
    echo ""
    print_warning "========================================"
    print_error "          警告: 数据将永久丢失!"
    print_warning "========================================"
    echo ""
    print_warning "即将格式化设备: ${CYAN}$DEVICE${NC}"
    print_warning "文件系统: ${CYAN}$fs_type${NC}"
    if [ -n "$label" ]; then
        print_warning "卷标: ${CYAN}$label${NC}"
    fi
    echo ""
    
    print_question "确认执行格式化? (y/N)"
    read -p "> " confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_info "操作已取消"
        wait_for_exit 3
        exit 0
    fi
    
    echo ""
    print_step "开始格式化过程..."
    
    # 卸载设备
    unmount_device "$DEVICE"
    
    # 执行格式化
    if format_device "$DEVICE" "$fs_type" "$label"; then
        echo ""
        print_success "========================================"
        print_success "          格式化成功完成!"
        print_success "========================================"
        echo ""
        print_info "设备信息:"
        lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT "$DEVICE" 2>/dev/null || true
        echo ""
        print_success "现在可以安全拔出USB设备了"
        wait_for_exit 10
    else
        echo ""
        print_error "========================================"
        print_error "          格式化失败!"
        print_error "========================================"
        echo ""
        print_info "可能的原因:"
        echo -e "  ${YELLOW}•${NC} 设备被写保护"
        echo -e "  ${YELLOW}•${NC} 设备硬件故障"
        echo -e "  ${YELLOW}•${NC} 格式化工具问题"
        wait_for_exit 10
    fi
}

# 运行主函数
main "$@"