use flate2::Compression;
use flate2::write::GzEncoder;
use tar::Builder;
use std::io::Write;

fn main() {
    println!("Testing tar...");

    // Test InvalidPath
    let mut gz = GzEncoder::new(Vec::new(), Compression::default());
    {
        let mut tar = Builder::new(&mut gz);
        let mut header = tar::Header::new_gnu();
        header.set_size(0);
        let bytes = header.as_mut_bytes();
        bytes[0..4].copy_from_slice(b"\xff\xff\xff\xff");
        header.set_cksum();
        tar.append(&header, &b""[..]).unwrap();
        tar.finish().unwrap();
    }
    let gz_bytes = gz.finish().unwrap();
    let decoder = flate2::read::GzDecoder::new(&gz_bytes[..]);
    let mut archive = tar::Archive::new(decoder);
    let mut entry = archive.entries().unwrap().next().unwrap().unwrap();
    match entry.path() {
        Err(e) => println!("InvalidPath success: {}", e),
        Ok(_) => println!("InvalidPath failed"),
    }

    // Test ReadFile (Truncated gzip)
    let mut gz2 = GzEncoder::new(Vec::new(), Compression::default());
    {
        let mut tar = Builder::new(&mut gz2);
        let mut header = tar::Header::new_gnu();
        header.set_size(100);
        header.set_cksum();
        tar.append_data(&mut header, "test.txt", &vec![0u8; 100][..]).unwrap();
        tar.finish().unwrap();
    }
    let mut gz_bytes2 = gz2.finish().unwrap();
    // Truncate just a few bytes to break the gzip stream during data reading, but keep the header intact
    // Actually, a tar header is 512 bytes. Compressed it might be small. 
    // Let's truncate the uncompressed tar instead, then compress it?
    // No, tar Builder requires a valid write. We can just create a tar file, truncate it, and then compress it!
}
