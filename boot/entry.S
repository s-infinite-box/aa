/*****************************************************
 * aa 的 Multiboot2 header 与最小 32 位启动环境。
 * cat entry.S | grep -v '^ *\*' | grep -v ' *\/\*' | grep  -v '^$' | cat -n
 * 当前文件完成这些工作：
 * 1. 向 GRUB 声明“这是一个 Multiboot2 内核”；
 * 2. 提供一个 GRUB 可以跳转到的 32 位入口 _start；
 * 3. 保存 GRUB 交付的 Multiboot2 参数；
 * 4. 清除方向标志并建立 aa 自己的启动栈；
 * 5. 在 long mode 尚未建立时安全停机。
 *****************************************************/

/*
 * 创建名为 .multiboot_header 的输入节。
 * "a" 表示 ALLOC：
 * 该节在内核运行时需要占据内存，因此应包含在 ELF 的装载映像中。
 * linker.ld 会通过：
 *     KEEP(*(.multiboot_header))
 * 把这个输入节放到最终 ELF 的 .boot 输出节最前面。
 */
.section .multiboot_header, "a"

/*
 * 将接下来的位置对齐到 8 字节边界。
 * Multiboot2 规范要求整个 header：
 * - 按 8 字节对齐；
 * - 完整位于内核文件最前面的 32768 字节中。
 */
.balign 8


/*
 * 记录 Multiboot2 header 的起始位置。
 */
header_start:

    /*
     * magic：Multiboot2 header 魔数。
     * GRUB 会在内核文件前 32768 字节中搜索这个值，
     * 以判断该文件是否声明了 Multiboot2 启动协议。
     * .long 写入一个 32 位整数。
     */
    .long 0xe85250d6


    /*
     * architecture：Multiboot2 入口架构。
     * 0 表示 i386 的 32 位保护模式入口；
     * 4 表示 MIPS32。
     * 这里写 0 并不表示 aa 最终是 32 位内核。
     * 它只表示 GRUB 首先以 32 位保护模式进入 _start。
     * aa 随后需要自行建立页表、开启 long mode，
     * 再进入 64 位 Rust kernel_main。
     */
    .long 0


    /*
     * header_length：整个 Multiboot2 header 的字节数。
     * header_end 和 header_start 都是链接/汇编期符号，
     * 汇编器会计算二者之差并将结果写入这里。
     * 当前 header 的组成是：
     * 固定字段：
     *     magic          4 字节
     *     architecture   4 字节
     *     header_length  4 字节
     *     checksum       4 字节
     * end tag：
     *     type           2 字节
     *     flags          2 字节
     *     size           4 字节
     * 总长度：
     *     16 + 8 = 24 字节 = 0x18
     */
    .long header_end - header_start


    /*
     * checksum：header 校验值。
     * Multiboot2 要求下面四个 32 位字段相加后，
     * 按模 2^32 计算必须等于零：
     *     magic
     *   + architecture
     *   + header_length
     *   + checksum
     *   = 0
     * 因此：
     *     checksum =
     *         -(magic + architecture + header_length)
     * 这里的 0 是 architecture 字段。
     * 所有计算都在汇编/链接阶段完成，不会生成运行时代码。
     */
    .long -(0xe85250d6 + 0 + (header_end - header_start))


    /*
     * Multiboot2 header 由若干 tag 组成，并且必须使用
     * type = 0 的 end tag 结束。
     * 通用 tag 头部结构是：
     *     u16 type
     *     u16 flags
     *     u32 size
     */


    /*
     * end tag 的 type。
     * 0 表示整个 Multiboot2 header 到此结束。
     */
    .short 0


    /*
     * end tag 的 flags。
     * end tag 必须使用 0。
     */
    .short 0


    /*
     * end tag 的总大小。
     * type  占 2 字节；
     * flags 占 2 字节；
     * size  占 4 字节；
     * 因此 end tag 总共占 8 字节。
     */
    .long 8


/*
 * 记录 Multiboot2 header 的结束位置。
 * 该符号本身不占用空间，仅用于计算：
 *     header_end - header_start
 */
header_end:


/*
 * 切换到启动代码输入节。
 * linker.ld 会通过：
 *     *(.boot.text)
 * 把它紧接在 Multiboot2 header 后面放入最终的 .boot 输出节。
 * "a" 表示该节需要装入内存；
 * "x" 表示该节包含可执行代码。
 */
.section .boot.text, "ax"


/*
 * 告诉汇编器，接下来应按 32 位指令模式编码。
 * 即使最终文件是 ELF64，GRUB 在普通 Multiboot2 BIOS
 * 启动路径中仍会以 32 位保护模式进入内核。
 * ELF 文件的位数和 CPU 当前执行模式是两个不同概念：
 * - ELF64 描述文件、符号和地址格式；
 * - .code32 决定这里的机器指令如何编码。
 */
.code32


/*
 * 把 _start 导出为全局符号。
 * linker.ld 中的：
 *     ENTRY(_start)
 * 需要找到这个符号，并把它的地址写入 ELF 的入口字段。
 */
.global _start


/*
 * 把 _start 标记为函数符号。
 * 这不是 CPU 执行所必需的，但能够让 readelf、objdump
 * 和 GDB 正确地把 _start 识别为一个函数。
 */
.type _start, @function


