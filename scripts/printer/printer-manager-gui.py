#!/usr/bin/env python3
# printer-manager-gui.py
import tkinter as tk
from tkinter import ttk, messagebox, simpledialog
import subprocess
import os
import threading

# ─── 🛠️ 完美的动态项目绝对路径对齐 ───
SCRIPT_DIR = os.path.dirname(os.path.realpath(__file__))
BASH_SCRIPT = os.path.join(SCRIPT_DIR, "printer-helper.sh")

# 精致深色主题色彩配置
THEME = {
    "bg":           "#1e1e2e",
    "bg_card":      "#2a2a3e",
    "accent":       "#89b4fa",
    "accent_hover": "#b4befe",
    "text":         "#cdd6f4",
    "text_dim":     "#6c7086",
    "danger":       "#f38ba8",
    "success":      "#a6e3a1",
    "warning":      "#f9e2af",
    "win_bg":       "#313244",
}

# 品牌关键词 → 建议安装的驱动包命令（驱动列表搜索为空时提示用户）
BRAND_DRIVER_HINTS = {
    "canon":   "sudo apt update && sudo apt install -y printer-driver-gutenprint\n"
               "# 若仍无对应型号，请前往 Canon 官网下载 cnijfilter2 驱动包",
    "epson":   "sudo apt update && sudo apt install -y epson-inkjet-printer-escpr epson-inkjet-printer-escpr2",
    "hp":      "sudo apt update && sudo apt install -y hplip hplip-gui",
    "hewlett": "sudo apt update && sudo apt install -y hplip hplip-gui",
    "brother": "sudo apt update && sudo apt install -y printer-driver-brlaser\n"
               "# 若仍无对应型号，请前往 Brother 官网下载对应型号驱动包",
    "samsung": "sudo apt update && sudo apt install -y printer-driver-splix",
    "lexmark": "sudo apt update && sudo apt install -y printer-driver-foomatic-filters printer-driver-gutenprint",
}
GENERIC_DRIVER_HINT = (
    "sudo apt update\n"
    "sudo apt install -y printer-driver-gutenprint printer-driver-all foomatic-db-compressed-ppds"
)


def guess_driver_install_cmd(keyword):
    """根据品牌关键词猜测应安装的驱动包命令；无匹配品牌时返回通用命令。"""
    kw = (keyword or "").lower().strip()
    for brand, cmd in BRAND_DRIVER_HINTS.items():
        if brand in kw:
            return cmd
    return GENERIC_DRIVER_HINT


# ══════════════════════════════════════════════════════════
# 驱动选择对话框：可搜索的 PPD 列表
# ══════════════════════════════════════════════════════════
class PPDPickerDialog(tk.Toplevel):
    """弹出一个可搜索的驱动选择窗口，返回用户选中的 PPD model 字符串。"""

    def __init__(self, parent, brand_hint="", auto_ppd=""):
        super().__init__(parent)
        self.title("选择打印机驱动")
        self.resizable(True, True)
        self.geometry("720x480")
        self.configure(bg=THEME["bg"])
        self.transient(parent)
        self.grab_set()

        self.result_ppd = None          # 最终选择的 PPD model
        self._all_entries = []          # [(ppd_model, label), ...]
        self._filtered = []
        self._loading = True            # 首次异步加载完成前为 True，避免误报"未安装驱动"

        # ── 顶部说明 ──────────────────────────────────────────────────
        info_text = (
            "未能自动匹配到对应驱动。\n"
            "请在下方列表中搜索并选择最接近您打印机型号的驱动。\n"
            f"自动推荐：{auto_ppd or '（无）'}"
        )
        tk.Label(self, text=info_text, bg=THEME["bg"], fg=THEME["warning"],
                 font=("Helvetica", 9), justify="left", anchor="w",
                 wraplength=680).pack(fill="x", padx=12, pady=(10, 4))

        # ── 搜索栏 ────────────────────────────────────────────────────
        search_frame = tk.Frame(self, bg=THEME["bg"])
        search_frame.pack(fill="x", padx=12, pady=4)
        tk.Label(search_frame, text="🔍 搜索型号：", bg=THEME["bg"],
                 fg=THEME["text"], font=("Helvetica", 10)).pack(side="left")
        self._search_var = tk.StringVar(value=brand_hint)
        search_entry = tk.Entry(search_frame, textvariable=self._search_var,
                                bg=THEME["bg_card"], fg=THEME["text"],
                                insertbackground=THEME["text"],
                                font=("Helvetica", 10), bd=0,
                                highlightthickness=1,
                                highlightbackground=THEME["accent"])
        search_entry.pack(side="left", fill="x", expand=True, padx=6)
        self._search_var.trace_add("write", lambda *_: self._filter())

        # ── 驱动列表 ──────────────────────────────────────────────────
        list_frame = tk.Frame(self, bg=THEME["bg"])
        list_frame.pack(fill="both", expand=True, padx=12, pady=4)

        cols = ("label", "model")
        self._tree = ttk.Treeview(list_frame, columns=cols,
                                  show="headings", height=14)
        self._tree.heading("label", text="驱动名称 / 型号")
        self._tree.heading("model", text="PPD 内部标识")
        self._tree.column("label", width=420, anchor="w")
        self._tree.column("model", width=240, anchor="w")
        sb = ttk.Scrollbar(list_frame, orient="vertical",
                           command=self._tree.yview)
        self._tree.configure(yscrollcommand=sb.set)
        self._tree.pack(side="left", fill="both", expand=True)
        sb.pack(side="right", fill="y")
        self._tree.bind("<Double-1>", lambda e: self._confirm())

        # ── 空结果提示区（未安装驱动包时显示，默认隐藏）──────────────────
        self._hint_frame = tk.Frame(self, bg=THEME["bg_card"])
        self._hint_lbl = tk.Label(
            self._hint_frame,
            text="⚠️ 未找到匹配的驱动，本机可能尚未安装对应的驱动包。",
            bg=THEME["bg_card"], fg=THEME["warning"],
            font=("Helvetica", 9, "bold"), justify="left", anchor="w",
            wraplength=680)
        self._hint_lbl.pack(fill="x", padx=8, pady=(6, 2))
        self._hint_cmd_lbl = tk.Label(
            self._hint_frame, text="", bg="#11111b", fg=THEME["success"],
            font=("Consolas", 9), justify="left", anchor="w",
            wraplength=680)
        self._hint_cmd_lbl.pack(fill="x", padx=8, pady=(0, 4))
        tk.Button(self._hint_frame, text="📋 复制安装命令",
                  bg=THEME["accent"], fg="#11111b",
                  font=("Helvetica", 9, "bold"), bd=0, padx=8, pady=3,
                  command=self._copy_install_cmd).pack(anchor="e", padx=8, pady=(0, 6))
        # 注意：此处不 pack，_populate() 会在结果为空时动态显示/隐藏

        # ── 底部按钮 ──────────────────────────────────────────────────
        self._btn_frame = tk.Frame(self, bg=THEME["bg"])
        self._btn_frame.pack(fill="x", padx=12, pady=8)

        # 「使用自动推荐」按钮（如果有）
        if auto_ppd:
            tk.Button(self._btn_frame,
                      text=f"✅ 使用自动推荐驱动",
                      bg=THEME["success"], fg="#11111b",
                      font=("Helvetica", 10, "bold"),
                      bd=0, padx=10, pady=5,
                      command=lambda: self._use_auto(auto_ppd)
                      ).pack(side="left", padx=4)

        tk.Button(self._btn_frame, text="❌ 跳过（RAW模式）",
                  bg=THEME["bg_card"], fg=THEME["text_dim"],
                  font=("Helvetica", 9), bd=0, padx=10, pady=5,
                  command=self._skip).pack(side="right", padx=4)
        tk.Button(self._btn_frame, text="确认选择",
                  bg=THEME["accent"], fg="#11111b",
                  font=("Helvetica", 10, "bold"),
                  bd=0, padx=14, pady=5,
                  command=self._confirm).pack(side="right", padx=4)

        # ── 加载 PPD 列表（异步，避免冻结窗口）──────────────────────
        self._count_lbl = tk.Label(self, text="正在加载驱动列表...",
                                   bg=THEME["bg"], fg=THEME["text_dim"],
                                   font=("Helvetica", 8))
        self._count_lbl.pack(pady=(0, 4))
        threading.Thread(target=self._load_ppds,
                         args=(brand_hint,), daemon=True).start()

        search_entry.focus_set()
        self.wait_window(self)

    # ── 内部方法 ──────────────────────────────────────────────────────
    def _load_ppds(self, keyword):
        entries = []
        try:
            res = subprocess.run(
                [BASH_SCRIPT, "listppd", keyword],
                stdout=subprocess.PIPE, text=True, timeout=30)
            inside = False
            for line in res.stdout.splitlines():
                line = line.strip()
                if line == "===PPD_START===":
                    inside = True; continue
                if line == "===PPD_END===":
                    inside = False; continue
                if inside and line.startswith("PPD:"):
                    parts = line.split("|", 1)
                    model = parts[0][len("PPD:"):]
                    label = parts[1][len("LABEL:"):] if len(parts) > 1 else model
                    entries.append((model, label))
        except Exception:
            pass
        self._all_entries = entries
        self._loading = False
        self.after(0, self._populate, entries)

    def _populate(self, entries):
        self._tree.delete(*self._tree.get_children())
        for model, label in entries:
            self._tree.insert("", "end", values=(label, model))
        count = len(entries)
        self._filtered = entries

        if count == 0 and self._loading:
            # 首次结果尚未返回，先显示加载中，不急着提示"未安装驱动"
            self._count_lbl.config(text="正在加载驱动列表...", fg=THEME["text_dim"])
            return

        if count == 0:
            kw = self._search_var.get().strip()
            cmd = guess_driver_install_cmd(kw)
            self._count_lbl.config(
                text=f"⚠️ 未找到匹配 “{kw or '（空）'}” 的驱动，共 0 个结果",
                fg=THEME["danger"])
            self._hint_lbl.config(
                text=(f"⚠️ 未找到匹配 “{kw or '（空）'}” 的驱动，本机可能尚未安装对应的驱动包。\n"
                      "请打开终端执行下方命令安装驱动，安装完成后重新搜索或重新扫描添加打印机："))
            self._hint_cmd_lbl.config(text=cmd)
            if not self._hint_frame.winfo_ismapped():
                self._hint_frame.pack(fill="x", padx=12, pady=(0, 4),
                                      before=self._btn_frame)
        else:
            self._count_lbl.config(
                text=f"共 {count} 个驱动  |  双击或选中后点「确认选择」",
                fg=THEME["text_dim"])
            if self._hint_frame.winfo_ismapped():
                self._hint_frame.pack_forget()

    def _filter(self):
        kw = self._search_var.get().lower().strip()
        if not kw:
            filtered = self._all_entries
        else:
            # 支持多关键词空格分隔（如 "canon g2000"）
            keywords = kw.split()
            filtered = [
                (m, l) for m, l in self._all_entries
                if all(k in l.lower() or k in m.lower() for k in keywords)
            ]
        self._populate(filtered)

    def _confirm(self):
        sel = self._tree.selection()
        if not sel:
            messagebox.showwarning("提示", "请先选择一个驱动。", parent=self)
            return
        vals = self._tree.item(sel[0])["values"]
        self.result_ppd = str(vals[1])   # PPD model 列
        self.destroy()

    def _use_auto(self, ppd):
        self.result_ppd = ppd
        self.destroy()

    def _skip(self):
        self.result_ppd = "raw"
        self.destroy()

    def _copy_install_cmd(self):
        """把建议的安装命令复制到剪贴板，方便用户直接粘贴到终端执行。"""
        cmd = self._hint_cmd_lbl.cget("text")
        if not cmd:
            return
        try:
            self.clipboard_clear()
            self.clipboard_append(cmd)
            messagebox.showinfo(
                "已复制",
                "安装命令已复制到剪贴板。\n请打开终端粘贴执行，安装完成后重新搜索/扫描。",
                parent=self)
        except Exception:
            messagebox.showwarning(
                "复制失败",
                f"无法访问剪贴板，请手动复制以下命令：\n\n{cmd}",
                parent=self)


