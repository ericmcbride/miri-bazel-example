use core::RawBuffer;
use utils::{checksum, fill_pattern};

fn main() {
    let mut buf = RawBuffer::new(32);
    fill_pattern(&mut buf, &[0xDE, 0xAD, 0xBE, 0xEF]).unwrap();

    let cs = checksum(&buf).unwrap();
    println!("Buffer checksum: 0x{:02X}", cs);
    println!("Buffer size: {}", buf.len());
}
