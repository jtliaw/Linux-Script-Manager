#!/bin/bash
# Make Bootable USB
# DESCRIPTION: 使用dd命令创建USB系统启动盘（全Linux发行版兼容）
# REQUIRES_SUDO: true

# USB系统启动盘制作工具 - 修复版

# 注意：不使用 set -e，因为我们需要捕获函数的返回值

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

# 检查并安装必要工具
check_tools() {
    local distro=$(detect_distro)
    
    print_info "检测到系统: $distro"
    
    # 检查核心工具
    for tool in lsblk blkid mount umount dd sync; do
        if ! command -v $tool &> /dev/null; then
            print_error "缺少核心工具: $tool"
            return 1
        fi
    done
    
    print_success "必要工具检查完成"
    return 0
}

# 显示USB设备列表并返回设备数量
show_devices() {
    print_header "=== 选择USB设备 ===" >&2
    echo "" >&2
    
    local count=0
    
    # 使用lsblk获取USB设备
    print_step "扫描USB设备..." >&2
    echo "" >&2
    
    # 获取所有设备信息
    local device_info
    device_info=$(lsblk -n -o NAME,TYPE,SIZE,MODEL,RO 2>/dev/null | grep -E 'disk|part' || true)
    
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        
        local device=$(echo "$line" | awk '{print $1}')
        local type=$(echo "$line" | awk '{print $2}')
        local size=$(echo "$line" | awk '{print $3}')
        local model=$(echo "$line" | awk '{print $4}')
        local ro=$(echo "$line" | awk '{print $5}')
        
        # 只显示磁盘设备，跳过系统磁盘
        if [ "$type" == "disk" ] && [[ "$device" =~ ^(sd[b-z]|nvme[0-9]+n[1-9]|mmcblk[1-9]) ]]; then
            count=$((count + 1))
            
            echo -e "  ${GREEN}[$count]${NC} ${CYAN}/dev/$device${NC}" >&2
            echo -e "      ${BLUE}型号:${NC} $model" >&2
            echo -e "      ${BLUE}大小:${NC} $size" >&2
            
            if [ "$ro" == "1" ]; then
                echo -e "      ${RED}状态: 只读(无法使用)${NC}" >&2
            else
                echo -e "      ${GREEN}状态: 可读写${NC}" >&2
            fi
            
            # 显示分区信息
            local partitions=$(lsblk -n -o NAME,SIZE,FSTYPE,MOUNTPOINT "/dev/$device" | grep -E "^${device}[0-9]+" || true)
            if [ -n "$partitions" ]; then
                echo -e "      ${BLUE}现有分区:${NC}" >&2
                while IFS= read -r part_line; do
                    local part_name=$(echo "$part_line" | awk '{print $1}')
                    local part_size=$(echo "$part_line" | awk '{print $2}')
                    local part_fs=$(echo "$part_line" | awk '{print $3}')
                    local part_mount=$(echo "$part_line" | awk '{print $4}')
                    local mount_info=""
                    [ -n "$part_mount" ] && [ "$part_mount" != "-" ] && mount_info=" (挂载于: $part_mount)"
                    echo -e "        ${YELLOW}•${NC} /dev/$part_name - $part_size - $part_fs$mount_info" >&2
                done <<< "$partitions"
            fi
            
            echo "" >&2
        fi
    done <<< "$device_info"
    
    if [ $count -eq 0 ]; then
        print_error "未找到可用的USB设备" >&2
        return 1
    fi
    
    # 只输出数字到stdout
    echo $count
}

# 根据索引获取设备
get_device_by_index() {
    local index=$1
    local count=0
    
    # 获取所有设备信息
    local device_info
    device_info=$(lsblk -n -o NAME,TYPE 2>/dev/null)
    
    while IFS= read -r line; do
        local device=$(echo "$line" | awk '{print $1}')
        local type=$(echo "$line" | awk '{print $2}')
        
        # 只显示磁盘设备，跳过系统磁盘
        if [ "$type" == "disk" ] && [[ "$device" =~ ^(sd[b-z]|nvme[0-9]+n[1-9]|mmcblk[1-9]) ]]; then
            count=$((count + 1))
            if [ $count -eq $index ]; then
                echo "/dev/$device"
                return 0
            fi
        fi
    done <<< "$device_info"
    
    return 1
}

# 检查设备是否只读
get_device_ro_status() {
    local device=$1
    local device_name=$(basename "$device")
    lsblk -n -o RO "/dev/$device_name" 2>/dev/null | head -1
}

