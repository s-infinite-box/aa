/*
 * aa 的 Multiboot2 header 与最小 32 位入口。
 *
 * 当前文件只完成两件事：
 *
 * 1. 向 GRUB 声明“这是一个 Multiboot2 内核”；
 * 2. 提供一个 GRUB 可以跳转到的 32 位入口 _start。
 *
 * 当前版本还不会：
 *
 * - 创建启动栈；
 * - 检查 Multiboot2 magic；
 * - 保存 Multiboot2 信息地址；
 * - 创建 GDT；
 * - 创建页表；
 * - 进入 64 位 long mode；
 * - 调用 Rust kernel_main。
 */


/*
 * 创建名为 .multiboot_header 的输入节。
 *
 * "a" 表示 ALLOC：
 * 该节在内核运行时需要占据内存，因此应包含在 ELF 的装载映像中。
 *
 * 这里没有使用 "x"，因为 header 是供 GRUB 读取的数据，
 * 本身不是需要执行的机器指令。
 *
 * linker.ld 会通过：
 *
 *     KEEP(*(.multiboot_header))
 *
 * 把这个输入节放到最终 ELF 的 .boot 输出节最前面。
 */
.section .multiboot_header, "a"


/*
 * 将接下来的位置对齐到 8 字节边界。
 *
 * Multiboot2 规范要求整个 header：
 *
 * - 按 8 字节对齐；
 * - 完整位于内核文件最前面的 32768 字节中。
 *
 * 如果当前位置尚未对齐，汇编器会自动插入少量填充字节。
 */
.balign 8


/*
 * 记录 Multiboot2 header 的起始位置。
 *
 * 这是文件内部的局部符号，不需要暴露给 Rust 或 GRUB。
 * 后面使用它计算整个 header 的长度。
 */
header_start:


    /*
     * magic：Multiboot2 header 魔数。
     *
     * GRUB 会在内核文件前 32768 字节中搜索这个值，
     * 以判断该文件是否声明了 Multiboot2 启动协议。
     *
     * 注意不要和 GRUB 进入内核时放在 EAX 中的
     * bootloader magic 0x36d76289 混淆：
     *
     * 0xe85250d6：存放在内核文件中的 header magic；
     * 0x36d76289：启动时由 GRUB 放入 EAX 的运行时 magic。
     *
     * .long 写入一个 32 位整数。
     */
    .long 0xe85250d6


    /*
     * architecture：Multiboot2 入口架构。
     *
     * 0 表示 i386 的 32 位保护模式入口；
     * 4 表示 MIPS32。
     *
     * 这里写 0 并不表示 aa 最终是 32 位内核。
     * 它只表示 GRUB 首先以 32 位保护模式进入 _start。
     *
     * aa 随后需要自行建立页表、开启 long mode，
     * 再进入 64 位 Rust kernel_main。
     */
    .long 0


    /*
     * header_length：整个 Multiboot2 header 的字节数。
     *
     * header_end 和 header_start 都是链接/汇编期符号，
     * 汇编器会计算二者之差并将结果写入这里。
     *
     * 当前 header 的组成是：
     *
     * 固定字段：
     *     magic          4 字节
     *     architecture   4 字节
     *     header_length  4 字节
     *     checksum       4 字节
     *
     * end tag：
     *     type           2 字节
     *     flags          2 字节
     *     size           4 字节
     *
     * 总长度：
     *
     *     16 + 8 = 24 字节 = 0x18
     */
    .long header_end - header_start


    /*
     * checksum：header 校验值。
     *
     * Multiboot2 要求下面四个 32 位字段相加后，
     * 按模 2^32 计算必须等于零：
     *
     *     magic
     *   + architecture
     *   + header_length
     *   + checksum
     *   = 0
     *
     * 因此：
     *
     *     checksum =
     *         -(magic + architecture + header_length)
     *
     * 这里的 0 是 architecture 字段。
     * 所有计算都在汇编/链接阶段完成，不会生成运行时代码。
     */
    .long -(0xe85250d6 + 0 + (header_end - header_start))


    /*
     * Multiboot2 header 由若干 tag 组成，并且必须使用
     * type = 0 的 end tag 结束。
     *
     * 通用 tag 头部结构是：
     *
     *     u16 type
     *     u16 flags
     *     u32 size
     */


    /*
     * end tag 的 type。
     *
     * 0 表示整个 Multiboot2 header 到此结束。
     */
    .short 0


    /*
     * end tag 的 flags。
     *
     * end tag 必须使用 0。
     */
    .short 0


    /*
     * end tag 的总大小。
     *
     * type  占 2 字节；
     * flags 占 2 字节；
     * size  占 4 字节；
     *
     * 因此 end tag 总共占 8 字节。
     */
    .long 8


