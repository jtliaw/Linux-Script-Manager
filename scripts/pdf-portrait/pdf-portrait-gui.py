#!/usr/bin/env python3
# pdf-portrait-gui.py
# 描述: PDF 双向转换工具（横转纵 / 纵转横）
import tkinter as tk
from tkinter import ttk, messagebox, filedialog
import subprocess
import os
import threading

SCRIPT_DIR  = os.path.dirname(os.path.realpath(__file__))
BASH_SCRIPT = os.path.join(SCRIPT_DIR, "pdf-portrait-helper.sh")

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
    "landscape_btn":"#cba6f7",  # 紫色：纵转横按钮
}

class PdfPortraitApp:
    def __init__(self, root):
        self.root = root
        self.root.title("PDF 双向转换工具")
        self.root.geometry("740x560")
        self.root.configure(bg=THEME["bg"])
        self.root.resizable(False, False)

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
        style.configure("green.Horizontal.TProgressbar",
                        troughcolor=THEME["bg_card"],
                        background=THEME["success"])

        self._active_threads = 0
        self._lock = threading.Lock()
        self._results = []
        self._folder = ""

        self.create_widgets()
        self.root.protocol("WM_DELETE_WINDOW", self._on_closing)

    def create_widgets(self):
        # 标题
        tk.Label(self.root,
                 text="📄 PDF 双向转换工具",
                 font=("Helvetica", 14, "bold"),
                 bg=THEME["bg"], fg=THEME["accent"]
                 ).pack(pady=10)

        # ── 文件夹选择区 ──
        folder_frame = tk.Frame(self.root, bg=THEME["bg"])
        folder_frame.pack(fill="x", padx=15, pady=2)

        tk.Label(folder_frame, text="PDF 文件夹：",
                 font=("Helvetica", 10),
                 bg=THEME["bg"], fg=THEME["text"]
                 ).pack(side="left")

        self.folder_var = tk.StringVar(value="请选择包含 PDF 的文件夹...")
        self.folder_entry = tk.Entry(folder_frame,
                                     textvariable=self.folder_var,
                                     font=("Helvetica", 9),
                                     bg=THEME["bg_card"], fg=THEME["text_dim"],
                                     insertbackground=THEME["text"],
                                     relief="flat", bd=4,
                                     width=44)
        self.folder_entry.pack(side="left", padx=6)

        tk.Button(folder_frame,
                  text="📂 浏览",
                  font=("Helvetica", 9),
                  bg=THEME["accent"], fg="#11111b",
                  activebackground=THEME["accent_hover"],
                  bd=0, cursor="hand2", padx=10, pady=4,
                  command=self.browse_folder
                  ).pack(side="left")

        # ── 双按钮转换区 ──
        btn_frame = tk.Frame(self.root, bg=THEME["bg"])
        btn_frame.pack(fill="x", padx=15, pady=8)

        self.portrait_btn = tk.Button(
            btn_frame,
            text="⚡ 横向 → A4 纵向",
            font=("Helvetica", 11, "bold"),
            bg=THEME["success"], fg="#11111b",
            activebackground="#b4befe",
            bd=0, cursor="hand2", pady=10,
            command=lambda: self.start_convert_thread("portrait")
        )
        self.portrait_btn.pack(side="left", fill="x", expand=True, padx=(0, 6))

        self.landscape_btn = tk.Button(
            btn_frame,
            text="🔄 纵向 → A4 横向",
            font=("Helvetica", 11, "bold"),
            bg=THEME["landscape_btn"], fg="#11111b",
            activebackground="#f5c2e7",
            bd=0, cursor="hand2", pady=10,
            command=lambda: self.start_convert_thread("landscape")
        )
        self.landscape_btn.pack(side="left", fill="x", expand=True, padx=(6, 0))

        # ── 进度条 ──
        self.progress_var = tk.DoubleVar(value=0)
        self.progress_bar = ttk.Progressbar(
            self.root,
            variable=self.progress_var,
            maximum=100,
            style="green.Horizontal.TProgressbar",
            length=710
        )
        self.progress_bar.pack(padx=15, pady=2)

        # ── 状态提示 ──
        self.status_lbl = tk.Label(
            self.root,
            text="就绪。请选择文件夹，然后选择转换方向...",
            font=("Helvetica", 9),
            bg=THEME["bg"], fg=THEME["text_dim"],
            anchor="w"
        )
        self.status_lbl.pack(fill="x", padx=20, pady=2)

        # ── 结果列表 ──
        list_frame = tk.Frame(self.root, bg=THEME["bg"])
        list_frame.pack(fill="both", expand=True, padx=15, pady=5)

        columns = ("status", "filename", "note")
        self.tree = ttk.Treeview(list_frame, columns=columns,
                                 show="headings", height=10)
        self.tree.heading("status",   text="状态")
        self.tree.heading("filename", text="文件名")
        self.tree.heading("note",     text="备注")

        self.tree.column("status",   width=70,  anchor="center")
        self.tree.column("filename", width=380, anchor="w")
        self.tree.column("note",     width=230, anchor="w")

        scrollbar = ttk.Scrollbar(list_frame, orient="vertical",
                                  command=self.tree.yview)
        self.tree.configure(yscrollcommand=scrollbar.set)
        self.tree.pack(side="left", fill="both", expand=True)
        scrollbar.pack(side="right", fill="y")

        # ── 底部按钮（放大、醒目）──
        bottom_frame = tk.Frame(self.root, bg=THEME["bg"])
        bottom_frame.pack(fill="x", padx=15, pady=10)

        tk.Button(
            bottom_frame,
            text="📁  打开输出文件夹",
            font=("Helvetica", 11, "bold"),
            bg=THEME["accent"], fg="#11111b",
            activebackground=THEME["accent_hover"],
            bd=0, cursor="hand2",
            padx=20, pady=10,
            command=self.open_output_folder
        ).pack(side="left", padx=(0, 10))

        tk.Button(
            bottom_frame,
            text="🗑️  清空结果列表",
            font=("Helvetica", 11, "bold"),
            bg=THEME["win_bg"], fg=THEME["text"],
            activebackground=THEME["bg_card"],
            bd=0, cursor="hand2",
            padx=20, pady=10,
            command=self.clear_results
        ).pack(side="left")

    # ── 文件夹浏览 ──
    def browse_folder(self):
        folder = filedialog.askdirectory(title="选择包含 PDF 的文件夹")
        if folder:
            self._folder = folder
            self.folder_var.set(folder)
            self.folder_entry.config(fg=THEME["text"])
            pdf_count = len([f for f in os.listdir(folder)
                             if f.lower().endswith(".pdf")])
            self.status_lbl.config(
                text=f"已选择：{folder}  （检测到 {pdf_count} 个 PDF 文件）",
                fg=THEME["accent"]
            )

    # ── 启动转换线程 ──
    def start_convert_thread(self, mode):
        folder = self.folder_var.get().strip()
        if not folder or folder.startswith("请选择"):
            messagebox.showwarning("提示", "请先选择一个包含 PDF 的文件夹。")
            return
        if not os.path.isdir(folder):
            messagebox.showerror("错误", f"路径不存在：{folder}")
            return

        self._folder = folder
        self._mode   = mode

        self.portrait_btn.config(state="disabled")
        self.landscape_btn.config(state="disabled")

        if mode == "portrait":
            self.portrait_btn.config(text="转换中，请稍候...")
            mode_label = "横向 → A4 纵向"
            subdir     = "纵向输出"
        else:
            self.landscape_btn.config(text="转换中，请稍候...")
            mode_label = "纵向 → A4 横向"
            subdir     = "横向输出"

        self._subdir = subdir
        self.progress_var.set(0)
        self.tree.delete(*self.tree.get_children())
        with self._lock:
            self._results.clear()

        self.status_lbl.config(
            text=f"正在执行【{mode_label}】转换，请稍候...",
            fg=THEME["accent"]
        )

        self._active_threads += 1
        threading.Thread(target=self.run_convert,
                         args=(folder, mode, subdir), daemon=True).start()

    # ── 转换核心（背景线程）──
    def run_convert(self, folder, mode, subdir):
        try:
            process = subprocess.Popen(
                [BASH_SCRIPT, "convert", folder, mode],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True
            )

            total      = 0
            done       = 0
            ok_count   = 0
            fail_count = 0

            for line in process.stdout:
                line = line.strip()

                if line.startswith("TOTAL:"):
                    total = int(line.split(":", 1)[1])

                elif line.startswith("OK:"):
                    filename = line[3:]
                    done += 1; ok_count += 1
                    pct = (done / total * 100) if total > 0 else 100
                    self.root.after(0, self._add_row, "✅", filename, "转换成功", pct)

                elif line.startswith("FAIL:"):
                    filename = line[5:]
                    done += 1; fail_count += 1
                    pct = (done / total * 100) if total > 0 else 100
                    self.root.after(0, self._add_row, "❌", filename, "转换失败", pct)

                elif line == "STATUS:NO_PDF":
                    self.root.after(0, self._finish, 0, 0, folder, subdir, "no_pdf")
                    return

            process.wait()
            self.root.after(0, self._finish, ok_count, fail_count, folder, subdir, "done")

        except Exception as e:
            self.root.after(0, lambda: messagebox.showerror(
                "错误", f"转换程序异常终止:\n{str(e)}"))
            self.root.after(0, self._reset_btns)
        finally:
            self._active_threads -= 1

    # ── UI 回调 ──
    def _add_row(self, status_icon, filename, note, pct):
        self.tree.insert("", "end", values=(status_icon, filename, note))
        self.tree.yview_moveto(1)
        self.progress_var.set(pct)
        self.status_lbl.config(
            text=f"转换中... {pct:.0f}%  ─  {filename}",
            fg=THEME["accent"]
        )

    def _finish(self, ok, fail, folder, subdir, reason):
        self._reset_btns()
        self.progress_var.set(100)

        if reason == "no_pdf":
            self.status_lbl.config(
                text="⚠️  所选文件夹内未发现任何 PDF 文件。",
                fg=THEME["warning"]
            )
            messagebox.showwarning("无文件", "所选文件夹内没有 PDF 文件。")
            return

        output_dir = os.path.join(folder, subdir)
        summary = (
            f"【转换完成】\n\n"
            f"✅ 成功：{ok} 个\n"
            f"❌ 失败：{fail} 个\n\n"
            f"输出位置：\n{output_dir}"
        )
        self.status_lbl.config(
            text=f"完成！成功 {ok} 个 / 失败 {fail} 个  →  {output_dir}",
            fg=THEME["success"]
        )
        messagebox.showinfo("完成", summary)

    def _reset_btns(self):
        self.portrait_btn.config(state="normal",  text="⚡ 横向 → A4 纵向")
        self.landscape_btn.config(state="normal", text="🔄 纵向 → A4 横向")

    # ── 辅助操作 ──
    def open_output_folder(self):
        folder = self._folder
        if not folder:
            messagebox.showwarning("提示", "请先执行一次转换。")
            return
        # 优先打开最近用的输出子目录
        subdir = getattr(self, "_subdir", "纵向输出")
        output_dir = os.path.join(folder, subdir)
        if not os.path.isdir(output_dir):
            # 退回到父文件夹
            output_dir = folder
        subprocess.Popen(["xdg-open", output_dir])

    def clear_results(self):
        self.tree.delete(*self.tree.get_children())
        self.progress_var.set(0)
        self.status_lbl.config(
            text="列表已清空，可重新选择文件夹开始转换。",
            fg=THEME["text_dim"]
        )

    def _on_closing(self):
        if self._active_threads > 0:
            if not messagebox.askyesno(
                "有任务进行中",
                f"当前有 {self._active_threads} 个转换任务正在执行中。\n"
                "强行关闭可能导致部分 PDF 未完成转换。\n\n确定要退出吗？"
            ):
                return
        try:
            self.root.destroy()
        except Exception:
            pass


if __name__ == "__main__":
    root = tk.Tk()
    app  = PdfPortraitApp(root)
    root.mainloop()
