#!/bin/bash
# Auto Extract
# DESCRIPTION: 智能批量解压工具 - 支持所有压缩格式的递归解压
# REQUIRES_SUDO: false

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
PURPLE='\033[0;35m'
WHITE='\033[1;37m'
NC='\033[0m'

wait_for_exit() {
    local seconds=${1:-5}
    echo ""
    echo -e "${BLUE}[INFO]${NC} 脚本将在 ${seconds} 秒后自动退出..."
    sleep $seconds
    exit 0
}

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_progress() { echo -e "${CYAN}[进度]${NC} $1"; }
print_step() { echo -e "${CYAN}➜${NC} $1"; }
print_header() { echo -e "${WHITE}$1${NC}"; }

detect_system() {
    print_info "正在检测系统类型..."
    
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
    elif [ -f /etc/redhat-release ]; then
        OS="centos"
    elif [ -f /etc/debian_version ]; then
        OS="debian"
    else
        OS=$(uname -s)
    fi
    
    print_success "检测到系统: $OS"
}

detect_package_manager() {
    if command -v apt >/dev/null 2>&1; then
        PKG_MANAGER="apt"
    elif command -v apt-get >/dev/null 2>&1; then
        PKG_MANAGER="apt-get"
    elif command -v dnf >/dev/null 2>&1; then
        PKG_MANAGER="dnf"
    elif command -v yum >/dev/null 2>&1; then
        PKG_MANAGER="yum"
    elif command -v pacman >/dev/null 2>&1; then
        PKG_MANAGER="pacman"
    elif command -v zypper >/dev/null 2>&1; then
        PKG_MANAGER="zypper"
    elif command -v apk >/dev/null 2>&1; then
        PKG_MANAGER="apk"
    else
        PKG_MANAGER="none"
    fi
    
    print_info "检测到包管理器: $PKG_MANAGER"
}

