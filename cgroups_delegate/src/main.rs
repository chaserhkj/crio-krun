use std::{
    fs,
    env,
    io::Write,
    path::Path,
    process::Command,
    os::unix::process::CommandExt,
};

fn main() -> Result<(), Box<dyn std::error::Error>>{
    let args: Vec<String> = env::args().collect();

    if args.len() < 2 {
        return Err("No program to exec given".into());
    }
    let exec = &args[1];
    let exec_args = &args[2..];

    let root_cg = Path::new("/sys/fs/cgroup");
    let init_cg = root_cg.join("init");

    fs::create_dir_all(&init_cg)?;

    let mut procs_file = fs::OpenOptions::new().write(true)
        .open(init_cg.join("cgroup.procs"))?;

    procs_file.write_all(b"1")?;
    drop(procs_file);

    let all_controllers = fs::read_to_string(root_cg.join("cgroup.controllers"))?;
    let mut enable_all_controllers = all_controllers
        .trim_end()
        .split(" ")
        .map(|c| format!("+{}", c))
        .collect::<Vec<_>>()
        .join(" ");
    enable_all_controllers.push('\n');

    let mut subtree_file = fs::OpenOptions::new().write(true)
        .open(root_cg.join("cgroup.subtree_control"))?;
    subtree_file.write_all(enable_all_controllers.as_bytes())?;
    drop(subtree_file);

    let err = Command::new(exec).args(exec_args).exec();

    Err(format!("Failed to exec, errno: {}", err).into())
}