# 卸载设备
unmount_device() {
    local device=$1
    
    print_step "卸载设备..."
    
    # 获取设备的所有分区
    local partitions
    partitions=$(lsblk -n -o NAME "$device" | grep -E "^$(basename "$device")[0-9]+" || true)
    
    # 卸载所有分区
    for part in $partitions; do
        local part_path="/dev/$part"
        local mount_point
        mount_point=$(lsblk -n -o MOUNTPOINT "$part_path" 2>/dev/null | head -1)
        
        if [ -n "$mount_point" ] && [ "$mount_point" != "-" ]; then
            print_info "卸载分区: $part_path"
            if umount "$part_path" 2>/dev/null; then
                print_success "成功卸载: $part_path"
            else
                print_warning "强制卸载: $part_path"
                umount -l "$part_path" 2>/dev/null || true
            fi
        fi
    done
    
    sync
    sleep 2
    print_success "设备卸载完成"
}

# 验证ISO文件
verify_iso() {
    local iso_file=$1
    
    print_step "验证ISO文件..."
    
    if [ ! -f "$iso_file" ]; then
        print_error "ISO文件不存在: $iso_file"
        return 1
    fi
    
    # 检查文件是否可读
    if [ ! -r "$iso_file" ]; then
        print_error "无法读取ISO文件: $iso_file"
        return 1
    fi
    
    local file_size
    file_size=$(du -h "$iso_file" 2>/dev/null | cut -f1 || echo "未知")
    local file_type
    file_type=$(file -b "$iso_file" 2>/dev/null || echo "未知")
    
    print_info "文件: $(basename "$iso_file")"
    print_info "路径: $(dirname "$(realpath "$iso_file")")"
    print_info "大小: $file_size"
    print_info "类型: $file_type"
    
    # 基本文件大小检查
    local min_size=100000000  # 100MB
    local actual_size
    actual_size=$(stat -c%s "$iso_file" 2>/dev/null || echo "0")
    
    if [ "$actual_size" -lt "$min_size" ]; then
        print_warning "ISO文件可能太小，可能不是有效的系统镜像"
        print_question "是否继续? (y/N)"
        read -p "> " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            return 1
        fi
    fi
    
    print_success "ISO文件验证完成"
    return 0
}

# 使用dd写入ISO
write_iso_with_dd() {
    local device=$1
    local iso_file=$2
    
    print_header "开始写入系统镜像..."
    echo ""
    
    print_info "源文件: $(basename "$iso_file")"
    print_info "目标设备: $device"
    
    # 获取文件大小（如果blockdev不可用则跳过）
    local iso_size=0
    local device_size=0
    
    if command -v blockdev &> /dev/null; then
        iso_size=$(blockdev --getsize64 "$iso_file" 2>/dev/null || stat -c%s "$iso_file" 2>/dev/null || echo "0")
        device_size=$(blockdev --getsize64 "$device" 2>/dev/null || echo "0")
        
        if command -v numfmt &> /dev/null; then
            print_info "文件大小: $(numfmt --to=iec $iso_size)"
            print_info "设备大小: $(numfmt --to=iec $device_size)"
        else
            print_info "文件大小: ${iso_size} 字节"
            print_info "设备大小: ${device_size} 字节"
        fi
        
        # 检查设备容量是否足够
        if [ "$iso_size" -gt "$device_size" ]; then
            print_error "ISO文件大小超过设备容量!"
            return 1
        fi
    else
        print_warning "无法精确检查容量，请确保设备空间足够"
    fi
    
    print_warning "========================================"
    print_error "          警告: 数据将永久丢失!"
    print_warning "========================================"
    echo ""
    print_warning "这将完全清除设备: ${CYAN}$device${NC}"
    print_warning "并写入系统镜像: ${CYAN}$(basename "$iso_file")${NC}"
    echo ""
    
    print_question "确认执行? (y/n):"
    read -p "> " confirm
    echo ""
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_info "操作已取消"
        return 1
    fi
    
    echo ""
    print_step "开始写入过程..."
    
    # 卸载设备
    unmount_device "$device"
    
    # 清除设备签名（如果wipefs可用）
    if command -v wipefs &> /dev/null; then
        print_step "清除设备签名..."
        wipefs -a "$device" 2>/dev/null || true
    fi
    
    # 使用dd写入
    print_step "使用dd写入镜像..."
    
    # 开始时间
    local start_time
    start_time=$(date +%s)
    
    # 方法1: 使用pv显示进度（如果可用）
    if command -v pv &> /dev/null; then
        print_info "使用pv显示实时进度..."
        echo -e "${CYAN}命令: pv \"$iso_file\" | dd of=\"$device\" bs=4M${NC}"
        echo ""
        if pv "$iso_file" | dd of="$device" bs=4M 2>/dev/null; then
            local result=0
        else
            local result=1
        fi
        
    # 方法2: 使用dd的status=progress（如果支持）
    elif dd --help 2>&1 | grep -q "status=progress"; then
        print_info "使用dd内置进度显示..."
        echo -e "${CYAN}命令: dd if=\"$iso_file\" of=\"$device\" bs=4M status=progress${NC}"
        echo ""
        if dd if="$iso_file" of="$device" bs=4M status=progress; then
            local result=0
        else
            local result=1
        fi
        
    # 方法3: 基本dd命令（无进度显示）
    else
        print_warning "无法显示实时进度，请耐心等待..."
        echo -e "${CYAN}命令: dd if=\"$iso_file\" of=\"$device\" bs=4M${NC}"
        echo ""
        print_info "正在写入，这可能需要几分钟..."
        if dd if="$iso_file" of="$device" bs=4M 2>/dev/null; then
            local result=0
        else
            local result=1
        fi
    fi
    
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    if [ $result -eq 0 ]; then
        print_success "写入完成!"
        print_info "耗时: ${duration} 秒"
        
        # 同步确保数据写入
        print_step "同步数据..."
        sync
        
        print_success "========================================"
        print_success "      USB启动盘制作成功!"
        print_success "========================================"
        echo ""
        print_success "现在可以安全拔出USB设备并使用它启动系统了"
        return 0
    else
        print_error "写入失败!"
        print_info "可能的原因:"
        echo -e "  ${YELLOW}•${NC} 设备被写保护"
        echo -e "  ${YELLOW}•${NC} 设备硬件故障"
        echo -e "  ${YELLOW}•${NC} ISO文件损坏"
        echo -e "  ${YELLOW}•${NC} 写入过程中断"
        echo -e "  ${YELLOW}•${NC} 空间不足"
        return 1
    fi
}

