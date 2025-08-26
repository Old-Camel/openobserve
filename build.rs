use std::fs;
use std::io::Read;
use std::path::{Path, PathBuf};

fn main() {
    let dist_dir = Path::new("web/dist");

    // 确保对目录变更敏感
    println!("cargo:rerun-if-changed=web/dist");

    let mut file_list: Vec<PathBuf> = Vec::new();
    if dist_dir.exists() {
        collect_files_recursively(dist_dir, &mut file_list);
        // 排序保证哈希稳定
        file_list.sort();
        for path in &file_list {
            if let Some(p) = path.to_str() {
                println!("cargo:rerun-if-changed={}", p);
            }
        }
    }

    let web_dist_hash = if file_list.is_empty() {
        "no-dist".to_string()
    } else {
        // 先对每个文件做 sha256，再汇总做一次 sha256
        let mut parts = String::new();
        for path in &file_list {
            match fs::File::open(path) {
                Ok(mut f) => {
                    let mut buf = Vec::new();
                    if f.read_to_end(&mut buf).is_ok() {
                        let h = sha256::digest(buf);
                        parts.push_str(path.to_string_lossy().as_ref());
                        parts.push(':');
                        parts.push_str(&h);
                        parts.push('\n');
                    }
                }
                Err(_) => {}
            }
        }
        sha256::digest(parts)
    };

    // 注入到编译环境；改变即触发根 crate 重编
    println!("cargo:rustc-env=WEB_DIST_HASH={}", web_dist_hash);
    // 同时注入一个 cfg，进一步确保指纹变化
    println!("cargo:rustc-cfg=web_dist_hash=\"{}\"", web_dist_hash);
}

fn collect_files_recursively(dir: &Path, out: &mut Vec<PathBuf>) {
    if let Ok(entries) = fs::read_dir(dir) {
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_dir() {
                collect_files_recursively(&path, out);
            } else if path.is_file() {
                out.push(path);
            }
        }
    }
}


