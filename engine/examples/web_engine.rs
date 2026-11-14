use std::io::{self, Read};

fn main() {
    let mut input = String::new();
    io::stdin()
        .read_to_string(&mut input)
        .expect("read request");
    let args: Vec<String> = std::env::args().skip(1).collect();
    let output = if args == ["--v03"] {
        field_shift_engine::v03::analyze_v03_json(&input)
    } else if args == ["--v02"] {
        field_shift_engine::v02::analyze_v02_json(&input)
    } else if args.is_empty() {
        field_shift_engine::integration::analyze_integration_json(&input)
    } else {
        eprintln!("Unknown interface; use no flag, --v02 or --v03");
        std::process::exit(2);
    };
    println!("{output}");
}