# 主函数
main() {
    print_header "========================================"
    print_header "      USB系统启动盘制作工具"
    print_header "========================================"
    echo ""
    print_info "使用dd命令创建可启动USB设备"
    print_info "兼容所有Linux发行版"
    echo ""
    
    # 检查权限
    check_root
    
    # 检查必要工具
    if ! check_tools; then
        wait_for_exit 10
        exit 1
    fi
    
    # 显示设备列表
    show_devices 2>&1
    device_count=$(show_devices 2>/dev/null | tail -1)
    
    if [ -z "$device_count" ] || ! [[ "$device_count" =~ ^[0-9]+$ ]]; then
        wait_for_exit 10
        exit 1
    fi
    
    # 选择设备
    echo ""
    print_question "请选择目标USB设备 [1-${device_count}]"
    read -p "> " dev_choice
    
    # 验证输入
    if ! [[ "$dev_choice" =~ ^[0-9]+$ ]] || [ "$dev_choice" -lt 1 ] || [ "$dev_choice" -gt "$device_count" ]; then
        print_error "无效的选择: $dev_choice"
        wait_for_exit 5
        exit 1
    fi
    
    # 获取选择的设备
    selected_device=$(get_device_by_index "$dev_choice")
    
    if [ -z "$selected_device" ] || [ ! -b "$selected_device" ]; then
        print_error "设备不存在或不可用: $selected_device"
        wait_for_exit 5
        exit 1
    fi
    
    print_success "已选择设备: $selected_device"
    
    # 检查设备是否只读
    ro_status=$(get_device_ro_status "$selected_device")
    if [ "$ro_status" == "1" ]; then
        print_error "设备写保护，无法使用: $selected_device"
        wait_for_exit 10
        exit 1
    fi
    
    echo ""
    print_header "=== 选择系统镜像 ==="
    echo ""
    
    # 直接询问ISO文件路径
    print_info "请输入或选择ISO文件:"
    echo -e "  ${GREEN}[1]${NC} 手动输入完整路径"
    echo -e "  ${GREEN}[2]${NC} 浏览文件选择 (在HOME目录中搜索)"
    echo ""
    print_question "请选择 [1 或 2]:"
    read -p "> " iso_method
    echo ""
    
    iso_file=""
    
    if [ "$iso_method" == "1" ]; then
        # 手动输入路径
        print_info "请输入ISO文件的完整路径:"
        read -p "> " iso_file
        iso_file="${iso_file/#\~/$HOME}"
        iso_file="$(echo "$iso_file" | xargs)"
        
        if [ ! -f "$iso_file" ]; then
            print_error "文件不存在: $iso_file"
            wait_for_exit 10
            exit 1
        fi
    elif [ "$iso_method" == "2" ]; then
        # 浏览选择
        while true; do
            print_info "搜索ISO文件..."
            echo ""
            local found_iso=()
            
            # 定义搜索路径 - 包括中英文常见位置
            local search_paths=(
                "$HOME/Downloads"
                "$HOME/下载"
                "$HOME/Documents"
                "$HOME/文档"
                "$HOME/Videos"
                "$HOME/视频"
                "$HOME/Pictures"
                "$HOME/图片"
                "$HOME/Music"
                "$HOME/音乐"
                "$HOME/Desktop"
                "$HOME/桌面"
                "$HOME/Public"
                "$HOME/公共"
                "$HOME/Templates"
                "$HOME/模板"
                "$HOME"
                "/home"
            )
            
            # 搜索所有指定路径中的ISO文件
            for search_path in "${search_paths[@]}"; do
                if [ -d "$search_path" ]; then
                    while IFS= read -r file; do
                        # 避免重复
                        if ! [[ " ${found_iso[@]} " =~ " ${file} " ]]; then
                            found_iso+=("$file")
                        fi
                    done < <(find "$search_path" -maxdepth 3 -type f \( -name "*.iso" -o -name "*.ISO" \) 2>/dev/null)
                fi
            done
            
            # 排序结果
            found_iso=($(printf '%s\n' "${found_iso[@]}" | sort))
            
            if [ ${#found_iso[@]} -eq 0 ]; then
                print_warning "未找到任何ISO文件"
                echo ""
                print_info "已搜索的目录:"
                echo "  • Downloads, 下载"
                echo "  • Documents, 文档"
                echo "  • Videos, 视频"
                echo "  • Pictures, 图片"
                echo "  • Music, 音乐"
                echo "  • Desktop, 桌面"
                echo "  • Public, 公共"
                echo "  • Templates, 模板"
                echo "  • /home 目录"
                echo ""
                print_question "是否手动输入ISO文件路径? (y/n):"
                read -p "> " retry_choice
                echo ""
                
                if [[ "$retry_choice" =~ ^[Yy]$ ]]; then
                    print_info "请输入ISO文件的完整路径:"
                    read -p "> " iso_file
                    iso_file="${iso_file/#\~/$HOME}"
                    iso_file="$(echo "$iso_file" | xargs)"
                    
                    if [ -f "$iso_file" ]; then
                        break
                    else
                        print_error "文件不存在: $iso_file"
                        echo ""
                        continue
                    fi
                else
                    print_error "未找到ISO文件且用户取消"
                    wait_for_exit 10
                    exit 1
                fi
            fi
            
            print_info "找到以下ISO文件:"
            for i in "${!found_iso[@]}"; do
                local file="${found_iso[$i]}"
                local file_size
                file_size=$(du -h "$file" 2>/dev/null | cut -f1 || echo "未知")
                echo -e "  ${GREEN}[$((i+1))]${NC} ${CYAN}${file}${NC} (${file_size})"
            done
            
            echo ""
            print_question "请选择ISO文件 [1-${#found_iso[@]}]:"
            read -p "> " iso_choice
            echo ""
            
            if [[ "$iso_choice" =~ ^[0-9]+$ ]] && [ "$iso_choice" -ge 1 ] && [ "$iso_choice" -le ${#found_iso[@]} ]; then
                iso_file="${found_iso[$((iso_choice-1))]}"
                break
            else
                print_error "无效的选择"
                echo ""
            fi
        done
    else
        print_error "无效的选择"
        wait_for_exit 10
        exit 1
    fi
    
    if [ -z "$iso_file" ] || [ ! -f "$iso_file" ]; then
        print_error "无法获取有效的ISO文件"
        wait_for_exit 10
        exit 1
    fi
    
    echo ""
    
    # 验证ISO文件
    if ! verify_iso "$iso_file"; then
        wait_for_exit 10
        exit 1
    fi
    
    echo ""
    
    # 使用dd写入ISO
    if write_iso_with_dd "$selected_device" "$iso_file"; then
        wait_for_exit 15
    else
        wait_for_exit 15
        exit 1
    fi
}

# 运行主函数
main "$@"