use std::io::{self, Read};

fn main() {
    let input = if std::env::args().any(|arg| arg == "--stdin") {
        let mut input = String::new();
        io::stdin().read_to_string(&mut input).expect("read stdin");
        input
    } else {
        include_str!("../tests/fixtures/v03/synthetic_request.json").into()
    };
    println!("{}", field_shift_engine::analyze_v03_json(&input));
}
