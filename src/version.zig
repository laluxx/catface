pub const version = "0.7.1";
pub const codename = "Indexed Focus";

pub fn banner() []const u8 {
    return "Catface 0.7.1 Indexed Focus";
}

test "version exists" {
    try @import("std").testing.expect(version.len > 0);
}
