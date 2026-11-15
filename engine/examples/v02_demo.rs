//! Offline SYNTHETIC TEST DATA, never a crop recommendation or real observation.
fn main() {
    println!(
        "{}",
        field_shift_engine::v02::analyze_v02_json(include_str!(
            "../tests/fixtures/synthetic_v02_request.json"
        ))
    );
}
