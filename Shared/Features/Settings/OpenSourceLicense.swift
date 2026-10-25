import Foundation

struct OpenSourceLicense: Identifiable, Hashable {
    let name: String
    let license: String
    let url: URL
    /// Names of the `License-<name>.txt` bundle resources, shown one after another.
    let textFiles: [String]

    var id: String {
        name
    }

    var text: String {
        textFiles
            .compactMap { file in
                Bundle.main.url(forResource: "License-\(file)", withExtension: "txt")
                    .flatMap { try? String(contentsOf: $0, encoding: .utf8) }
            }
            .joined(separator: "\n\n")
    }
}

extension OpenSourceLicense {
    static let strimr = OpenSourceLicense(
        name: "Strimr",
        license: "GPL-3.0",
        url: AppInfo.sourceCodeURL,
        textFiles: ["GPL-3.0"],
    )

    static let dependencies: [OpenSourceLicense] = [
        OpenSourceLicense(
            name: "AetherEngine",
            license: "LGPL-3.0",
            url: URL(string: "https://github.com/wunax/AetherEngine")!,
            textFiles: ["AetherEngine"],
        ),
        OpenSourceLicense(
            name: "combine-schedulers",
            license: "MIT",
            url: URL(string: "https://github.com/pointfreeco/combine-schedulers")!,
            textFiles: ["combine-schedulers"],
        ),
        OpenSourceLicense(
            name: "dav1d",
            license: "BSD-2-Clause",
            url: URL(string: "https://code.videolan.org/videolan/dav1d")!,
            textFiles: ["dav1d"],
        ),
        OpenSourceLicense(
            name: "FFmpeg",
            license: "LGPL-2.1",
            url: URL(string: "https://github.com/superuser404notfound/FFmpegBuild")!,
            textFiles: ["LGPL-2.1"],
        ),
        OpenSourceLicense(
            name: "Fontconfig",
            license: "MIT",
            url: URL(string: "https://gitlab.freedesktop.org/fontconfig/fontconfig")!,
            textFiles: ["fontconfig"],
        ),
        OpenSourceLicense(
            name: "FreeType",
            license: "FTL",
            url: URL(string: "https://freetype.org")!,
            textFiles: ["freetype"],
        ),
        OpenSourceLicense(
            name: "FriBidi",
            license: "LGPL-2.1",
            url: URL(string: "https://github.com/fribidi/fribidi")!,
            textFiles: ["LGPL-2.1"],
        ),
        OpenSourceLicense(
            name: "GRDB.swift",
            license: "MIT",
            url: URL(string: "https://github.com/groue/GRDB.swift")!,
            textFiles: ["GRDB"],
        ),
        OpenSourceLicense(
            name: "HarfBuzz",
            license: "Old MIT",
            url: URL(string: "https://github.com/harfbuzz/harfbuzz")!,
            textFiles: ["harfbuzz"],
        ),
        OpenSourceLicense(
            name: "libass",
            license: "ISC",
            url: URL(string: "https://github.com/libass/libass")!,
            textFiles: ["libass"],
        ),
        OpenSourceLicense(
            name: "LibDovi",
            license: "MIT",
            url: URL(string: "https://github.com/superuser404notfound/LibDovi")!,
            textFiles: ["LibDovi"],
        ),
        OpenSourceLicense(
            name: "LibDTSX",
            license: "Apache-2.0, LGPL-2.1",
            url: URL(string: "https://github.com/superuser404notfound/LibDTSX")!,
            textFiles: ["LibDTSX-NOTICE", "Apache-2.0", "LGPL-2.1"],
        ),
        OpenSourceLicense(
            name: "libpng",
            license: "libpng-2.0",
            url: URL(string: "https://github.com/pnggroup/libpng")!,
            textFiles: ["libpng"],
        ),
        OpenSourceLicense(
            name: "LibTrueHD",
            license: "MIT, Apache-2.0",
            url: URL(string: "https://github.com/superuser404notfound/LibTrueHD")!,
            textFiles: ["LibTrueHD", "LibTrueHD-NOTICE", "Apache-2.0"],
        ),
        OpenSourceLicense(
            name: "libzvbi",
            license: "LGPL-2.1, MIT",
            url: URL(string: "https://github.com/zapping-vbi/zvbi")!,
            textFiles: ["LGPL-2.1", "libzvbi-ure"],
        ),
        OpenSourceLicense(
            name: "Sentry",
            license: "MIT",
            url: URL(string: "https://github.com/getsentry/sentry-cocoa")!,
            textFiles: ["Sentry"],
        ),
        OpenSourceLicense(
            name: "SMBClient",
            license: "MIT",
            url: URL(string: "https://github.com/kishikawakatsumi/SMBClient")!,
            textFiles: ["SMBClient"],
        ),
        OpenSourceLicense(
            name: "swift-ass-renderer",
            license: "MIT",
            url: URL(string: "https://github.com/mihai8804858/swift-ass-renderer")!,
            textFiles: ["swift-ass-renderer"],
        ),
        OpenSourceLicense(
            name: "swift-concurrency-extras",
            license: "MIT",
            url: URL(string: "https://github.com/pointfreeco/swift-concurrency-extras")!,
            textFiles: ["swift-concurrency-extras"],
        ),
        OpenSourceLicense(
            name: "swift-libass",
            license: "MIT",
            url: URL(string: "https://github.com/mihai8804858/swift-libass")!,
            textFiles: ["swift-libass"],
        ),
        OpenSourceLicense(
            name: "xctest-dynamic-overlay",
            license: "MIT",
            url: URL(string: "https://github.com/pointfreeco/xctest-dynamic-overlay")!,
            textFiles: ["xctest-dynamic-overlay"],
        ),
        OpenSourceLicense(
            name: "zimg",
            license: "WTFPL",
            url: URL(string: "https://github.com/sekrit-twc/zimg")!,
            textFiles: ["zimg"],
        ),
    ]
}
