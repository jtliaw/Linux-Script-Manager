#!/bin/bash
# pdf-portrait-helper.sh
# 描述: PDF 双向转换底层（横转纵 / 纵转横）
# 算法: 解析全局 cm 变换矩阵 + 内容坐标，精准裁剪白边，来回转换不缩水

set +e

HELPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PYTHON_CORE='
import sys, re
from pypdf import PdfWriter, PdfReader, Transformation
from pypdf.generic import ArrayObject

def get_bbox_with_transform(page):
    """
    解析内容流里的全局 cm 变换矩阵，把原始坐标映射到页面实际位置，
    综合文字(BT/ET) + 路径(m/l) + 图片(cm Do) 三类坐标，
    得到真实内容在当前页面上的边界框。
    """
    try:
        if "/Contents" not in page:
            return None
        contents = page["/Contents"]
        if hasattr(contents, "get_object"):
            contents = contents.get_object()
        if isinstance(contents, ArrayObject):
            raw = b"".join(obj.get_object().get_data() for obj in contents)
        else:
            raw = contents.get_data()
        text = raw.decode("latin-1", errors="ignore")

        pw = float(page.mediabox.width)
        ph = float(page.mediabox.height)

        # ── 读取全局 cm 变换（第一个 cm，通常是 merge_transformed_page 写入的） ──
        cms = re.findall(
            r"([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)\s+cm",
            text
        )
        global_scale = 1.0
        global_tx    = 0.0
        global_ty    = 0.0
        if cms:
            a, b, c, d, e, f = [float(x) for x in cms[0]]
            if b == 0 and c == 0:   # 纯缩放+平移，无旋转
                global_scale = abs(a)
                global_tx    = e
                global_ty    = f

        all_x, all_y = [], []

        # ── 文字坐标 (BT/ET) ──
        for block in re.findall(r"BT(.*?)ET", text, re.DOTALL):
            cx, cy = 0.0, 0.0
            for td in re.findall(r"([-\d.]+)\s+([-\d.]+)\s+Td", block):
                cx += float(td[0]); cy += float(td[1])
                all_x.append(cx);   all_y.append(cy)
            for tm in re.findall(
                r"([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)\s+Tm",
                block
            ):
                cx = float(tm[4]); cy = float(tm[5])
                all_x.append(cx);  all_y.append(cy)

        # ── 路径坐标 (m / l) ──
        for p in re.findall(r"([\d.]+)\s+([\d.]+)\s+[ml]\b", text):
            all_x.append(float(p[0])); all_y.append(float(p[1]))

        # ── 图片坐标（跳过第一个全局 cm，处理后续 cm） ──
        for m in cms[1:]:
            a2, b2, c2, d2, e2, f2 = [float(x) for x in m]
            sx2, sy2 = abs(a2), abs(d2)
            all_x.extend([e2, e2 + sx2])
            all_y.extend([f2, f2 + sy2])

        if not all_x or not all_y:
            return None

        # ── 把原始坐标用全局变换映射到页面坐标 ──
        tx_coords = [x * global_scale + global_tx for x in all_x]
        ty_coords = [y * global_scale + global_ty for y in all_y]

        fx = [x for x in tx_coords if -2 < x < pw + 2]
        fy = [y for y in ty_coords if -2 < y < ph + 2]
        if not fx or not fy:
            return None

        x0 = max(0, min(fx) - 5)
        y0 = max(0, min(fy) - 5)
        x1 = min(pw, max(fx) + 5)
        y1 = min(ph, max(fy) + 5)
        cov = ((x1 - x0) * (y1 - y0)) / (pw * ph)
        return (x0, y0, x1, y1, cov)

    except Exception:
        return None


