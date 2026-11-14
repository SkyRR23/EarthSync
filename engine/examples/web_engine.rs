use std::io::{self, Read};

fn main() {
    let mut input = String::new();
    io::stdin()
        .read_to_string(&mut input)
        .expect("read request");
    let output = if std::env::args().any(|arg| arg == "--v02") {
        field_shift_engine::v02::analyze_v02_json(&input)
    } else {
        field_shift_engine::integration::analyze_integration_json(&input)
    };
    println!("{output}");
}
