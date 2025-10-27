#!/bin/bash
# Fix Usb
# DESCRIPTION: 检测并修复USB设备问题（全Linux发行版兼容）
# REQUIRES_SUDO: true


# USB盘一键修复脚本
# 支持FAT32, exFAT, NTFS, ext4等常见文件系统
# 适用于所有Linux发行版

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

# 等待函数
wait_for_exit() {
    local seconds=${1:-5}
    echo ""
    echo -e "${BLUE}[INFO]${NC} 脚本将在 ${seconds} 秒后自动退出..."
    sleep $seconds
    exit 0
}

# 打印带颜色的消息
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_step() {
    echo -e "${CYAN}➜${NC} $1"
}

print_header() {
    echo -e "${WHITE}$1${NC}"
}

# 检查是否以root权限运行
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "请使用 sudo 运行此脚本"
        wait_for_exit 5
        exit 1
    fi
}

# 全局设备数组
declare -a DEVICES
DEVICE_COUNT=0

# 修复的设备检测函数 - 正确解析lsblk输出
list_removable_devices() {
    print_info "正在扫描可移动设备..." >&2
    echo "" >&2
    
    DEVICES=()
    DEVICE_COUNT=0
    
    # 方法1: 使用lsblk检测所有可移动设备（仅显示USB设备）
    print_step "使用lsblk检测USB设备..." >&2
    
    # 获取所有USB设备（排除系统硬盘）
    while IFS= read -r device_info; do
        [ -z "$device_info" ] && continue
        
        # 解析设备信息
        local device_name=$(echo "$device_info" | awk '{print $1}')
        local device_type=$(echo "$device_info" | awk '{print $2}')
        local device_size=$(echo "$device_info" | awk '{print $3}')
        local device_model=$(echo "$device_info" | awk '{print $4}')
        local device_ro=$(echo "$device_info" | awk '{print $5}')
        
        # 跳过系统硬盘（sda, nvme0n1等）和loop设备
        if [[ "$device_name" =~ ^(sda|nvme0n1|mmcblk0|loop) ]]; then
            continue
        fi
        
        # 只显示磁盘设备和分区
        if [[ "$device_type" != "disk" && "$device_type" != "part" ]]; then
            continue
        fi
        
        # 对于分区，检查其父设备是否为可移动设备
        if [[ "$device_type" == "part" ]]; then
            local parent_device=$(lsblk -n -o PKNAME "/dev/$device_name" 2>/dev/null)
            if [[ ! "$parent_device" =~ ^(sdb|sdc|sd[d-z]) ]]; then
                continue
            fi
        fi
        
        DEVICE_COUNT=$((DEVICE_COUNT + 1))
        local device_path="/dev/$device_name"
        DEVICES+=("$device_path")
        
        echo -e "${GREEN}[$DEVICE_COUNT]${NC} $device_path" >&2
        echo "    类型: $device_type" >&2
        
        # 获取更详细的型号信息
        local detailed_model=$(lsblk -n -o MODEL "$device_path" 2>/dev/null | head -1)
        if [ -n "$detailed_model" ] && [ "$detailed_model" != "-" ]; then
            echo "    型号: $detailed_model" >&2
        elif [ -n "$device_model" ] && [ "$device_model" != "-" ]; then
            echo "    型号: $device_model" >&2
        fi
        
        echo "    大小: $device_size" >&2
        
        # 检查是否只读
        local detailed_ro=$(lsblk -n -o RO "$device_path" 2>/dev/null | head -1)
        if [ "$detailed_ro" == "1" ] || [ "$device_ro" == "1" ]; then
            echo -e "    状态: ${RED}只读${NC}" >&2
        else
            echo -e "    状态: ${GREEN}可读写${NC}" >&2
        fi
        
        # 获取文件系统信息
        local fs_type=$(lsblk -n -o FSTYPE "$device_path" 2>/dev/null | head -1)
        local label=$(lsblk -n -o LABEL "$device_path" 2>/dev/null | head -1)
        local mount_point=$(lsblk -n -o MOUNTPOINT "$device_path" 2>/dev/null | head -1)
        
        [ -n "$fs_type" ] && [ "$fs_type" != "-" ] && echo "    文件系统: $fs_type" >&2
        [ -n "$label" ] && [ "$label" != "-" ] && echo "    标签: $label" >&2
        [ -n "$mount_point" ] && [ "$mount_point" != "-" ] && echo "    挂载点: $mount_point" >&2
        
        echo "" >&2
        
    done < <(lsblk -n -o NAME,TYPE,SIZE,MODEL,RO 2>/dev/null | grep -E '(disk|part)')
    
    # 方法2: 如果没找到USB设备，尝试直接检测sdX设备
    if [ $DEVICE_COUNT -eq 0 ]; then
        print_step "尝试直接检测USB设备..." >&2
        
        # 直接检测所有sdX设备（排除sda）
        for device in /dev/sd*; do
            # 跳过sda和分区数字大于1的（只显示磁盘和第一个分区）
            if [[ "$device" =~ /dev/sda ]] || [[ "$device" =~ /dev/sd[a-z][2-9] ]]; then
                continue
            fi
            
            # 检查设备是否存在且是块设备
            if [ -b "$device" ]; then
                local device_name=$(basename "$device")
                local size=$(lsblk -n -o SIZE "$device" 2>/dev/null | head -1)
                local model=$(lsblk -n -o MODEL "$device" 2>/dev/null | head -1)
                local ro=$(lsblk -n -o RO "$device" 2>/dev/null | head -1)
                local fs_type=$(lsblk -n -o FSTYPE "$device" 2>/dev/null | head -1)
                local label=$(lsblk -n -o LABEL "$device" 2>/dev/null | head -1)
                local mount_point=$(lsblk -n -o MOUNTPOINT "$device" 2>/dev/null | head -1)
                local type=$(lsblk -n -o TYPE "$device" 2>/dev/null | head -1)
                
                DEVICE_COUNT=$((DEVICE_COUNT + 1))
                DEVICES+=("$device")
                
                echo -e "${GREEN}[$DEVICE_COUNT]${NC} $device" >&2
                echo "    类型: $type" >&2
                [ -n "$model" ] && [ "$model" != "-" ] && echo "    型号: $model" >&2
                echo "    大小: $size" >&2
                
                if [ "$ro" == "1" ]; then
                    echo -e "    状态: ${RED}只读${NC}" >&2
                else
                    echo -e "    状态: ${GREEN}可读写${NC}" >&2
                fi
                
                [ -n "$fs_type" ] && [ "$fs_type" != "-" ] && echo "    文件系统: $fs_type" >&2
                [ -n "$label" ] && [ "$label" != "-" ] && echo "    标签: $label" >&2
                [ -n "$mount_point" ] && [ "$mount_point" != "-" ] && echo "    挂载点: $mount_point" >&2
                echo "" >&2
            fi
        done
    fi
    
    if [ $DEVICE_COUNT -eq 0 ]; then
        print_error "未检测到可移动USB设备" >&2
        print_info "提示: 请确保USB盘已正确连接" >&2
        wait_for_exit 10
        exit 1
    fi
}