install_dependencies() {
    print_info "检查必要的解压工具..."
    
    local missing_tools=()
    local missing_packages=()
    
    command -v unzip >/dev/null 2>&1 || missing_tools+=("unzip")
    command -v unrar >/dev/null 2>&1 || missing_tools+=("unrar")
    command -v 7z >/dev/null 2>&1 || missing_tools+=("7z")
    command -v tar >/dev/null 2>&1 || missing_tools+=("tar")
    command -v gunzip >/dev/null 2>&1 || missing_tools+=("gunzip")
    command -v bunzip2 >/dev/null 2>&1 || missing_tools+=("bunzip2")
    
    if [ ${#missing_tools[@]} -eq 0 ]; then
        print_success "所有必要工具已安装！"
        return 0
    fi
    
    print_warning "缺少以下工具: ${missing_tools[*]}"
    
    detect_package_manager
    
    if [ "$PKG_MANAGER" = "none" ]; then
        print_error "未检测到支持的包管理器！"
        print_warning "请手动安装以下工具："
        echo "  - unzip"
        echo "  - unrar"
        echo "  - p7zip-full"
        echo "  - tar"
        echo "  - gzip"
        echo "  - bzip2"
        echo ""
        read -p "是否继续使用已安装的工具? [y/N]: " continue_anyway
        if [ "$continue_anyway" != "y" ] && [ "$continue_anyway" != "Y" ]; then
            wait_for_exit 3
        fi
        return 0
    fi
    
    print_info "正在使用 $PKG_MANAGER 安装缺失的工具..."
    
    for tool in "${missing_tools[@]}"; do
        case "$tool" in
            unzip) missing_packages+=("unzip") ;;
            unrar) missing_packages+=("unrar") ;;
            7z) 
                case "$PKG_MANAGER" in
                    apt|apt-get) missing_packages+=("p7zip-full") ;;
                    dnf|yum) missing_packages+=("p7zip p7zip-plugins") ;;
                    pacman) missing_packages+=("p7zip") ;;
                    apk) missing_packages+=("p7zip") ;;
                    *) missing_packages+=("p7zip") ;;
                esac
                ;;
            tar) missing_packages+=("tar") ;;
            gunzip) missing_packages+=("gzip") ;;
            bunzip2) missing_packages+=("bzip2") ;;
        esac
    done
    
    case "$PKG_MANAGER" in
        apt|apt-get)
            sudo $PKG_MANAGER update -qq
            for pkg in "${missing_packages[@]}"; do
                sudo $PKG_MANAGER install -y $pkg 2>/dev/null || print_warning "无法安装 $pkg"
            done
            ;;
        dnf|yum)
            for pkg in "${missing_packages[@]}"; do
                sudo $PKG_MANAGER install -y $pkg 2>/dev/null || print_warning "无法安装 $pkg"
            done
            ;;
        pacman)
            for pkg in "${missing_packages[@]}"; do
                sudo pacman -S --noconfirm $pkg 2>/dev/null || print_warning "无法安装 $pkg"
            done
            ;;
        zypper)
            for pkg in "${missing_packages[@]}"; do
                sudo zypper install -y $pkg 2>/dev/null || print_warning "无法安装 $pkg"
            done
            ;;
        apk)
            sudo apk update
            for pkg in "${missing_packages[@]}"; do
                sudo apk add $pkg 2>/dev/null || print_warning "无法安装 $pkg"
            done
            ;;
    esac
    
    local still_missing=()
    for tool in "${missing_tools[@]}"; do
        if ! command -v $tool >/dev/null 2>&1; then
            still_missing+=("$tool")
        fi
    done
    
    if [ ${#still_missing[@]} -eq 0 ]; then
        print_success "所有依赖安装完成！"
    else
        print_warning "以下工具仍然缺失: ${still_missing[*]}"
        print_info "脚本将尝试使用已安装的工具继续..."
    fi
}

check_archive_structure() {
    local file="$1"
    local password="$2"
    local filename=$(basename "$file")
    local extension="${filename##*.}"
    
    case "$extension" in
        zip)
            if ! command -v unzip >/dev/null 2>&1; then
                echo "multi_root"
                return
            fi
            local contents=$(timeout 5s unzip -l "$file" 2>/dev/null | awk 'NR>3 {print $4}' | grep -v '^$' | head -20 || echo "")
            ;;
        rar)
            if ! command -v unrar >/dev/null 2>&1; then
                echo "multi_root"
                return
            fi
            if [ -n "$password" ]; then
                local contents=$(timeout 5s unrar lb -p"$password" "$file" 2>/dev/null | head -20 || echo "")
            else
                local contents=$(timeout 5s unrar lb "$file" 2>/dev/null | head -20 || echo "")
            fi
            ;;
        7z)
            echo "multi_root"
            return
            ;;
        tar|gz|tgz|bz2|tbz2|xz|txz)
            if [[ "$filename" == *.tar.gz ]] || [[ "$filename" == *.tgz ]]; then
                local contents=$(tar -tzf "$file" 2>/dev/null | head -20)
            elif [[ "$filename" == *.tar.bz2 ]] || [[ "$filename" == *.tbz2 ]]; then
                local contents=$(tar -tjf "$file" 2>/dev/null | head -20)
            elif [[ "$filename" == *.tar.xz ]] || [[ "$filename" == *.txz ]]; then
                local contents=$(tar -tJf "$file" 2>/dev/null | head -20)
            elif [[ "$filename" == *.tar ]]; then
                local contents=$(tar -tf "$file" 2>/dev/null | head -20)
            else
                echo "single"
                return
            fi
            ;;
        *)
            echo "single"
            return
            ;;
    esac
    
    if [ -z "$contents" ]; then
        echo "multi_root"
        return
    fi
    
    local top_level_items=$(echo "$contents" | cut -d'/' -f1 | sort -u | wc -l)
    local has_single_root=$(echo "$contents" | grep -c '/' 2>/dev/null | tr -d '\n' || echo "0")
    
    if [ "$top_level_items" -eq 1 ] && [ "$has_single_root" -gt 0 ] 2>/dev/null; then
        local root_dir=$(echo "$contents" | head -1 | cut -d'/' -f1)
        local all_in_root=$(echo "$contents" | grep -c "^$root_dir/" 2>/dev/null | tr -d '\n' || echo "0")
        local total_items=$(echo "$contents" | wc -l | tr -d '\n')
        
        if [ "$all_in_root" -eq "$total_items" ] 2>/dev/null; then
            echo "single_root"
            return
        fi
    fi
    
    echo "multi_root"
}

