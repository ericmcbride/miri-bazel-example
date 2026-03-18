use core::RawBuffer;

pub fn fill_pattern(buf: &mut RawBuffer, pattern: &[u8]) -> Result<(), &'static str> {
    if pattern.is_empty() {
        return Err("empty pattern");
    }
    for i in 0..buf.len() {
        buf.write_at(i, pattern[i % pattern.len()])?;
    }
    Ok(())
}

pub fn checksum(buf: &RawBuffer) -> Result<u8, &'static str> {
    let mut result: u8 = 0;
    for i in 0..buf.len() {
        result ^= buf.read_at(i)?;
    }
    Ok(result)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_fill_pattern() {
        let mut buf = RawBuffer::new(8);
        fill_pattern(&mut buf, &[0xAA, 0xBB]).unwrap();
        assert_eq!(buf.read_at(0).unwrap(), 0xAA);
        assert_eq!(buf.read_at(1).unwrap(), 0xBB);
        assert_eq!(buf.read_at(2).unwrap(), 0xAA);
        assert_eq!(buf.read_at(3).unwrap(), 0xBB);
    }

    #[test]
    fn test_checksum() {
        let mut buf = RawBuffer::new(4);
        buf.write_at(0, 0xFF).unwrap();
        buf.write_at(1, 0x00).unwrap();
        buf.write_at(2, 0xFF).unwrap();
        buf.write_at(3, 0x00).unwrap();
        assert_eq!(checksum(&buf).unwrap(), 0x00);
    }

    #[test]
    fn test_empty_pattern() {
        let mut buf = RawBuffer::new(4);
        assert!(fill_pattern(&mut buf, &[]).is_err());
    }
}
