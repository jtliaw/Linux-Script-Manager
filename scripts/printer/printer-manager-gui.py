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
        self.scan_btn.config(state="disabled", text="正在全网深层搜索...")
        self._set_status("正在唤醒 Avahi/Samba 引擎探测内网打印机，请稍候...",
                         THEME["accent"])
        self.scan_tree.delete(*self.scan_tree.get_children())
        with self._data_lock:
            self.printer_data.clear()
        self._active_threads += 1
        threading.Thread(target=self.run_scan, daemon=True).start()

    def run_scan(self):
        try:
            process = subprocess.Popen(
                [BASH_SCRIPT, "scan"],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            local_buf = []
            inside_block = False
            for line in process.stdout:
                line = line.strip()
                if line == "===SCAN_START===":
                    inside_block = True; continue
                if line == "===SCAN_END===":
                    inside_block = False; continue
                if inside_block and line.startswith("KIND:"):
                    parts = line.split("|")
                    if len(parts) < 4:
                        continue
                    kind = self._parse_field(parts[0], len("KIND:"))
                    uri  = self._parse_field(parts[1], len("URI:"))
                    name = self._parse_field(parts[2], len("NAME:"))
                    info = self._parse_field(parts[3], len("INFO:"))
                    local_buf.append({"kind": kind, "uri": uri,
                                      "name": name, "info": info})
            process.wait()
            with self._data_lock:
                self.printer_data.extend(local_buf)
            self.root.after(0, self.update_scan_table_ui, "SUCCESS")
        except Exception as e:
            self.root.after(0, self.update_scan_table_ui, f"ERROR: {e}")
        finally:
            self._active_threads -= 1

    def update_scan_table_ui(self, status):
        self.scan_btn.config(state="normal", text="🔍 智能搜索全网/USB打印机")
        if "ERROR" in status:
            self._set_status(f"扫描失败: {status}", THEME["danger"])
            return
        for p in self.printer_data:
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
        self._set_status(
            f"扫描完成！共发现 {len(self.printer_data)} 台设备。双击或点击下方按钮安装。",
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

        username = password = ""
        if printer["kind"] == "WINDOWS":
            if messagebox.askyesno("需要凭据",
                                   "您选择的是【Windows 共享打印机】。\n是否需要配置账号密码？"):
                username = simpledialog.askstring(
                    "凭据配置", "请输入 Windows 电脑的用户名:", parent=self.root)
                if username:
                    password = simpledialog.askstring(
                        "凭据配置", "请输入该用户的密码:",
                        show="*", parent=self.root)

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
            f"正在为 {printer['name']} 静默匹配并配置万能驱动...",
            THEME["accent"])

        def do_add():
            try:
                cmd = ["pkexec", BASH_SCRIPT, "add",
                       printer["name"], printer["kind"], uri_to_install,
                       username or "", password or ""]
                res = subprocess.run(cmd, stdout=subprocess.PIPE,
                                     text=True, timeout=30)
                if "ADD_STATUS:SUCCESS" in res.stdout:
                    self.root.after(0, lambda: messagebox.showinfo(
                        "成功",
                        f"🎉 打印机 [{printer['name']}] 已成功添加进您的 Linux 系统！"))
                    self.root.after(0, lambda: self._set_status(
                        "打印机添加成功！", THEME["success"]))
                else:
                    self.root.after(0, lambda: messagebox.showerror(
                        "错误",
                        "驱动安装失败。可能此打印机不支持 Driverless 协议。"))
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
        if current_default == "⭐ 是":
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