/*
 * 记录 Multiboot2 header 的结束位置。
 *
 * 该符号本身不占用空间，仅用于计算：
 *
 *     header_end - header_start
 */
header_end:


/*
 * 切换到启动代码输入节。
 *
 * linker.ld 会通过：
 *
 *     *(.boot.text)
 *
 * 把它紧接在 Multiboot2 header 后面放入最终的 .boot 输出节。
 *
 * "a" 表示该节需要装入内存；
 * "x" 表示该节包含可执行代码。
 */
.section .boot.text, "ax"


/*
 * 告诉汇编器，接下来应按 32 位指令模式编码。
 *
 * 即使最终文件是 ELF64，GRUB 在普通 Multiboot2 BIOS
 * 启动路径中仍会以 32 位保护模式进入内核。
 *
 * ELF 文件的位数和 CPU 当前执行模式是两个不同概念：
 *
 * - ELF64 描述文件、符号和地址格式；
 * - .code32 决定这里的机器指令如何编码。
 */
.code32


/*
 * 把 _start 导出为全局符号。
 *
 * linker.ld 中的：
 *
 *     ENTRY(_start)
 *
 * 需要找到这个符号，并把它的地址写入 ELF 的入口字段。
 */
.global _start


/*
 * 把 _start 标记为函数符号。
 *
 * 这不是 CPU 执行所必需的，但能够让 readelf、objdump
 * 和 GDB 正确地把 _start 识别为一个函数。
 */
.type _start, @function


/*
 * aa 的第一个机器指令入口。
 *
 * 在 GRUB 跳到这里时，普通 i386 Multiboot2 入口的重要状态是：
 *
 *     EAX = 0x36d76289
 *         表示由兼容 Multiboot2 的加载器启动；
 *
 *     EBX = Multiboot2 information structure 的物理地址；
 *
 *     CR0.PE = 1
 *         已处于 32 位保护模式；
 *
 *     CR0.PG = 0
 *         分页尚未开启；
 *
 *     IF = 0
 *         可屏蔽中断处于关闭状态；
 *
 *     ESP 未定义
 *         不能假设 GRUB 提供了可用栈；
 *
 *     GDTR/IDTR 不可依赖
 *         aa 必须建立自己的 GDT 和 IDT。
 *
 * 因此当前入口绝对不能直接：
 *
 * - push/pop；
 * - call Rust 函数；
 * - 使用局部变量；
 * - 重新加载段寄存器；
 * - 开启中断。
 */
_start:


    /*
     * 再次关闭可屏蔽中断。
     *
     * Multiboot2 规范已经要求 IF 为 0，因此这条指令主要用于：
     *
     * - 明确记录入口不变量；
     * - 防御启动环境与预期不一致；
     * - 防止在 IDT 尚未建立时处理中断。
     */
    cli


/*
 * 数字标签是 GNU 汇编支持的局部标签。
 *
 * 同一个文件中可以多次定义 1:、2: 等数字标签。
 *
 *     1b 表示最近的、位于当前位置之前的 1:；
 *     1f 表示最近的、位于当前位置之后的 1:。
 */
1:


    /*
     * 让 CPU 进入暂停状态。
     *
     * 因为 cli 已经关闭可屏蔽中断，CPU 不会被普通硬件中断唤醒。
     * NMI、SMI 或复位仍可能让 CPU 离开 hlt。
     *
     * 当前版本停在这里是故意的：
     *
     * - 它只验证 GRUB 能识别并进入 _start；
     * - 它还不能进入 64 位 Rust；
     * - 在 QEMU 中看起来会像“卡住”，这是预期现象。
     *
     * 此阶段可以使用 GDB 在 _start 上设置断点验证执行路径。
     */
    hlt


    /*
     * 如果 CPU 因 NMI 等原因离开 hlt，就跳回标签 1，
     * 再次执行 hlt，保证不会意外落入后面的未知内存。
     */
    jmp 1b


/*
 * 记录 _start 函数的长度：
 *
 *     当前地址 - _start 地址
 *
 * 与 .type 类似，这主要用于 ELF 符号表、调试器和反汇编工具，
 * 不会生成额外的运行时代码。
 */
.size _start, . - _start