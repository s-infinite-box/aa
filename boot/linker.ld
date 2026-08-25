/*
 * 指定 ELF 的入口符号。
 *
 * 链接器会查找 entry.S 中定义的全局符号 _start，
 * 并把它的地址写入 ELF 头的 e_entry 字段。
 * GRUB 加载内核后会跳转到这个地址。
 */
ENTRY(_start)

/*
 * 强制输出为 x86-64 的 64 位 ELF 文件。
 *
 * 注意：ELF64 是文件格式；_start 仍然可以是一段 .code32 指令，
 * 因为 GRUB 通过 Multiboot2 BIOS 路径进入时 CPU 仍处于 32 位保护模式。
 */
OUTPUT_FORMAT(elf64-x86-64)

/*
 * SECTIONS 用来描述最终 ELF 中各个输出节的内存布局。
 */
SECTIONS
{
    /*
     * “.”是链接器的位置计数器，表示下一个内容的内存地址。
     *
     * 从 1 MiB 处开始放置 aa，避开传统 PC 的低端内存、
     * BIOS 数据区、显存和 ROM 等区域。
     *
     * 这是装载后的内存地址，不代表 ELF 文件前面会填充 1 MiB。
     */
    . = 0x00100000;

    /*
     * 创建 .boot 输出节。
     *
     * Multiboot2 要求 header 按 8 字节对齐。
     * 当前地址 0x100000 本身也已经满足 8 字节对齐。
     */
    .boot : ALIGN(8)
    {
        /*
         * 收集所有输入文件中的 .multiboot_header 节。
         *
         * KEEP 防止链接器执行 section garbage collection 时，
         * 因为没有普通代码引用 header 而将它删除。
         *
         * 这个 header 是给 GRUB 读取的，而不是给 Rust 代码调用的。
         */
        KEEP(*(.multiboot_header))

        /*
         * 收集 entry.S 中的 .boot.text。
         *
         * 真正的 32 位入口 _start 位于这个输入节中。
         * 因为它紧跟在 24 字节的 Multiboot2 header 后面，
         * 所以当前入口通常是 0x100000 + 0x18 = 0x100018。
         */
        *(.boot.text)
    }

    /*
     * 把位置计数器向上对齐到下一个 4 KiB 边界。
     *
     * 4 KiB 是 x86_64 的基础页大小。这样启动代码和主要
     * Rust 代码不会挤在同一个页面中，方便后续设置页表权限。
     */
    . = ALIGN(0x1000);

    /*
     * 收集所有可执行代码。
     *
     * .text   匹配名称恰好为 .text 的输入节；
     * .text.* 匹配 .text.kernel_main 等函数独立节。
     *
     * Rust/LLVM 经常把每个函数放到单独的 .text.* 节中。
     */
    .text :
    {
        *(.text)
        *(.text.*)
    }

    /*
     * 收集只读数据，例如字符串、只读静态变量和常量表。
     *
     * 后续建立正式页表时，这部分应该映射为只读、不可执行。
     */
    .rodata :
    {
        *(.rodata)
        *(.rodata.*)
    }

    /*
     * 收集具有非零初始值的可写全局变量。
     *
     * 这些初始值真实存在于 ELF 文件中，由 GRUB 加载到内存。
     */
    .data :
    {
        *(.data)
        *(.data.*)
    }

    /*
     * 收集零初始化或未初始化的静态数据。
     *
     * NOLOAD 表示这部分只占用运行时内存，不需要在 ELF 文件中
     * 存储大量零字节。ELF 装载信息会记录所需的内存大小。
     */
    .bss (NOLOAD) :
    {
        /*
         * Rust/LLVM 产生的普通 BSS 输入节。
         */
        *(.bss)
        *(.bss.*)

        /*
         * 传统工具链可能产生的 COMMON 符号。
         * Rust 通常不会依赖它，但保留后兼容性更完整。
         */
        *(COMMON)
    }

    /*
     * /DISCARD/ 是链接器的特殊输出节。
     *
     * 放入这里的输入节不会出现在最终 ELF 中。
     */
    /DISCARD/ :
    {
        /*
         * 删除栈展开和异常展开元数据。
         *
         * aa 当前使用 panic = "abort"，不执行 unwinding，
         * 因而暂时不需要 .eh_frame。
         */
        *(.eh_frame)
        *(.eh_frame.*)

        /*
         * 删除编译器版本等说明信息。
         * 这些信息不参与内核运行。
         */
        *(.comment)
    }
}