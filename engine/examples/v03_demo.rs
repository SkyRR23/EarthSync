use std::io::{self, Read};

fn main() {
    let water = std::env::args().any(|arg| arg == "--water-stdin");
    let input = if water || std::env::args().any(|arg| arg == "--stdin") {
        let mut input = String::new();
        io::stdin().read_to_string(&mut input).expect("read stdin");
        input
    } else {
        include_str!("../tests/fixtures/v03/synthetic_request.json").into()
    };
    println!(
        "{}",
        if water {
            field_shift_engine::v03::water::calculate_json(&input)
        } else {
            field_shift_engine::analyze_v03_json(&input)
        }
    );
}
