fn main() {
    /*
     * linker.ld 通过 rustflags 传给链接器，不是普通 Rust 源文件。
     * 显式声明依赖后，修改链接脚本会触发重新构建和链接。
     */
    println!("cargo:rerun-if-changed=boot/linker.ld");

    /*
     * entry.S 通过 include_str!/global_asm! 引入，rustc 通常能够追踪；
     * 这里仍显式声明，使构建依赖关系更加清晰。
     */
    println!("cargo:rerun-if-changed=boot/entry.S");
}