# 检测文件系统类型
detect_filesystem() {
    local device=$1
    local fs_type=$(blkid -o value -s TYPE "$device" 2>/dev/null)
    
    if [ -z "$fs_type" ]; then
        fs_type=$(lsblk -n -o FSTYPE "$device" 2>/dev/null)
    fi
    
    echo "$fs_type"
}

# 检查并安装必要的工具
check_and_install_tools() {
    local fs_type=$1
    local missing_tools=()
    
    case "$fs_type" in
        vfat|fat32|fat16|fat12)
            if ! command -v fsck.vfat &> /dev/null; then
                missing_tools+=("dosfstools")
            fi
            ;;
        exfat)
            if ! command -v fsck.exfat &> /dev/null; then
                missing_tools+=("exfat-fuse exfat-utils")
            fi
            ;;
        ntfs)
            if ! command -v ntfsfix &> /dev/null; then
                missing_tools+=("ntfs-3g")
            fi
            ;;
        ext4|ext3|ext2)
            if ! command -v fsck.ext4 &> /dev/null; then
                missing_tools+=("e2fsprogs")
            fi
            ;;
        xfs)
            if ! command -v xfs_repair &> /dev/null; then
                missing_tools+=("xfsprogs")
            fi
            ;;
        btrfs)
            if ! command -v btrfs &> /dev/null; then
                missing_tools+=("btrfs-progs")
            fi
            ;;
    esac
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        print_warning "需要安装以下工具: ${missing_tools[*]}"
        print_info "正在尝试自动安装..."
        
        # 检测包管理器并安装
        if command -v apt-get &> /dev/null; then
            apt-get update -qq
            apt-get install -y ${missing_tools[*]}
        elif command -v dnf &> /dev/null; then
            dnf install -y ${missing_tools[*]}
        elif command -v yum &> /dev/null; then
            yum install -y ${missing_tools[*]}
        elif command -v pacman &> /dev/null; then
            pacman -Sy --noconfirm ${missing_tools[*]}
        elif command -v zypper &> /dev/null; then
            zypper install -y ${missing_tools[*]}
        else
            print_error "无法识别包管理器，请手动安装: ${missing_tools[*]}"
            return 1
        fi
        
        print_success "工具安装完成"
    fi
    
    return 0
}

