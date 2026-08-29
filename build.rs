//! aa 的 Cargo 构建脚本。
//!
//! 这个程序在宿主机上、编译内核之前运行；它不会被链接进 aa，也不会在
//! QEMU 中执行。打印到标准输出的 cargo: 指令用于向 Cargo 声明额外依赖。

fn main() {
    /*
     * linker.ld 通过 rustflags 传给链接器，不是普通 Rust 源文件。
     * Cargo 默认不知道它会影响最终产物；显式声明依赖后，修改链接脚本
     * 就会触发重新构建和链接，避免继续使用旧的 ELF 布局。
     */
    println!("cargo:rerun-if-changed=boot/linker.ld");

    /*
     * entry.S 通过 include_str!/global_asm! 引入，rustc 通常能够追踪；
     * 这里仍显式声明，使构建依赖关系更加清晰，也让两份启动输入文件
     * 使用相同的重建规则。
     */
    println!("cargo:rerun-if-changed=boot/entry.S");
}
