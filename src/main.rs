//! aa 的最小 Rust 内核入口。
//!
//! 当前启动链仍停留在 boot/entry.S 的 32 位 _start：GRUB 可以识别并
//! 进入 aa，但汇编入口还没有建立栈、页表和 64 位执行环境，也没有调用
//! kernel_main。本文件先定义 Rust 侧接口，供后续 long mode 切换完成后接入。
//!
//! 因为 kernel_main 当前没有调用者，链接器启用 section garbage collection
//! 时可能把它移除；现阶段在反汇编中看不到 kernel_main 属于预期结果。

// 裸机目标没有操作系统提供的标准库实现。禁用 std 后仍可使用不依赖操作系统
// 的 core，例如 PanicInfo 和 spin_loop。
#![no_std]
// 禁用 Rust 默认的 main 入口和语言运行时。最终 ELF 的真实入口由 linker.ld
// 中的 ENTRY(_start) 指定，并由 boot/entry.S 提供。
#![no_main]

// global_asm! 在编译期把全局汇编加入当前 crate；它不是运行时函数调用。
use core::arch::global_asm;
// no_std 程序必须自行提供 panic handler；PanicInfo 描述 panic 发生的位置与消息。
use core::panic::PanicInfo;

// include_str! 的路径相对于当前文件 src/main.rs 解析，因此 ../boot/entry.S
// 指向仓库中的启动汇编。options(att_syntax) 声明该文件采用 GNU/AT&T 语法；
// 如果以后加入带操作数的 x86 指令，源和目的操作数顺序必须遵循该语法。
global_asm!(include_str!("../boot/entry.S"), options(att_syntax));

/// 进入 64 位模式后的 Rust 内核入口。
///
/// 汇编代码未来跳转或调用到这里之前，至少必须满足以下契约：
///
/// - CPU 已进入 x86_64 long mode，当前代码和数据所在地址已经正确映射；
/// - 已建立可写、已映射且满足 x86_64 C ABI 对齐规则的栈；
/// - GDT 和段寄存器处于 aa 自己可依赖的状态，方向标志 DF 已清零；
/// - 在 IDT 准备好之前保持中断关闭；
/// - 若以后传入 Multiboot2 信息，参数寄存器布局要与这里声明的 ABI 一致。
///
/// 返回类型 ! 表示该函数永不返回。内核入口没有可返回的上层运行时，因此
/// 后续即使 main loop 退出，也应转入明确的关机、重启或停机路径。
///
/// no_mangle 固定导出符号名为 kernel_main，供汇编按名字引用。Rust 2024
/// 要求用 unsafe(...) 标记这个属性，因为全局符号名的唯一性需要程序员保证。
/// extern "C" 则固定跨汇编边界的调用约定；它不会替调用方检查上述 CPU 状态。
// SAFETY: 整个链接单元只定义这一个 kernel_main 符号；未来汇编调用方必须
// 遵守 extern "C" ABI 以及上面列出的入口状态契约。
#[unsafe(no_mangle)]
pub extern "C" fn kernel_main() -> ! {
    // 这里只是 Rust 侧的临时占位循环。spin_loop 是忙等提示，在 x86_64 上通常
    // 会生成 PAUSE；它不会像 HLT 那样等待中断，也不是内存同步屏障。
    loop {
        core::hint::spin_loop();
    }
}

/// 处理所有无法继续恢复的 Rust panic。
///
/// dev/release 都使用 panic = "abort"，因此 aa 不执行栈展开；但 no_std
/// 可执行程序仍需提供唯一的 panic handler。当前还没有串口或屏幕输出能力，
/// 所以暂时忽略 PanicInfo 并永久忙等，避免 panic 之后落入未知地址。
#[panic_handler]
fn panic(_info: &PanicInfo<'_>) -> ! {
    // 参数名前的下划线表示它在当前阶段被有意保留但尚未使用。串口可用后，
    // 这里应先输出 _info，再进入不会返回的停机循环。
    loop {
        core::hint::spin_loop();
    }
}