def convert(input_path, output_path, TARGET_W, TARGET_H):
    reader = PdfReader(input_path)
    writer = PdfWriter()

    for page in reader.pages:
        pw = float(page.mediabox.width)
        ph = float(page.mediabox.height)

        result = get_bbox_with_transform(page)

        if result:
            x0, y0, x1, y1, cov = result
            content_w = x1 - x0
            content_h = y1 - y0

            if cov < 0.10:
                # 内容极稀少，保持整页比例缩放
                scale = min(TARGET_W / pw, TARGET_H / ph) * 0.97
                tx    = (TARGET_W - pw * scale) / 2
                ty    = (TARGET_H - ph * scale) / 2
            else:
                scale = min(TARGET_W / content_w, TARGET_H / content_h) * 0.97
                tx    = (TARGET_W - content_w * scale) / 2 - x0 * scale
                ty    = (TARGET_H - content_h * scale) / 2 - y0 * scale
        else:
            # 无法解析坐标，退回整页比例
            scale = min(TARGET_W / pw, TARGET_H / ph) * 0.97
            tx    = (TARGET_W - pw * scale) / 2
            ty    = (TARGET_H - ph * scale) / 2

        new_page = writer.add_blank_page(TARGET_W, TARGET_H)
        new_page.merge_transformed_page(
            page, Transformation().scale(scale).translate(tx, ty)
        )

    with open(output_path, "wb") as f:
        writer.write(f)


if __name__ == "__main__":
    input_path  = sys.argv[1]
    output_path = sys.argv[2]
    TARGET_W    = float(sys.argv[3])
    TARGET_H    = float(sys.argv[4])
    convert(input_path, output_path, TARGET_W, TARGET_H)
'

# ==========================================
# 核心功能：批量转换文件夹内所有 PDF
# ==========================================
cmd_convert() {
    local folder="$1"
    local mode="$2"

    if [ -z "$folder" ]; then folder="$(pwd)"; fi
    if [ -z "$mode"   ]; then mode="portrait";  fi

    if [ ! -d "$folder" ]; then
        echo "ERROR:路径不存在：$folder"
        exit 1
    fi

    echo "===CONVERT_START==="
    echo "FOLDER:${folder}"
    echo "MODE:${mode}"

    local total
    total=$(find "$folder" -maxdepth 1 -iname "*.pdf" | wc -l)
    echo "TOTAL:${total}"

    if [ "$total" -eq 0 ]; then
        echo "STATUS:NO_PDF"
        echo "===CONVERT_END==="
        exit 0
    fi

    if [ "$mode" == "landscape" ]; then
        local output_dir="${folder}/横向输出"
        local TARGET_W="841.890"
        local TARGET_H="595.276"
    else
        local output_dir="${folder}/纵向输出"
        local TARGET_W="595.276"
        local TARGET_H="841.890"
    fi

    mkdir -p "$output_dir"
    echo "OUTPUT_DIR:${output_dir}"

    find "$folder" -maxdepth 1 -iname "*.pdf" | sort | while read -r pdf_path; do
        local filename
        filename=$(basename "$pdf_path")
        local output_path="${output_dir}/${filename}"

        echo "$PYTHON_CORE" | python3 - "$pdf_path" "$output_path" "$TARGET_W" "$TARGET_H"

        if [ $? -eq 0 ]; then
            echo "OK:${filename}"
        else
            echo "FAIL:${filename}"
        fi
    done

    echo "STATUS:DONE"
    echo "===CONVERT_END==="
}

# ==========================================
# 单文件转换
# ==========================================
cmd_single() {
    local input_file="$1"
    local output_file="$2"
    local mode="${3:-portrait}"

    if [ -z "$output_file" ]; then
        local dir; dir=$(dirname "$input_file")
        local base; base=$(basename "$input_file" .pdf)
        if [ "$mode" == "landscape" ]; then
            output_file="${dir}/${base}_横向.pdf"
        else
            output_file="${dir}/${base}_纵向.pdf"
        fi
    fi

    if [ "$mode" == "landscape" ]; then
        TARGET_W="841.890"; TARGET_H="595.276"
    else
        TARGET_W="595.276"; TARGET_H="841.890"
    fi

    echo "===SINGLE_START==="
    echo "$PYTHON_CORE" | python3 - "$input_file" "$output_file" "$TARGET_W" "$TARGET_H"

    if [ $? -eq 0 ]; then
        echo "OK:${output_file}"
    else
        echo "FAIL:转换失败"
    fi
    echo "===SINGLE_END==="
}

case "$1" in
    convert) cmd_convert "$2" "$3" ;;
    single)  cmd_single  "$2" "$3" "$4" ;;
    *)       echo "Usage: $0 {convert <folder> [portrait|landscape] | single <input.pdf> [output.pdf] [portrait|landscape]}" ;;
esac
