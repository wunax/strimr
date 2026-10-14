@testable import Strimr
import Testing

struct ProfileTintTests {
    @Test func `a profile keeps the same tint`() {
        #expect(ProfileTint.index(for: "plex.owner") == 1)
    }

    @Test func `tints spread across the palette`() {
        let indices = Set((0 ..< 64).map { ProfileTint.index(for: "local.\($0)") })

        #expect(indices == Set(ProfileTint.palette.indices))
    }
}
