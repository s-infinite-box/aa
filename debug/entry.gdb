# 关闭分页，避免脚本输出停在“按回车继续”的交互状态。
set pagination off

# 汇编统一使用 Intel 展示风格；这只影响 GDB 输出，不改变机器代码。
set disassembly-flavor intel

# 加载带符号和调试信息的内核 ELF。该命令不会启动内核。
file target/x86_64-unknown-none/debug/aa

# 连接由 `make debug` 在本机回环地址 1234 端口开放的 QEMU GDB stub。
target remote 127.0.0.1:1234

# QEMU 对 x86_64 虚拟机报告 i386:x86-64 target description，而当前
# _start 实际是 .code32。不要强制执行 `set architecture i386`，否则这版
# GDB/QEMU 会出现 target description 不兼容；也不要用 GDB 的 x/i 判断
# 入口编码。静态机器指令统一用 `objdump -D -m i386 -Mintel` 复核。

# QEMU 此时仍停在复位入口，GRUB 还没有把 aa 装入 0x100000。
# 使用硬件断点，避免普通软件断点被随后装入的内核映像覆盖。
hbreak *_start

# 让 BIOS 和 GRUB 继续执行，直到 GRUB 跳入 aa 的 _start。
continue

echo \n已停在 aa 的 32 位入口 _start。\n
echo 此时还没有执行 aa 的第一条指令，下面是 GRUB 交付的入口状态：\n
info registers eax ebx esp eflags rip

# 保存入口 EBX，稍后用它核对写入 multiboot_info 的值。
set $entry_multiboot_info = $ebx

# boot_environment_ready 是 entry.S 在参数保存、cld 和栈初始化之后
# 导出的零长度检查点。内核此时已经装入，继续使用硬件断点也最明确。
hbreak *boot_environment_ready
continue

echo \n已到达 boot_environment_ready。\n
echo 现在核对保存区、启动栈和方向标志：\n
info registers esp ebp eflags rip
x/wx &multiboot_magic
x/wx &multiboot_info
printf "入口 EBX                 = 0x%x\n", $entry_multiboot_info
printf "期望 ESP                 = 0x%x\n", (unsigned long)&boot_stack_top
printf "EFLAGS.DF（期望为 0）    = %u\n", (($eflags >> 10) & 1)

set $saved_magic = *(unsigned int *)&multiboot_magic
set $saved_info = *(unsigned int *)&multiboot_info

if $saved_magic == 0x36d76289
    echo [PASS] Multiboot2 magic 已正确保存。\n
else
    echo [FAIL] Multiboot2 magic 不正确。\n
end

if $saved_info == $entry_multiboot_info
    echo [PASS] Multiboot2 信息地址与入口 EBX 一致。\n
else
    echo [FAIL] Multiboot2 信息地址与入口 EBX 不一致。\n
end

if $esp == (unsigned long)&boot_stack_top
    echo [PASS] ESP 已切换到 boot_stack_top。\n
else
    echo [FAIL] ESP 没有指向 boot_stack_top。\n
end

if (($eflags >> 10) & 1) == 0
    echo [PASS] DF 已清零。\n
else
    echo [FAIL] DF 仍为 1。\n
end

echo \n如果上面的保存值和寄存器符合预期，就已经动态证明了第一段启动交接。\n
echo 当前 CPU 停在 hlt 之前；可用 quit 退出 GDB，再在 QEMU 终端按 Ctrl-C。\n