extract_file() {
    local file="$1"
    local password="$2"
    local current="$3"
    local total="$4"
    local filename=$(basename "$file")
    local extension="${filename##*.}"
    local basename="${filename%.*}"
    local file_dir="$(dirname "$file")"
    
    print_progress "[$current/$total] 正在处理: $filename"
    
    # 统一策略：总是创建同名文件夹
    local target_dir="$file_dir/$basename"
    mkdir -p "$target_dir"
    print_step "创建解压目录: $basename/"
    
    local extract_success=false
    
    case "$extension" in
        zip)
            if ! command -v unzip >/dev/null 2>&1; then
                print_error "  └─ 缺少 unzip 工具"
                return 1
            fi
            if [ -n "$password" ]; then
                unzip -q -P "$password" -o "$file" -d "$target_dir" 2>/dev/null && extract_success=true
            else
                unzip -q -o "$file" -d "$target_dir" 2>/dev/null && extract_success=true
            fi
            ;;
        rar)
            if ! command -v unrar >/dev/null 2>&1; then
                print_error "  └─ 缺少 unrar 工具"
                return 1
            fi
            print_step "正在解压 RAR 文件..."
            if [ -n "$password" ]; then
                timeout 120s unrar x -p"$password" -o+ -inul "$file" "$target_dir/" 2>/dev/null && extract_success=true
            else
                timeout 120s unrar x -o+ -inul "$file" "$target_dir/" 2>/dev/null && extract_success=true
            fi
            
            local exit_code=$?
            if [ $exit_code -eq 124 ]; then
                print_error "  └─ 解压超时（120秒）"
                print_warning "  └─ 文件可能损坏或过大，建议手动检查"
                return 1
            elif [ $exit_code -eq 3 ]; then
                print_error "  └─ 密码错误或文件已损坏"
                return 1
            elif [ $exit_code -eq 5 ]; then
                print_error "  └─ 无法写入目标目录"
                return 1
            fi
            ;;
        7z)
            if ! command -v 7z >/dev/null 2>&1; then
                print_error "  └─ 缺少 7z 工具"
                return 1
            fi
            print_step "正在解压 7z 文件..."
            if [ -n "$password" ]; then
                timeout 120s 7z x -p"$password" -o"$target_dir" -y "$file" >/dev/null 2>&1 && extract_success=true
            else
                timeout 120s 7z x -o"$target_dir" -y "$file" >/dev/null 2>&1 && extract_success=true
            fi
            
            if [ $? -eq 124 ]; then
                print_error "  └─ 解压超时（120秒）"
                return 1
            fi
            ;;
        tar)
            tar -xf "$file" -C "$target_dir" 2>/dev/null && extract_success=true
            ;;
        gz|tgz)
            if [[ "$filename" == *.tar.gz ]] || [[ "$filename" == *.tgz ]]; then
                tar -xzf "$file" -C "$target_dir" 2>/dev/null && extract_success=true
            else
                gunzip -c "$file" > "$target_dir/$(basename ${file%.gz})" 2>/dev/null && extract_success=true
            fi
            ;;
        bz2|tbz2)
            if [[ "$filename" == *.tar.bz2 ]] || [[ "$filename" == *.tbz2 ]]; then
                tar -xjf "$file" -C "$target_dir" 2>/dev/null && extract_success=true
            else
                bunzip2 -c "$file" > "$target_dir/$(basename ${file%.bz2})" 2>/dev/null && extract_success=true
            fi
            ;;
        xz|txz)
            if [[ "$filename" == *.tar.xz ]] || [[ "$filename" == *.txz ]]; then
                tar -xJf "$file" -C "$target_dir" 2>/dev/null && extract_success=true
            else
                xz -dc "$file" > "$target_dir/$(basename ${file%.xz})" 2>/dev/null && extract_success=true
            fi
            ;;
        *)
            print_warning "  └─ 不支持的格式"
            return 1
            ;;
    esac
    
    if [ "$extract_success" = true ]; then
        print_success "  └─ 解压成功！"
        print_step "删除原始压缩包: $filename"
        rm -f "$file"
        return 0
    else
        rmdir "$target_dir" 2>/dev/null
        print_error "  └─ 解压失败 (密码错误或文件损坏)"
        return 1
    fi
}