# 卸载设备
unmount_device() {
    local device=$1
    
    print_info "正在卸载设备 $device ..."
    
    # 获取所有挂载点
    local mount_points=$(mount | grep "^$device" | awk '{print $3}')
    
    if [ -n "$mount_points" ]; then
        while IFS= read -r mp; do
            if umount "$mp" 2>/dev/null; then
                print_success "已卸载: $mp"
            else
                print_warning "强制卸载: $mp"
                umount -l "$mp" 2>/dev/null || true
            fi
        done <<< "$mount_points"
        sleep 1
    else
        print_info "设备未挂载"
    fi
}

# 修复文件系统
repair_filesystem() {
    local device=$1
    local fs_type=$2
    
    case "$fs_type" in
        vfat|fat32|fat16|fat12)
            print_info "执行: fsck.vfat -av $device"
            echo -e "${YELLOW}修复过程中...${NC}"
            echo "----------------------------------------"
            fsck.vfat -av "$device" 2>&1 | while IFS= read -r line; do
                echo "$line"
            done
            local result=${PIPESTATUS[0]}
            echo "----------------------------------------"
            if [ $result -eq 0 ] || [ $result -eq 1 ]; then
                print_success "FAT文件系统修复完成"
                return 0
            else
                print_error "FAT文件系统修复失败"
                return 1
            fi
            ;;
        exfat)
            print_info "执行: fsck.exfat $device"
            echo -e "${YELLOW}修复过程中...${NC}"
            echo "----------------------------------------"
            fsck.exfat "$device" 2>&1 | while IFS= read -r line; do
                echo "$line"
            done
            local result=${PIPESTATUS[0]}
            echo "----------------------------------------"
            if [ $result -eq 0 ]; then
                print_success "exFAT文件系统修复完成"
                return 0
            else
                print_error "exFAT文件系统修复失败"
                return 1
            fi
            ;;
        ntfs)
            print_info "执行: ntfsfix -d $device"
            echo -e "${YELLOW}修复过程中...${NC}"
            echo "----------------------------------------"
            ntfsfix -d "$device" 2>&1 | while IFS= read -r line; do
                echo "$line"
            done
            local result=${PIPESTATUS[0]}
            echo "----------------------------------------"
            if [ $result -eq 0 ]; then
                print_success "NTFS文件系统修复完成"
                return 0
            else
                print_error "NTFS文件系统修复失败"
                return 1
            fi
            ;;
        ext4|ext3|ext2)
            print_info "执行: fsck.ext4 -fy $device"
            echo -e "${YELLOW}修复过程中...${NC}"
            echo "----------------------------------------"
            fsck.ext4 -fy "$device" 2>&1 | while IFS= read -r line; do
                echo "$line"
            done
            local result=${PIPESTATUS[0]}
            echo "----------------------------------------"
            if [ $result -eq 0 ] || [ $result -eq 1 ]; then
                print_success "EXT文件系统修复完成"
                return 0
            else
                print_error "EXT文件系统修复失败"
                return 1
            fi
            ;;
        xfs)
            print_info "执行: xfs_repair -v $device"
            echo -e "${YELLOW}修复过程中...${NC}"
            echo "----------------------------------------"
            xfs_repair -v "$device" 2>&1 | while IFS= read -r line; do
                echo "$line"
            done
            local result=${PIPESTATUS[0]}
            echo "----------------------------------------"
            if [ $result -eq 0 ]; then
                print_success "XFS文件系统修复完成"
                return 0
            else
                print_error "XFS文件系统修复失败"
                return 1
            fi
            ;;
        btrfs)
            print_info "执行: btrfs check --repair $device"
            echo -e "${YELLOW}修复过程中...${NC}"
            echo "----------------------------------------"
            btrfs check --repair "$device" 2>&1 | while IFS= read -r line; do
                echo "$line"
            done
            local result=${PIPESTATUS[0]}
            echo "----------------------------------------"
            if [ $result -eq 0 ]; then
                print_success "BTRFS文件系统修复完成"
                return 0
            else
                print_error "BTRFS文件系统修复失败"
                return 1
            fi
            ;;
        *)
            print_error "不支持的文件系统类型: $fs_type"
            return 1
            ;;
    esac
}

