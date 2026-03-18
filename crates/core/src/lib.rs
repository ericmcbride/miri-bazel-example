pub struct RawBuffer {
    data: Vec<u8>,
}

impl RawBuffer {
    pub fn new(size: usize) -> Self {
        Self {
            data: vec![0u8; size],
        }
    }

    /// Safe write via pointer.
    pub fn write_at(&mut self, offset: usize, value: u8) -> Result<(), &'static str> {
        if offset >= self.data.len() {
            return Err("offset out of bounds");
        }
        let ptr = self.data.as_mut_ptr();
        unsafe {
            *ptr.add(offset) = value;
        }
        Ok(())
    }

    /// Safe read via pointer.
    pub fn read_at(&self, offset: usize) -> Result<u8, &'static str> {
        if offset >= self.data.len() {
            return Err("offset out of bounds");
        }
        let ptr = self.data.as_ptr();
        Ok(unsafe { *ptr.add(offset) })
    }

    pub fn len(&self) -> usize {
        self.data.len()
    }

    pub fn is_empty(&self) -> bool {
        self.data.is_empty()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_write_read() {
        let mut buf = RawBuffer::new(16);
        buf.write_at(0, 0xAB).unwrap();
        buf.write_at(15, 0xCD).unwrap();
        assert_eq!(buf.read_at(0).unwrap(), 0xAB);
        assert_eq!(buf.read_at(15).unwrap(), 0xCD);
    }

    #[test]
    fn test_bounds_check() {
        let buf = RawBuffer::new(4);
        assert!(buf.read_at(4).is_err());
        assert!(buf.read_at(100).is_err());
    }

    #[test]
    fn test_zero_initialized() {
        let buf = RawBuffer::new(8);
        for i in 0..8 {
            assert_eq!(buf.read_at(i).unwrap(), 0);
        }
    }

    /// This test passes normally but Miri catches the undefined behavior.
    /// Creating two mutable references to the same data is UB.
    #[test]
    fn test_aliasing_violation() {
        let mut data: u32 = 1;
        let ptr = &mut data as *mut u32;
        let ref1 = unsafe { &mut *ptr };
        let ref2 = unsafe { &mut *ptr };
        *ref1 = 10;
        *ref2 = 20;
        assert_eq!(data, 20);
    }
}
