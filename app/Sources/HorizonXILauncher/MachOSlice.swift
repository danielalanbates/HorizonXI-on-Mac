import Foundation

/// Whether a Mach-O file carries the x86_64 slice Wine runs as under Rosetta. A
/// `DYLD_INSERT_LIBRARIES` that names a missing or wrong-architecture file makes dyld noisy at
/// best and aborts the process at worst, so every interposer/shim checks this before it is used.
/// The header is read directly rather than shelling out to `lipo`, which a Mac without the
/// developer tools does not have.
enum MachOSlice {
    static func hasX86(_ url: URL) -> Bool {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? fh.close() }
        guard let head = try? fh.read(upToCount: 4096), head.count >= 8 else { return false }
        func be32(_ o: Int) -> UInt32 {
            UInt32(head[o]) << 24 | UInt32(head[o + 1]) << 16 | UInt32(head[o + 2]) << 8 | UInt32(head[o + 3])
        }
        func le32(_ o: Int) -> UInt32 {
            UInt32(head[o + 3]) << 24 | UInt32(head[o + 2]) << 16 | UInt32(head[o + 1]) << 8 | UInt32(head[o])
        }
        let cpuTypeX86_64: UInt32 = 0x0100_0007
        let magic = be32(0)
        if magic == 0xCAFE_BABE || magic == 0xCAFE_BABF {          // fat binary
            let count = Int(be32(4)); let entry = magic == 0xCAFE_BABE ? 20 : 32
            for i in 0..<count {
                let off = 8 + i * entry
                guard off + 4 <= head.count else { break }
                if be32(off) == cpuTypeX86_64 { return true }
            }
            return false
        }
        if magic == 0xCFFA_EDFE || magic == 0xCEFA_EDFE { return le32(4) == cpuTypeX86_64 }  // thin
        return false
    }
}