# 主函数
main() {
    echo ""
    print_header "======================================"
    print_header "   USB盘一键修复工具"
    print_header "======================================"
    echo ""
    
    check_root
    
    # 列出设备
    list_removable_devices
    
    if [ $DEVICE_COUNT -eq 0 ]; then
        print_error "未找到可用设备"
        wait_for_exit 10
        exit 1
    fi
    
    # 选择设备
    read -p "$(echo -e "${PURPLE}[INPUT]${NC} 请选择要修复的设备编号 [1-${DEVICE_COUNT}]: ")" choice
    
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt $DEVICE_COUNT ]; then
        print_error "无效的选择"
        wait_for_exit 5
        exit 1
    fi
    
    local selected_device="${DEVICES[$((choice-1))]}"
    
    echo ""
    print_warning "即将修复设备: $selected_device"
    read -p "$(echo -e "${PURPLE}[INPUT]${NC} 是否继续? [y/N]: ")" confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_info "操作已取消"
        wait_for_exit 3
        exit 0
    fi
    
    echo ""
    
    # 检测文件系统
    local fs_type=$(detect_filesystem "$selected_device")
    
    if [ -z "$fs_type" ]; then
        print_error "无法检测文件系统类型"
        wait_for_exit 10
        exit 1
    fi
    
    print_info "检测到文件系统: $fs_type"
    
    # 检查并安装工具
    if ! check_and_install_tools "$fs_type"; then
        wait_for_exit 10
        exit 1
    fi
    
    # 卸载设备
    unmount_device "$selected_device"
    
    echo ""
    
    # 修复文件系统
    if repair_filesystem "$selected_device" "$fs_type"; then
        echo ""
        print_success "===== 修复完成 ====="
        print_info "你现在可以安全地拔出并重新插入USB盘"
        wait_for_exit 15
    else
        echo ""
        print_error "===== 修复失败 ====="
        print_warning "建议在Windows系统中尝试修复，或考虑重新格式化USB盘"
        wait_for_exit 15
    fi
}

# 运行主函数
main