extract_all() {
    local search_dir="$1"
    local password="$2"
    
    print_info "开始搜索压缩文件: $search_dir"
    print_info "模式: 无限递归解压（直到没有新压缩包）"
    echo ""
    
    local total=0
    local success=0
    local failed=0
    local depth=0
    
    while true; do
        depth=$((depth + 1))
        echo ""
        print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        print_info "开始第 $depth 轮解压"
        print_header "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        
        local files=()
        while IFS= read -r -d '' file; do
            files+=("$file")
        done < <(find "$search_dir" -type f \( \
            -iname "*.zip" -o \
            -iname "*.rar" -o \
            -iname "*.7z" -o \
            -iname "*.tar" -o \
            -iname "*.tar.gz" -o \
            -iname "*.tgz" -o \
            -iname "*.tar.bz2" -o \
            -iname "*.tbz2" -o \
            -iname "*.tar.xz" -o \
            -iname "*.txz" -o \
            -iname "*.gz" -o \
            -iname "*.bz2" -o \
            -iname "*.xz" \
        \) -print0 2>/dev/null)
        
        local found=${#files[@]}
        
        if [ $found -eq 0 ]; then
            echo ""
            print_success "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            print_success "未发现更多压缩文件，解压完成！"
            print_success "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            break
        fi
        
        print_info "发现 $found 个压缩文件"
        echo ""
        
        local round_success=0
        local current=0
        
        for file in "${files[@]}"; do
            current=$((current + 1))
            total=$((total + 1))
            
            if extract_file "$file" "$password" "$current" "$found"; then
                success=$((success + 1))
                round_success=$((round_success + 1))
            else
                failed=$((failed + 1))
            fi
        done
        
        echo ""
        print_info "本轮统计: 成功 $round_success/$found"
        
        if [ $round_success -eq 0 ]; then
            print_warning "本轮没有成功解压任何文件，停止递归"
            break
        fi
    done
    
    echo ""
    echo ""
    print_success "╔════════════════════════════════════════╗"
    print_success "║          解压任务完成！                ║"
    print_success "╚════════════════════════════════════════╝"
    echo ""
    print_info "📊 统计信息："
    print_info "  总文件数: $total"
    print_success "  成功: $success"
    [ $failed -gt 0 ] && print_error "  失败: $failed"
    print_info "  解压轮数: $depth"
    echo ""
}

main() {
    echo ""
    print_header "======================================"
    print_header "   智能批量解压工具"
    print_header "======================================"
    echo ""
    
    detect_system
    install_dependencies
    
    echo ""
    
    if [ -n "$1" ]; then
        TARGET_DIR="$1"
    else
        read -p "请输入要解压的目录路径 (默认当前目录): " TARGET_DIR
        TARGET_DIR=${TARGET_DIR:-.}
    fi
    
    if [ ! -d "$TARGET_DIR" ]; then
        print_error "目录不存在: $TARGET_DIR"
        wait_for_exit 5
    fi
    
    TARGET_DIR=$(realpath "$TARGET_DIR")
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${YELLOW}⚠️  重要提示：密码设置${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "本脚本只支持使用【单一密码】批量解压"
    echo "如果压缩包有不同的密码，请分开解压！"
    echo -e "${RED}⚠️  解压成功后会自动删除原始压缩包！${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    read -p "请输入解压密码 (如无密码直接回车): " PASSWORD
    
    if [ -n "$PASSWORD" ]; then
        print_info "已设置密码: $PASSWORD"
    else
        print_info "未设置密码，将尝试无密码解压"
    fi
    
    echo ""
    print_warning "准备解压目录: $TARGET_DIR"
    read -p "是否开始解压? [y/N]: " confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_info "操作已取消"
        wait_for_exit 3
    fi
    
    extract_all "$TARGET_DIR" "$PASSWORD"
    
    print_success "所有操作完成！"
    wait_for_exit 10
}

main "$@"