/*
 * aa 的第一个机器指令入口。
 * 在 GRUB 跳到这里时，普通 i386 Multiboot2 入口的重要状态是：
 *     EAX = 0x36d76289
 *         表示由兼容 Multiboot2 的加载器启动；
 *     EBX = Multiboot2 information structure 的物理地址；
 *     CR0.PE = 1
 *         已处于 32 位保护模式；
 *     CR0.PG = 0
 *         分页尚未开启；
 *     IF = 0
 *         可屏蔽中断处于关闭状态；
 *     ESP 未定义
 *         不能假设 GRUB 提供了可用栈；
 *     GDTR/IDTR 不可依赖
 *         aa 必须建立自己的 GDT 和 IDT。
 * 因此当前入口绝对不能直接：
 * - push/pop；
 * - call Rust 函数；
 * - 使用局部变量；
 * - 重新加载段寄存器；
 * - 开启中断。
 */
_start:


    /*
     * 再次关闭可屏蔽中断。
     * Multiboot2 规范已经要求 IF 为 0，因此这条指令主要用于：
     * - 明确记录入口不变量；
     * - 防御启动环境与预期不一致；
     * - 防止在 IDT 尚未建立时处理中断。
     * 全称是 Clear Interrupt Flag，即清除中断标志。它的作用等价于：
     *  EFLAGS.IF = 0
     *  执行后，CPU 暂时不响应普通的可屏蔽硬件中断。
     */
    cli


    /*
     * 清除方向标志 DF。
     * GRUB 不保证 DF 的入口值；Rust、C ABI 和普通字符串操作都要求
     * DF 为 0。必须在进入任何高级语言代码前主动建立这个不变量。
     */
    cld


    /*
     * 保存 GRUB 交付的 Multiboot2 参数。
     *     EAX = Multiboot2 启动魔数 0x36d76289；
     *     EBX = Multiboot2 information structure 的物理地址。
     * 此时 ESP 仍未初始化，所以不能用 push 或 call。linker.ld 已在
     * 可写的 .bss 中预留两个 32 位位置，这里直接按绝对地址写入。
     */
    movl %eax, multiboot_magic
    movl %ebx, multiboot_info

    /*
     * 建立 aa 自己的 32 位启动栈。
     * boot_stack_top 是 linker.ld 导出的地址，因此这里必须使用
     * `$boot_stack_top` 取得地址本身。若省略 `$`，含义会变成读取
     * boot_stack_top 地址中的内容。
     * x86 栈向低地址增长，所以初始 ESP 指向预留区域的末端。
     * boot_stack_top 按 4 KiB 对齐，也满足后续 ABI 的 16 字节对齐。
     */
    movl $boot_stack_top, %esp


    /*
     * 清空 GRUB 遗留的帧指针。
     * 这样 GDB 做栈回溯时，不会把 GRUB 的旧 EBP 链误认为 aa 的
     * 调用栈。当前还没有真正的函数调用帧，因此零是明确的终点。
     */
    xorl %ebp, %ebp


/*
 * 导出第一个可动态验证的启动检查点。
 * 到达 boot_environment_ready 时，下列操作都已经完成：
 * - EAX/EBX 已保存到 .bss；
 * - DF 已清零；
 * - ESP 已指向 boot_stack_top；
 * - EBP 已清零。
 * 该符号主要供 GDB 设置断点，不会生成额外机器指令。
 */
.global boot_environment_ready
boot_environment_ready:

    /*
     * 比较保存区中的 32 位值与 Multiboot2 运行时 magic。
     * cmp 不修改保存值，只更新 EFLAGS 中的条件标志。
     */
    cmpl $0x36d76289, multiboot_magic

    /* 不相等时跳到失败路径；相等时继续执行下面的代码。 */
    jne boot_bad_multiboot

/* 成功检查点：只有 magic 正确，才会顺序执行到这里。 */
.global multiboot_magic_ok
multiboot_magic_ok:

/*
 * 数字标签是 GNU 汇编支持的局部标签。
 * 同一个文件中可以多次定义 1:、2: 等数字标签。
 *     1b 表示最近的、位于当前位置之前的 1:；
 *     1f 表示最近的、位于当前位置之后的 1:。
 */
1:


    /*
     * 让 CPU 进入暂停状态。
     * 因为 cli 已经关闭可屏蔽中断，CPU 不会被普通硬件中断唤醒。
     * NMI、SMI 或复位仍可能让 CPU 离开 hlt。
     * 当前版本停在这里是故意的：
     * - 它验证 GRUB 能识别并进入 _start；
     * - 它保存了 Multiboot2 参数并建立了 aa 的启动栈；
     * - 它还不能进入 64 位 Rust；
     * - 在 QEMU 中看起来会像“卡住”，这是预期现象。
     * 此阶段可以使用 GDB 在 _start 上设置断点验证执行路径。
     */
    hlt


    /*
     * 如果 CPU 因 NMI 等原因离开 hlt，就跳回标签 1，
     * 再次执行 hlt，保证不会意外落入后面的未知内存。
     */
    jmp 1b

/* 失败检查点：启动标识不符合预期，不能继续初始化。 */
.global boot_bad_multiboot
boot_bad_multiboot:
    cli

    /*
     * 保持可屏蔽中断关闭并停机。
     * 若 hlt 被其他事件唤醒，继续回到停机指令。
     */
2:
    hlt
    jmp 2b

/*
 * 记录 _start 函数的长度：
 *     当前地址 - _start 地址
 * 与 .type 类似，这主要用于 ELF 符号表、调试器和反汇编工具，
 * 不会生成额外的运行时代码。
 */
.size _start, . - _start
