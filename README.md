# aa（一一）

aa 是一个以 Linux 0.11 为机制参照、面向 QEMU x86_64 的教学型 Rust
内核。当前处于阶段 0：GRUB2 通过 Multiboot2 装载内核，32 位入口已经
保存启动参数并建立临时启动栈，尚未进入 long mode 和 Rust 入口。

## 常用命令

以下命令都在 `_rust_kernel/` 目录执行：

```bash
# 只构建内核 ELF。
make build

# 检查 Rust 格式、构建内核并验证 Multiboot2 header。
make check

# 生成可启动的 GRUB ISO：target/aa.iso。
make iso

# 正常启动 QEMU。当前内核最终停在 hlt，使用 Ctrl-C 退出。
make run
```

运行 `make` 可以查看全部命令说明。

## QEMU + GDB 调试入口

第一个终端启动 QEMU。`-S` 会让虚拟 CPU 在复位后暂停，GDB stub 只监听
本机回环地址 `127.0.0.1:1234`：

```bash
make debug
```

第二个终端仍在 `_rust_kernel/` 目录运行：

```bash
make gdb
```

`debug/entry.gdb` 会执行两次硬件断点验证：

1. 在 `_start` 停住，显示 GRUB 交付的 `EAX`、`EBX`、`ESP` 和 `EFLAGS`；
2. 在 `boot_environment_ready` 停住，检查 magic、信息地址、启动栈和 `DF`。

全部通过时会显示四行 `[PASS]`。退出 GDB 后，在 QEMU 终端按 `Ctrl-C`
终止当前虚拟机。

想从第一条指令逐条调试，请按
[汇编与 GDB 调试手册](../docs/AA-Assembly-and-GDB.md)
中的手动流程启动 `gdb -q` 并使用 `si`；`make gdb` 会自动运行到第二个检查点。
手册同时汇总了当前 CPU 指令、汇编指示符、地址语法和逐步预期结果。

当前内核文件是 ELF64，但 `_start` 仍是 `.code32`。本机 GDB/QEMU 组合会
把这段代码误按 64 位模式反汇编。仍可使用 `si` 单步，并观察地址、寄存器和
内存；入口机器指令使用下面的命令按 32 位、AT&T 风格复核：

```bash
objdump -d -m i386 -M att --disassemble=_start \
  target/x86_64-unknown-none/debug/aa
```