class PrinterManagerApp:
    def __init__(self, root):
        self.root = root
        self.root.title("Linux 智能打印机一键神医与管理器")
        self.root.geometry("820x540")
        self.root.configure(bg=THEME["bg"])
        self.root.resizable(False, False)

        # 统一设置 Treeview 样式
        style = ttk.Style()
        style.theme_use("clam")
        style.configure("Treeview",
                        background=THEME["bg_card"],
                        fieldbackground=THEME["bg_card"],
                        foreground=THEME["text"],
                        rowheight=26)
        style.map("Treeview",
                  background=[("selected", THEME["accent"])],
                  foreground=[("selected", "#11111b")])
        # 标签页样式
        style.configure("TNotebook", background=THEME["bg"], borderwidth=0)
        style.configure("TNotebook.Tab",
                        background=THEME["bg_card"],
                        foreground=THEME["text_dim"],
                        padding=[12, 5])
        style.map("TNotebook.Tab",
                  background=[("selected", THEME["accent"])],
                  foreground=[("selected", "#11111b")])

        self.printer_data = []
        self._data_lock = threading.Lock()
        self._active_threads = 0

        self.create_widgets()
        self.root.protocol("WM_DELETE_WINDOW", self._on_closing)

    # ─────────────────────────────────────────────
    # 界面构建
    # ─────────────────────────────────────────────
    def create_widgets(self):
        # 标题栏
        tk.Label(self.root, text="🖨️ Linux 智能打印机助手",
                 font=("Helvetica", 14, "bold"),
                 bg=THEME["bg"], fg=THEME["accent"]).pack(pady=(10, 4))

        # 全局状态栏
        self.status_lbl = tk.Label(self.root,
                                   text="就绪。请选择标签页开始操作...",
                                   font=("Helvetica", 9),
                                   bg=THEME["bg"], fg=THEME["text_dim"])
        self.status_lbl.pack(fill="x", padx=20, pady=(0, 4), anchor="w")

        # ── Notebook 标签页 ──────────────────────
        nb = ttk.Notebook(self.root)
        nb.pack(fill="both", expand=True, padx=12, pady=(0, 10))

        # Tab 1：搜索并添加打印机
        tab_scan = tk.Frame(nb, bg=THEME["bg"])
        nb.add(tab_scan, text="  🔍 搜索 & 添加  ")

        # Tab 2：已安装打印机管理
        tab_installed = tk.Frame(nb, bg=THEME["bg"])
        nb.add(tab_installed, text="  🗂️ 已安装打印机  ")

        # Tab 3：CUPS 任务监控
        tab_jobs = tk.Frame(nb, bg=THEME["bg"])
        nb.add(tab_jobs, text="  📋 打印任务监控  ")

        self._build_scan_tab(tab_scan)
        self._build_installed_tab(tab_installed)
        self._build_jobs_tab(tab_jobs)

    # ══════════════════════════════════════════════
    # Tab 1：搜索 & 添加
    # ══════════════════════════════════════════════
    def _build_scan_tab(self, parent):
        # 按钮栏
        btn_frame = tk.Frame(parent, bg=THEME["bg"])
        btn_frame.pack(fill="x", padx=10, pady=6)

        self.scan_btn = tk.Button(
            btn_frame, text="🔍 智能搜索全网/USB打印机",
            font=("Helvetica", 10),
            bg=THEME["accent"], fg="#11111b",
            activebackground=THEME["accent_hover"],
            bd=0, cursor="hand2", padx=12, pady=5,
            command=self.start_scan_thread)
        self.scan_btn.pack(side="left", padx=5)

        self.clear_btn = tk.Button(
            btn_frame, text="💥 强力取消任务并重置CUPS",
            font=("Helvetica", 10, "bold"),
            bg=THEME["danger"], fg="#11111b",
            activebackground="#f5e0dc",
            bd=0, cursor="hand2", padx=12, pady=5,
            command=self.start_clear_thread)
        self.clear_btn.pack(side="right", padx=5)

        # ── 进度区域（扫描时显示，平时隐藏）────────────────────────────
        self._progress_frame = tk.Frame(parent, bg=THEME["bg_card"],
                                        relief="flat", bd=0)
        # 阶段标签 + 计数
        prog_top = tk.Frame(self._progress_frame, bg=THEME["bg_card"])
        prog_top.pack(fill="x", padx=8, pady=(6, 2))
        self._phase_lbl = tk.Label(prog_top, text="",
                                   font=("Helvetica", 9),
                                   bg=THEME["bg_card"], fg=THEME["accent"],
                                   anchor="w")
        self._phase_lbl.pack(side="left")
        self._found_lbl = tk.Label(prog_top, text="",
                                   font=("Helvetica", 9, "bold"),
                                   bg=THEME["bg_card"], fg=THEME["success"],
                                   anchor="e")
        self._found_lbl.pack(side="right")
        # 进度条
        style = ttk.Style()
        style.configure("Scan.Horizontal.TProgressbar",
                        troughcolor=THEME["bg"],
                        background=THEME["accent"],
                        thickness=10)
        self._progress_bar = ttk.Progressbar(
            self._progress_frame,
            style="Scan.Horizontal.TProgressbar",
            orient="horizontal", mode="determinate", maximum=100)
        self._progress_bar.pack(fill="x", padx=8, pady=(0, 6))
        # 初始隐藏
        self._progress_frame.pack_forget()

        # 列表
        list_frame = tk.Frame(parent, bg=THEME["bg"])
        list_frame.pack(fill="both", expand=True, padx=10, pady=4)

        columns = ("kind", "name", "uri", "info")
        self.scan_tree = ttk.Treeview(list_frame, columns=columns,
                                      show="headings", height=9)
        self.scan_tree.heading("kind", text="打印机类型")
        self.scan_tree.heading("name", text="推荐别名")
        self.scan_tree.heading("uri",  text="局域网物理路径 (URI)")
        self.scan_tree.heading("info", text="设备描述")
        self.scan_tree.column("kind", width=90,  anchor="center")
        self.scan_tree.column("name", width=120, anchor="w")
        self.scan_tree.column("uri",  width=250, anchor="w")
        self.scan_tree.column("info", width=240, anchor="w")

        sb = ttk.Scrollbar(list_frame, orient="vertical",
                           command=self.scan_tree.yview)
        self.scan_tree.configure(yscrollcommand=sb.set)
        self.scan_tree.pack(side="left", fill="both", expand=True)
        sb.pack(side="right", fill="y")
        self.scan_tree.bind("<Double-1>", self.on_scan_double_click)

        # 安装按钮
        self.add_btn = tk.Button(
            parent,
            text="⚡ 一键自动安装选中的打印机 (支持双击选择)",
            font=("Helvetica", 11, "bold"),
            bg=THEME["success"], fg="#11111b",
            activebackground="#b4befe",
            bd=0, cursor="hand2", pady=7,
            command=self.install_selected_printer)
        self.add_btn.pack(fill="x", padx=10, pady=6)

    # ══════════════════════════════════════════════
    # Tab 2：已安装打印机管理
    # ══════════════════════════════════════════════
    def _build_installed_tab(self, parent):
        btn_frame = tk.Frame(parent, bg=THEME["bg"])
        btn_frame.pack(fill="x", padx=10, pady=6)

        self.refresh_installed_btn = tk.Button(
            btn_frame, text="🔄 刷新已安装打印机列表",
            font=("Helvetica", 10),
            bg=THEME["accent"], fg="#11111b",
            activebackground=THEME["accent_hover"],
            bd=0, cursor="hand2", padx=12, pady=5,
            command=self.start_list_installed_thread)
        self.refresh_installed_btn.pack(side="left", padx=5)

        self.set_default_btn = tk.Button(
            btn_frame, text="⭐ 设为默认打印机",
            font=("Helvetica", 10, "bold"),
            bg=THEME["warning"], fg="#11111b",
            activebackground="#f5e0dc",
            bd=0, cursor="hand2", padx=12, pady=5,
            command=self.set_selected_as_default)
        self.set_default_btn.pack(side="left", padx=5)

        self.delete_btn = tk.Button(
            btn_frame, text="🗑️ 删除选中的打印机",
            font=("Helvetica", 10, "bold"),
            bg=THEME["danger"], fg="#11111b",
            activebackground="#f5e0dc",
            bd=0, cursor="hand2", padx=12, pady=5,
            command=self.delete_selected_printer)
        self.delete_btn.pack(side="right", padx=5)

        list_frame = tk.Frame(parent, bg=THEME["bg"])
        list_frame.pack(fill="both", expand=True, padx=10, pady=4)

        cols = ("default", "name", "uri", "state", "jobs")
        self.installed_tree = ttk.Treeview(list_frame, columns=cols,
                                           show="headings", height=10)
        self.installed_tree.heading("default", text="默认")
        self.installed_tree.heading("name",    text="打印机名称")
        self.installed_tree.heading("uri",     text="设备 URI")
        self.installed_tree.heading("state",   text="状态")
        self.installed_tree.heading("jobs",    text="待处理任务")
        self.installed_tree.column("default", width=52,  anchor="center")
        self.installed_tree.column("name",    width=150, anchor="w")
        self.installed_tree.column("uri",     width=290, anchor="w")
        self.installed_tree.column("state",   width=80,  anchor="center")
        self.installed_tree.column("jobs",    width=80,  anchor="center")

        # 默认打印机行高亮样式
        self.installed_tree.tag_configure(
            "default_tag",
            background="#2d3f2d",
            foreground=THEME["success"])

        sb2 = ttk.Scrollbar(list_frame, orient="vertical",
                            command=self.installed_tree.yview)
        self.installed_tree.configure(yscrollcommand=sb2.set)
        self.installed_tree.pack(side="left", fill="both", expand=True)
        sb2.pack(side="right", fill="y")

        # 提示
        tk.Label(parent,
                 text="⭐ 绿色行为当前默认打印机 | 选中后可设为默认或删除（需提权）",
                 font=("Helvetica", 8),
                 bg=THEME["bg"], fg=THEME["text_dim"]).pack(pady=(0, 4))

    # ══════════════════════════════════════════════
    # Tab 3：CUPS 打印任务监控
    # ══════════════════════════════════════════════
    def _build_jobs_tab(self, parent):
        btn_frame = tk.Frame(parent, bg=THEME["bg"])
        btn_frame.pack(fill="x", padx=10, pady=6)

        self.refresh_jobs_btn = tk.Button(
            btn_frame, text="🔄 刷新任务列表",
            font=("Helvetica", 10),
            bg=THEME["accent"], fg="#11111b",
            activebackground=THEME["accent_hover"],
            bd=0, cursor="hand2", padx=12, pady=5,
            command=self.start_list_jobs_thread)
        self.refresh_jobs_btn.pack(side="left", padx=5)

        self.cancel_job_btn = tk.Button(
            btn_frame, text="❌ 取消选中任务",
            font=("Helvetica", 10, "bold"),
            bg=THEME["warning"], fg="#11111b",
            activebackground="#f5e0dc",
            bd=0, cursor="hand2", padx=12, pady=5,
            command=self.cancel_selected_job)
        self.cancel_job_btn.pack(side="left", padx=5)

        self.cancel_all_jobs_btn = tk.Button(
            btn_frame, text="💥 清除所有任务",
            font=("Helvetica", 10, "bold"),
            bg=THEME["danger"], fg="#11111b",
            activebackground="#f5e0dc",
            bd=0, cursor="hand2", padx=12, pady=5,
            command=self.cancel_all_jobs)
        self.cancel_all_jobs_btn.pack(side="left", padx=5)

        list_frame = tk.Frame(parent, bg=THEME["bg"])
        list_frame.pack(fill="both", expand=True, padx=10, pady=4)

        cols = ("job_id", "printer", "owner", "size", "when", "stuck")
        self.jobs_tree = ttk.Treeview(list_frame, columns=cols,
                                      show="headings", height=10)
        self.jobs_tree.heading("job_id",  text="任务 ID")
        self.jobs_tree.heading("printer", text="所属打印机")
        self.jobs_tree.heading("owner",   text="提交用户")
        self.jobs_tree.heading("size",    text="大小")
        self.jobs_tree.heading("when",    text="提交时间")
        self.jobs_tree.heading("stuck",   text="是否卡住")
        self.jobs_tree.column("job_id",  width=130, anchor="w")
        self.jobs_tree.column("printer", width=150, anchor="w")
        self.jobs_tree.column("owner",   width=90,  anchor="center")
        self.jobs_tree.column("size",    width=80,  anchor="center")
        self.jobs_tree.column("when",    width=140, anchor="center")
        self.jobs_tree.column("stuck",   width=80,  anchor="center")

        sb3 = ttk.Scrollbar(list_frame, orient="vertical",
                            command=self.jobs_tree.yview)
        self.jobs_tree.configure(yscrollcommand=sb3.set)
        self.jobs_tree.pack(side="left", fill="both", expand=True)
        sb3.pack(side="right", fill="y")

        tk.Label(parent,
                 text="⚠️ 橙色行：任务滞留 >30 分钟，疑似卡住；建议取消后重打",
                 font=("Helvetica", 8),
                 bg=THEME["bg"], fg=THEME["warning"]).pack(pady=(0, 4))

        # 为卡住的任务配置高亮 tag
        self.jobs_tree.tag_configure("stuck_tag",
                                     background="#45403d",
                                     foreground=THEME["warning"])

    # ─────────────────────────────────────────────
    # 工具函数
    # ─────────────────────────────────────────────
    def _parse_field(self, field_str, prefix_len):
        return field_str[prefix_len:]

    def _set_status(self, text, color=None):
        self.status_lbl.config(text=text,
                               fg=color if color else THEME["text_dim"])

    # ══════════════════════════════════════════════
    # Tab 1 逻辑：扫描 & 添加
    # ══════════════════════════════════════════════
    def start_scan_thread(self):
        self.scan_btn.config(state="disabled", text="⏳ 正在扫描...")
        self._set_status("扫描启动中...", THEME["accent"])
        self.scan_tree.delete(*self.scan_tree.get_children())
        with self._data_lock:
            self.printer_data.clear()
        # 显示进度区域
        self._progress_frame.pack(fill="x", padx=10, pady=(0, 4))
        self._progress_bar["value"] = 0
        self._phase_lbl.config(text="⏳ 初始化扫描引擎...")
        self._found_lbl.config(text="已发现：0 台")
        self._active_threads += 1
        threading.Thread(target=self.run_scan, daemon=True).start()

    def _add_printer_to_ui(self, p):
        """实时把单台发现的设备插入列表（可从子线程通过 root.after 调用）"""
        if p["kind"] == "USB":
            kind_show = "🔌 USB直连"
        elif p["kind"] == "LINUX":
            kind_show = "🐧 Linux/IPP"
        elif "SCAN_PLACEHOLDER" in p["uri"] or "ManualEntry" in p["uri"]:
            kind_show = "🪟 Win(需确认)"
        else:
            kind_show = "🪟 Win(已发现)"
        self.scan_tree.insert("", "end",
                              values=(kind_show, p["name"],
                                      p["uri"], p["info"]))
        count = len(self.scan_tree.get_children())
        self._found_lbl.config(text=f"已发现：{count} 台")

    def _update_progress(self, value, phase_text):
        """更新进度条和阶段文字（从子线程通过 root.after 调用）"""
        self._progress_bar["value"] = value
        self._phase_lbl.config(text=phase_text)

    def run_scan(self):
        try:
            # 阶段进度映射（根据 shell 脚本输出的 DEBUG 行判断阶段）
            # 进度区间：USB=0-15, IPP=15-25, Avahi=25-40, nmblookup=40-55, 网段扫描=55-95
            PHASE_MAP = {
                "SCAN_START":   (2,  "⏳ 正在扫描本地 USB 打印机..."),
                "KIND:USB":     (10, "🔌 发现 USB 打印机，继续扫描..."),
                "KIND:LINUX":   (22, "🐧 发现 IPP 网络打印机，继续扫描..."),
                "avahi":        (35, "🔍 正在用 Avahi/mDNS 发现局域网主机..."),
                "nmblookup":    (50, "📡 正在用 NetBIOS 广播发现 Windows 主机..."),
                "网段直扫":     (58, "🌐 正在扫描 192.168.x.x 网段（最多约30秒）..."),
                "KIND:WINDOWS": (80, "🪟 发现 Windows 共享打印机！"),
                "SCAN_END":     (100,"✅ 扫描完成！"),
            }
            # 网段扫描的伪进度：从58到93之间每隔1秒递增，模拟进度
            self._subnet_scan_active = False
            self._subnet_progress = 58

            def _tick_subnet_progress():
                """每1.2秒推进一格，让进度条在网段扫描阶段动起来"""
                if not self._subnet_scan_active:
                    return
                if self._subnet_progress < 93:
                    self._subnet_progress += 1
                    self._progress_bar["value"] = self._subnet_progress
                self.root.after(1200, _tick_subnet_progress)

            process = subprocess.Popen(
                [BASH_SCRIPT, "scan"],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            local_buf = []
            inside_block = False

            for line in process.stdout:
                line = line.strip()
                if not line:
                    continue

                if line == "===SCAN_START===":
                    inside_block = True
                    self.root.after(0, self._update_progress, 5,
                                    "⏳ 正在扫描 USB 和 IPP 打印机...")
                    continue

                if line == "===SCAN_END===":
                    inside_block = False
                    self._subnet_scan_active = False
                    self.root.after(0, self._update_progress, 100, "✅ 扫描完成！")
                    continue

                # 阶段检测（使用 shell 脚本输出的 SCAN_PHASE 标记行）
                if line.startswith("SCAN_PHASE:"):
                    phase = line[len("SCAN_PHASE:"):]
                    if phase == "AVAHI":
                        self.root.after(0, self._update_progress, 30,
                                        "🔍 Avahi/mDNS 正在发现局域网主机...")
                    elif phase == "NMBLOOKUP":
                        self.root.after(0, self._update_progress, 48,
                                        "📡 NetBIOS 广播正在探测 Windows 主机...")
                    elif phase.startswith("SUBNET:"):
                        subnet_info = phase[len("SUBNET:"):]
                        if not self._subnet_scan_active:
                            self._subnet_scan_active = True
                            self._subnet_progress = 58
                            self.root.after(0, self._update_progress, 58,
                                            f"🌐 正在逐一探测 {subnet_info} 网段（约20-30秒）...")
                            self.root.after(1200, _tick_subnet_progress)
                    continue

                if not inside_block:
                    continue

                if line.startswith("KIND:"):
                    parts = line.split("|")
                    if len(parts) < 4:
                        continue
                    kind  = self._parse_field(parts[0], len("KIND:"))
                    uri   = self._parse_field(parts[1], len("URI:"))
                    name  = self._parse_field(parts[2], len("NAME:"))
                    info  = self._parse_field(parts[3], len("INFO:"))
                    # 解析新增的 BRAND 和 MODEL 字段（第5、6个）
                    brand = ""
                    model = ""
                    for extra in parts[4:]:
                        if extra.startswith("BRAND:"):
                            brand = extra[len("BRAND:"):]
                        elif extra.startswith("MODEL:"):
                            model = extra[len("MODEL:"):]
                    p = {"kind": kind, "uri": uri, "name": name,
                         "info": info, "brand": brand, "model": model}
                    local_buf.append(p)

                    # 根据类型更新进度，显示识别到的品牌型号
                    display = f"{brand} {model}".strip() or name
                    if kind == "USB":
                        self.root.after(0, self._update_progress, 15,
                                        f"🔌 发现 USB 打印机：{display}")
                    elif kind == "LINUX":
                        self.root.after(0, self._update_progress, 25,
                                        f"🐧 发现 IPP 打印机：{display}")
                    elif kind == "WINDOWS":
                        self._subnet_scan_active = False
                        self.root.after(0, self._update_progress, 88,
                                        f"🪟 发现 Windows 打印机：{display}")

                    # 实时插入列表
                    p_copy = dict(p)
                    self.root.after(0, self._add_printer_to_ui, p_copy)

            process.wait()
            with self._data_lock:
                self.printer_data.extend(local_buf)
            self.root.after(0, self.update_scan_table_ui, "SUCCESS")

        except Exception as e:
            self.root.after(0, self.update_scan_table_ui, f"ERROR: {e}")
        finally:
            self._subnet_scan_active = False
            self._active_threads -= 1

    def update_scan_table_ui(self, status):
        self.scan_btn.config(state="normal", text="🔍 智能搜索全网/USB打印机")
        # 隐藏进度条
        self._progress_frame.pack_forget()
        if "ERROR" in status:
            self._set_status(f"扫描失败: {status}", THEME["danger"])
            return
        count = len(self.printer_data)
        if count == 0:
            self._set_status("扫描完成，未发现任何打印机。请检查网络或手动添加。",
                             THEME["warning"])
        else:
            self._set_status(
                f"✅ 扫描完成！共发现 {count} 台设备。双击或点击下方按钮安装。",
                THEME["success"])

    def start_clear_thread(self):
        if messagebox.askyesno(
                "警告",
                "您是否确认启动【强力重置】？\n这将清空全系统所有打印任务，并重置CUPS后台服务。"):
            self._set_status("正在强制剿灭打印任务死锁并清洗CUPS缓存...",
                             THEME["danger"])
            self._active_threads += 1
            threading.Thread(target=self.run_clear, daemon=True).start()

    def run_clear(self):
        try:
            process = subprocess.Popen(
                ["pkexec", BASH_SCRIPT, "clear"],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            task_count = 0
            for line in process.stdout:
                line = line.strip()
                if line.startswith("TASK_COUNT:"):
                    task_count = line.split(":")[1]
            process.wait()
            self.root.after(0, self.show_clear_report, task_count)
        except Exception as e:
            self.root.after(0, lambda: messagebox.showerror(
                "错误", f"提权或执行清理失败:\n{e}"))
        finally:
            self._active_threads -= 1

    def show_clear_report(self, count):
        self._set_status("系统 CUPS 后台已成功清洗并满血复活！", THEME["success"])
        messagebox.showinfo("神医体检报告",
                            f"【清道夫任务完成】\n\n"
                            f"检测到当前后台积压死锁任务: {count} 个\n"
                            f"已全部强力抹除完毕！\nCUPS 后台服务已成功优雅重启。")

    def _preview_auto_ppd_by_brand_model(self, brand, model):
        """根据品牌+型号查找最佳 PPD，返回 PPD model 字符串或空。"""
        if not brand and not model:
            return ""
        # 别名映射（与 shell 保持一致）
        ALIAS = {
            "g2010": ["g2000"], "g3010": ["g3000"], "g4010": ["g4000"],
            "g2012": ["g2000"], "g3012": ["g3000"],
            "g2020": ["g2010", "g2000"], "g3020": ["g3010", "g3000"],
            "g2060": ["g2000"], "g3060": ["g3000"],
            "l3210": ["l3200", "l3150"], "l3211": ["l3200", "l3150"],
            "l3250": ["l3200", "l3150"], "l3260": ["l3200", "l3150"],
            "l3110": ["l3100"], "l5190": ["l5180"], "l6170": ["l6160"],
        }
        import re
        model_key = model.lower().replace(" ", "").replace("-", "")
        brand_lower = brand.lower()
        try:
            res = subprocess.run(
                [BASH_SCRIPT, "listppd", brand_lower],
                stdout=subprocess.PIPE, text=True, timeout=20)
            entries = []
            inside = False
            for line in res.stdout.splitlines():
                line = line.strip()
                if line == "===PPD_START===": inside = True; continue
                if line == "===PPD_END===": break
                if inside and line.startswith("PPD:"):
                    parts = line.split("|", 1)
                    ppd_m = parts[0][4:]
                    lbl   = parts[1][6:] if len(parts) > 1 else ppd_m
                    entries.append((ppd_m, lbl))

            def _search(keyword):
                kw = keyword.lower()
                # gutenprint 优先
                for m2, l in entries:
                    if kw in m2.lower() or kw in l.lower():
                        if "gutenprint" in m2.lower() or "gutenprint" in l.lower():
                            return m2
                for m2, l in entries:
                    if kw in m2.lower() or kw in l.lower():
                        return m2
                return ""

            # 1. 直接用完整型号搜
            best = _search(model_key) if model_key else ""
            # 2. 查别名表
            if not best and model_key in ALIAS:
                for alt in ALIAS[model_key]:
                    best = _search(alt)
                    if best: break
            # 3. 提取字母+数字段搜（如 "PIXMA G2010" → "g2010"）
            if not best:
                chunks = re.findall(r'[a-zA-Z]*[0-9]+[a-zA-Z0-9]*', model)
                for chunk in chunks:
                    best = _search(chunk.lower())
                    if best: break
                    if chunk.lower() in ALIAS:
                        for alt in ALIAS[chunk.lower()]:
                            best = _search(alt)
                            if best: break
                    if best: break
            return best
        except Exception:
            return ""

    def _get_ppd_label(self, ppd_model):
        """取 PPD model 对应的人类可读名称。"""
        try:
            res = subprocess.run(
                ["lpinfo", "-m"], stdout=subprocess.PIPE, text=True, timeout=10)
            for line in res.stdout.splitlines():
                if line.startswith(ppd_model + " "):
                    return line[len(ppd_model):].strip()
        except Exception:
            pass
        return ppd_model

    def _show_spinner(self, title, message):
        """显示一个带旋转动画的等待窗口，返回 (window, stop_fn)。"""
        win = tk.Toplevel(self.root)
        win.title(title)
        win.geometry("340x130")
        win.resizable(False, False)
        win.configure(bg=THEME["bg"])
        win.transient(self.root)
        win.grab_set()
        # 居中
        win.update_idletasks()
        x = self.root.winfo_x() + (self.root.winfo_width() - 340) // 2
        y = self.root.winfo_y() + (self.root.winfo_height() - 130) // 2
        win.geometry(f"+{x}+{y}")

        frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
        spin_var = tk.StringVar(value=frames[0])
        idx = [0]
        running = [True]

        top_frame = tk.Frame(win, bg=THEME["bg"])
        top_frame.pack(expand=True)

        tk.Label(top_frame, textvariable=spin_var,
                 font=("Monospace", 22),
                 bg=THEME["bg"], fg=THEME["accent"]).pack(side="left", padx=12)

        right = tk.Frame(top_frame, bg=THEME["bg"])
        right.pack(side="left")
        tk.Label(right, text=title,
                 font=("Helvetica", 11, "bold"),
                 bg=THEME["bg"], fg=THEME["text"]).pack(anchor="w")
        tk.Label(right, text=message,
                 font=("Helvetica", 9),
                 bg=THEME["bg"], fg=THEME["text_dim"],
                 wraplength=220, justify="left").pack(anchor="w", pady=(2, 0))

        def _tick():
            if not running[0]:
                return
            idx[0] = (idx[0] + 1) % len(frames)
            spin_var.set(frames[idx[0]])
            win.after(80, _tick)

        win.after(80, _tick)

        def stop():
            running[0] = False
            try:
                win.grab_release()
                win.destroy()
            except Exception:
                pass

        return win, stop

    def on_scan_double_click(self, event):
        self.install_selected_printer()

    def install_selected_printer(self):
        selected = self.scan_tree.selection()
        if not selected:
            messagebox.showwarning("提示", "请先在列表中选择一台发现的打印机设备。")
            return
        vals = self.scan_tree.item(selected[0])["values"]
        printer = None
        with self._data_lock:
            for p in self.printer_data:
                if p["uri"] in str(vals[2]) or vals[1] == p["name"]:
                    printer = dict(p); break
        if not printer:
            return

        # ── Windows 凭据（仅 SMB）────────────────────────────────────────
        username = password = ""
        if printer["kind"] == "WINDOWS":
            if messagebox.askyesno("需要凭据",
                                   "您选择的是【Windows 共享打印机】。\n是否需要配置账号密码？\n\n"
                                   "（如果 Windows 共享设置为「无需密码」可选否）"):
                username = simpledialog.askstring(
                    "凭据配置", "请输入 Windows 电脑的用户名:", parent=self.root)
                if username:
                    password = simpledialog.askstring(
                        "凭据配置", "请输入该用户的密码:",
                        show="*", parent=self.root)

        # ── 统一驱动匹配流程（后台线程，显示旋转动画）───────────────────
        brand = printer.get("brand", "").strip()
        model = printer.get("model", "").strip()

        # 在后台线程做耗时查询，主线程显示 spinner
        _result = [None, None]   # [auto_ppd, ppd_label]
        _, stop_spinner = self._show_spinner(
            "正在匹配驱动",
            f"识别到：{brand} {model}\n正在检索已安装的驱动库，请稍候...")

        def _lookup():
            ppd = self._preview_auto_ppd_by_brand_model(brand, model)
            label = self._get_ppd_label(ppd) if ppd else ""
            _result[0] = ppd
            _result[1] = label
            self.root.after(0, _on_lookup_done)

        def _on_lookup_done():
            stop_spinner()
            _proceed_with_driver(_result[0], _result[1])

        threading.Thread(target=_lookup, daemon=True).start()

        # _proceed_with_driver 会在 _on_lookup_done 里被调用（主线程）
        def _proceed_with_driver(auto_ppd, ppd_label):
            manual_ppd = "AUTO"

            if auto_ppd:
                choice = messagebox.askyesno(
                    "驱动匹配成功",
                    f"已识别打印机：{brand} {model}\n\n"
                    f"找到推荐驱动：\n{ppd_label}\n\n"
                    "是否使用此驱动？\n\n"
                    "（选「否」可手动从完整列表中选择）",
                    parent=self.root)
                if choice:
                    manual_ppd = auto_ppd
                else:
                    dlg = PPDPickerDialog(self.root,
                                          brand_hint=brand.lower(),
                                          auto_ppd=auto_ppd)
                    chosen = dlg.result_ppd
                    if chosen is None:
                        return
                    manual_ppd = chosen
            else:
                if printer["kind"] == "LINUX":
                    go_picker = messagebox.askyesno(
                        "驱动匹配",
                        f"打印机：{brand} {model}\n\n"
                        "未找到精确匹配驱动。\n\n"
                        "• 选「是」→ 从驱动列表手动选择（推荐，确保打印质量）\n"
                        "• 选「否」→ 使用 IPP 通用模式（driverless，可能有兼容问题）",
                        parent=self.root)
                    if go_picker:
                        dlg = PPDPickerDialog(self.root,
                                              brand_hint=brand.lower(),
                                              auto_ppd="")
                        chosen = dlg.result_ppd
                        if chosen is None:
                            return
                        manual_ppd = chosen
                else:
                    hint_msg = ""
                    if brand.lower() == "canon" and "g2010" in model.lower():
                        hint_msg = "\n💡 提示：Canon G2010 请搜索「g2000」（G2010 是 G2000 的亚洲版）"
                    elif brand.lower() == "canon":
                        hint_msg = "\n💡 提示：在搜索框输入型号后几位数字，例如「g2000」"
                    elif brand.lower() == "epson":
                        hint_msg = "\n💡 提示：Epson L系列请搜索，例如「l3150」或「l3200」"
                    messagebox.showinfo(
                        "需要手动选择驱动",
                        f"打印机：{brand} {model}\n\n"
                        f"在已安装驱动库中未找到精确匹配。{hint_msg}\n\n"
                        "将打开驱动列表，已自动筛选到该品牌。",
                        parent=self.root)
                    dlg = PPDPickerDialog(self.root,
                                          brand_hint=brand.lower(),
                                          auto_ppd="")
                    chosen = dlg.result_ppd
                    if chosen is None:
                        return
                    manual_ppd = chosen

            # ── URI 处理 + 实际安装（在 _proceed_with_driver 内执行）────
            uri_to_install = printer["uri"]
            if "MANUAL_ENTRY" in uri_to_install or "ManualEntry" in uri_to_install:
                manual_ip = simpledialog.askstring(
                    "手动添加 Windows 打印机",
                    "未能自动发现局域网内的 Windows 主机。\n\n"
                    "请输入 Windows 电脑的 IP 地址（如 192.168.1.100）：",
                    parent=self.root)
                if not manual_ip: return
                manual_share = simpledialog.askstring(
                    "手动添加 Windows 打印机",
                    f"IP 地址：{manual_ip}\n\n"
                    "请输入打印机共享名（在 Windows「打印机属性 → 共享」中查看）：",
                    parent=self.root)
                if not manual_share: return
                uri_to_install = f"smb://{manual_ip}/{manual_share}"
                printer["name"] = f"Win_{manual_share.replace(' ', '_')}"
            elif "SCAN_PLACEHOLDER" in uri_to_install:
                share_part = uri_to_install.split("SCAN_PLACEHOLDER/")[-1]
                confirmed_ip = simpledialog.askstring(
                    "请确认 Windows 主机 IP",
                    f"已发现共享打印机：{share_part}\n"
                    "但未能自动解析其 IP 地址。\n\n"
                    "请输入该 Windows 电脑的 IP 地址（如 192.168.1.100）：",
                    parent=self.root)
                if not confirmed_ip: return
                uri_to_install = uri_to_install.replace("SCAN_PLACEHOLDER", confirmed_ip)

            self._set_status(
                f"正在安装 {printer['name']}，请在弹出的授权窗口中输入密码...",
                THEME["accent"])

            def do_add():
                try:
                    cmd = ["pkexec", BASH_SCRIPT, "add",
                           printer["name"], printer["kind"], uri_to_install,
                           username or "", password or "", manual_ppd]
                    res = subprocess.run(cmd, stdout=subprocess.PIPE,
                                        text=True, timeout=30)
                    if "ADD_STATUS:SUCCESS" in res.stdout:
                        if "降级为 raw 模式" in res.stdout or "Local Raw Printer" in res.stdout:
                            self.root.after(0, lambda: messagebox.showwarning(
                                "添加成功但驱动未匹配",
                                f"打印机 [{printer['name']}] 已添加，但未找到专属驱动。\n\n"
                                "当前使用 RAW 模式（可能无法正常打印）。\n\n"
                                "请安装对应驱动包后重新添加：\n"
                                "• Canon：sudo apt install printer-driver-gutenprint\n"
                                "          或从 Canon 官网下载 cnijfilter2\n"
                                "• Epson： sudo apt install epson-inkjet-printer-escpr\n"
                                "• HP：    sudo apt install hplip"))
                        else:
                            self.root.after(0, lambda: messagebox.showinfo(
                                "成功",
                                f"🎉 打印机 [{printer['name']}] 已成功添加！\n驱动已自动匹配。"))
                        self.root.after(0, lambda: self._set_status(
                            "打印机添加成功！", THEME["success"]))
                    else:
                        self.root.after(0, lambda: messagebox.showerror(
                            "驱动安装失败",
                            f"打印机 [{printer['name']}] 安装失败。\n\n"
                            "可能原因及解决方法：\n"
                            "1. 缺少驱动包 → 请先运行：\n"
                            "   sudo apt install printer-driver-gutenprint\n"
                            "   （Canon/Epson 通用 Gutenprint 驱动）\n\n"
                            "2. Canon 专用驱动 → 从 Canon 官网下载 cnijfilter2\n\n"
                            "3. Windows 共享需要账号密码 → 重试并填写凭据\n\n"
                            "安装驱动包后请重新点击「一键安装」。"))
                except Exception as e:
                    self.root.after(0, lambda: messagebox.showerror(
                        "错误", f"安装终止: {e}"))
                finally:
                    self._active_threads -= 1

            self._active_threads += 1
            threading.Thread(target=do_add, daemon=True).start()

    # ══════════════════════════════════════════════
    # Tab 2 逻辑：已安装打印机管理
    # ══════════════════════════════════════════════
    def start_list_installed_thread(self):
        self.refresh_installed_btn.config(state="disabled", text="刷新中...")
        self._set_status("正在读取系统已安装打印机列表...", THEME["accent"])
        self.installed_tree.delete(*self.installed_tree.get_children())
        self._active_threads += 1
        threading.Thread(target=self.run_list_installed, daemon=True).start()

    def run_list_installed(self):
        try:
            process = subprocess.Popen(
                [BASH_SCRIPT, "list"],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            results = []
            debug_default = ""
            inside = False
            for line in process.stdout:
                line = line.strip()
                if line == "===LIST_START===":
                    inside = True; continue
                if line == "===LIST_END===":
                    inside = False; continue
                if not inside:
                    continue
                # 捕获调试行，记录 shell 实际解析到的默认打印机名
                if line.startswith("DEBUG_DEFAULT:"):
                    debug_default = line[len("DEBUG_DEFAULT:"):]
                    continue
                if line.startswith("PRINTER:"):
                    parts = line.split("|")
                    if len(parts) < 5: continue
                    name    = self._parse_field(parts[0], len("PRINTER:"))
                    uri     = self._parse_field(parts[1], len("URI:"))
                    state   = self._parse_field(parts[2], len("STATE:"))
                    jobs    = self._parse_field(parts[3], len("JOBS:"))
                    default = self._parse_field(parts[4], len("DEFAULT:"))
                    results.append((name, uri, state, jobs, default))
            process.wait()
            self.root.after(0, self.update_installed_ui, results, debug_default)
        except Exception as e:
            self.root.after(0, lambda: self._set_status(
                f"读取失败: {e}", THEME["danger"]))
        finally:
            self._active_threads -= 1

    def update_installed_ui(self, results, debug_default=""):
        self.refresh_installed_btn.config(state="normal",
                                          text="🔄 刷新已安装打印机列表")
        default_name = ""
        for name, uri, state, jobs, is_default in results:
            jobs_int = int(jobs) if jobs.isdigit() else 0
            jobs_show = f"⚠️ {jobs_int} 个" if jobs_int > 0 else "无"
            default_show = "⭐ 默认" if is_default == "YES" else ""
            tag = ("default_tag",) if is_default == "YES" else ()
            self.installed_tree.insert("", "end",
                                       values=(default_show, name, uri,
                                               state, jobs_show),
                                       tags=tag)
            if is_default == "YES":
                default_name = name
        count = len(results)
        if count == 0:
            self._set_status("系统中暂无已安装的打印机。", THEME["text_dim"])
        elif default_name:
            self._set_status(
                f"共检测到 {count} 台打印机 | ⭐ 当前默认：{default_name}",
                THEME["success"])
        else:
            # shell 解析到的默认名但列表里没有匹配——显示原始值供排查
            hint = f"（系统返回：'{debug_default}'）" if debug_default else ""
            self._set_status(
                f"共检测到 {count} 台打印机 | 默认打印机未能识别 {hint}",
                THEME["warning"])

    def set_selected_as_default(self):
        selected = self.installed_tree.selection()
        if not selected:
            messagebox.showwarning("提示", "请先在列表中选择一台打印机。")
            return
        printer_name = self.installed_tree.item(selected[0])["values"][1]
        # 已经是默认打印机则提示
        current_default = self.installed_tree.item(selected[0])["values"][0]
        if current_default == "⭐ 默认":
            messagebox.showinfo("提示", f"【{printer_name}】已经是当前默认打印机了。")
            return
        if not messagebox.askyesno(
                "确认设置",
                f"将以下打印机设为系统默认打印机：\n\n  ⭐ 【{printer_name}】\n\n"
                "设置后，所有应用程序的「默认打印」将自动使用此设备。"):
            return
        self._set_status(f"正在将 [{printer_name}] 设为默认打印机...",
                         THEME["warning"])
        self._active_threads += 1

        def do_set_default():
            try:
                res = subprocess.run(
                    ["pkexec", BASH_SCRIPT, "setdefault", printer_name],
                    stdout=subprocess.PIPE, text=True, timeout=15)
                if "SETDEFAULT_STATUS:SUCCESS" in res.stdout:
                    self.root.after(0, lambda: (
                        self._set_status(
                            f"⭐ 默认打印机已设置为 [{printer_name}]。",
                            THEME["success"]),
                        messagebox.showinfo(
                            "设置成功",
                            f"⭐ 【{printer_name}】\n\n已成功设为系统默认打印机！\n"
                            "所有应用程序打印时将优先使用此设备。"),
                        self.start_list_installed_thread()
                    ))
                else:
                    reason = "未知错误"
                    for part in res.stdout.split("|"):
                        if part.startswith("REASON:"):
                            reason = part[7:]
                    self.root.after(0, lambda: messagebox.showerror(
                        "设置失败",
                        f"无法将 [{printer_name}] 设为默认打印机：\n{reason}"))
            except Exception as e:
                self.root.after(0, lambda: messagebox.showerror(
                    "错误", f"操作终止: {e}"))
            finally:
                self._active_threads -= 1

        threading.Thread(target=do_set_default, daemon=True).start()

    def delete_selected_printer(self):
        selected = self.installed_tree.selection()
        if not selected:
            messagebox.showwarning("提示", "请先在列表中选择一台已安装的打印机。")
            return
        printer_name = self.installed_tree.item(selected[0])["values"][1]
        if not messagebox.askyesno(
                "确认删除",
                f"您确定要从系统中永久删除打印机：\n\n  【{printer_name}】\n\n"
                "此操作将同时取消该打印机的所有排队任务，且不可撤销。"):
            return
        self._set_status(f"正在删除打印机 [{printer_name}]...", THEME["warning"])
        self._active_threads += 1

        def do_delete():
            try:
                res = subprocess.run(
                    ["pkexec", BASH_SCRIPT, "delete", printer_name],
                    stdout=subprocess.PIPE, text=True, timeout=20)
                if "DELETE_STATUS:SUCCESS" in res.stdout:
                    self.root.after(0, lambda: (
                        self._set_status(
                            f"打印机 [{printer_name}] 已成功删除。",
                            THEME["success"]),
                        messagebox.showinfo(
                            "删除成功",
                            f"打印机 [{printer_name}] 已从系统中移除。"),
                        self.start_list_installed_thread()
                    ))
                else:
                    reason = "未知错误"
                    for part in res.stdout.split("|"):
                        if part.startswith("REASON:"):
                            reason = part[7:]
                    self.root.after(0, lambda: messagebox.showerror(
                        "删除失败", f"无法删除打印机 [{printer_name}]：\n{reason}"))
            except Exception as e:
                self.root.after(0, lambda: messagebox.showerror(
                    "错误", f"删除操作终止: {e}"))
            finally:
                self._active_threads -= 1

        threading.Thread(target=do_delete, daemon=True).start()

    # ══════════════════════════════════════════════
    # Tab 3 逻辑：CUPS 任务监控
    # ══════════════════════════════════════════════
    def start_list_jobs_thread(self):
        self.refresh_jobs_btn.config(state="disabled", text="刷新中...")
        self._set_status("正在读取 CUPS 打印任务队列...", THEME["accent"])
        self.jobs_tree.delete(*self.jobs_tree.get_children())
        self._active_threads += 1
        threading.Thread(target=self.run_list_jobs, daemon=True).start()

    def run_list_jobs(self):
        try:
            process = subprocess.Popen(
                [BASH_SCRIPT, "jobs"],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            results = []
            no_jobs = False
            inside = False
            for line in process.stdout:
                line = line.strip()
                if line == "===JOBS_START===":
                    inside = True; continue
                if line == "===JOBS_END===":
                    inside = False; continue
                if not inside: continue
                if line == "NO_JOBS":
                    no_jobs = True; continue
                if line.startswith("JOB:"):
                    parts = line.split("|")
                    if len(parts) < 6: continue
                    job_id  = self._parse_field(parts[0], len("JOB:"))
                    printer = self._parse_field(parts[1], len("PRINTER:"))
                    owner   = self._parse_field(parts[2], len("OWNER:"))
                    size    = self._parse_field(parts[3], len("SIZE:"))
                    when    = self._parse_field(parts[4], len("WHEN:"))
                    stuck   = self._parse_field(parts[5], len("STUCK:"))
                    results.append((job_id, printer, owner, size, when, stuck))
            process.wait()
            self.root.after(0, self.update_jobs_ui, results, no_jobs)
        except Exception as e:
            self.root.after(0, lambda: self._set_status(
                f"读取任务失败: {e}", THEME["danger"]))
        finally:
            self._active_threads -= 1

    def update_jobs_ui(self, results, no_jobs):
        self.refresh_jobs_btn.config(state="normal", text="🔄 刷新任务列表")
        if no_jobs or not results:
            self._set_status("✅ 当前所有打印机任务队列为空，没有积压任务。",
                             THEME["success"])
            return
        stuck_count = 0
        for job_id, printer, owner, size, when, stuck in results:
            stuck_show = "⚠️ 疑似卡住" if stuck == "YES" else "正常"
            tag = ("stuck_tag",) if stuck == "YES" else ()
            self.jobs_tree.insert("", "end",
                                  values=(job_id, printer, owner,
                                          size, when, stuck_show),
                                  tags=tag)
            if stuck == "YES":
                stuck_count += 1
        total = len(results)
        msg = f"共 {total} 个未完成任务"
        if stuck_count:
            msg += f"，其中 {stuck_count} 个疑似卡住（橙色高亮）"
        self._set_status(msg, THEME["warning"] if stuck_count else THEME["text"])

    def cancel_selected_job(self):
        selected = self.jobs_tree.selection()
        if not selected:
            messagebox.showwarning("提示", "请先在列表中选择一个任务。")
            return
        job_id = self.jobs_tree.item(selected[0])["values"][0]
        if not messagebox.askyesno("确认", f"取消任务：{job_id}？"):
            return
        self._set_status(f"正在取消任务 [{job_id}]...", THEME["warning"])
        self._active_threads += 1

        def do_cancel():
            try:
                subprocess.run(["pkexec", "cancel", str(job_id)],
                               timeout=10)
                self.root.after(0, lambda: (
                    self._set_status(f"任务 [{job_id}] 已取消。",
                                     THEME["success"]),
                    self.start_list_jobs_thread()
                ))
            except Exception as e:
                self.root.after(0, lambda: messagebox.showerror(
                    "错误", f"取消任务失败: {e}"))
            finally:
                self._active_threads -= 1

        threading.Thread(target=do_cancel, daemon=True).start()

    def cancel_all_jobs(self):
        if not messagebox.askyesno(
                "警告",
                "确定要取消 CUPS 中所有打印机的全部任务吗？\n此操作不可撤销。"):
            return
        self._set_status("正在清除所有打印任务...", THEME["danger"])
        self._active_threads += 1

        def do_cancel_all():
            try:
                subprocess.run(["pkexec", "cancel", "-a", "-x"], timeout=15)
                self.root.after(0, lambda: (
                    self._set_status("所有任务已清除。", THEME["success"]),
                    self.start_list_jobs_thread()
                ))
            except Exception as e:
                self.root.after(0, lambda: messagebox.showerror(
                    "错误", f"清除失败: {e}"))
            finally:
                self._active_threads -= 1

        threading.Thread(target=do_cancel_all, daemon=True).start()

    # ─────────────────────────────────────────────
    # 关闭处理
    # ─────────────────────────────────────────────
    def _on_closing(self):
        if self._active_threads > 0:
            if not messagebox.askyesno(
                    "有任务进行中",
                    f"当前有 {self._active_threads} 个操作正在后台执行中。\n"
                    "强行关闭可能导致打印机配置不完整。\n\n确定要退出吗？"):
                return
        try:
            self.root.destroy()
        except Exception:
            pass


if __name__ == "__main__":
    root = tk.Tk()
    app = PrinterManagerApp(root)
    root.mainloop()
