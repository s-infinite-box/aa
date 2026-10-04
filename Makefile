# aa 阶段 0 的最小构建、启动与调试入口。
#
# 所有生成物都放在 Cargo 已使用且被 .gitignore 忽略的 target/ 中：
#
#   target/x86_64-unknown-none/debug/aa  Rust/汇编链接后的内核 ELF
#   target/iso-root/                     GRUB ISO 的临时目录树
#   target/aa.iso                        QEMU 启动使用的光盘镜像

.DEFAULT_GOAL := help

KERNEL := target/x86_64-unknown-none/debug/aa
ISO_ROOT := target/iso-root
ISO_IMAGE := target/aa.iso
GRUB_CONFIG := grub/grub.cfg
GDB_SCRIPT := debug/entry.gdb

# 固定 QEMU 的机器、CPU、内存和单核配置，避免不同宿主机默认值造成差异。
# 当前内核尚未初始化显示设备，GRUB 和未来的内核日志统一走 COM1 串口。
QEMU_COMMON := \
	-machine q35 \
	-accel tcg \
	-cpu qemu64 \
	-m 128M \
	-smp 1 \
	-cdrom $(ISO_IMAGE) \
	-boot d \
	-display none \
	-serial stdio \
	-monitor none \
	-no-reboot \
	-no-shutdown

.PHONY: help build check iso run debug gdb


build:
	cargo build

check:
	cargo fmt --check
	cargo build
	grub2-file --is-x86-multiboot2 $(KERNEL)

# GRUB 要求 ISO 中的配置位于 /boot/grub/grub.cfg。
# 内核复制到 /boot/aa，路径必须与 grub.cfg 中的 multiboot2 命令一致。
iso: check
	mkdir -p $(ISO_ROOT)/boot/grub
	cp $(KERNEL) $(ISO_ROOT)/boot/aa
	cp $(GRUB_CONFIG) $(ISO_ROOT)/boot/grub/grub.cfg
	grub2-mkrescue -o $(ISO_IMAGE) $(ISO_ROOT)

run: iso
	qemu-system-x86_64 $(QEMU_COMMON)

# -S：复位后立刻暂停所有虚拟 CPU；此时一条客户机指令都还没有执行。
# -gdb：在本机 TCP 1234 端口开放 QEMU 的 GDB stub。
debug_server: iso
	qemu-system-x86_64 $(QEMU_COMMON) -S -gdb tcp:127.0.0.1:1234

# 需要先在第一个终端运行 make debug，再在第二个终端运行本目标。
gdb_script:
	gdb -x $(GDB_SCRIPT)

#
gdb:
	gdb
