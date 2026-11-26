// 由 scripts/generate-tencent-live-license.mjs 从 adapters/live-cdn/shared/tencent-live-license.js 生成，勿手改。

enum TencentLiveLicense {
    static let url = "https://1355434317.trtcube-license.cn/license/v2/1355434317_1/v_cube.license"
    static let key = "cece2ce34041618af681aca0256e5182"

    static func resolve(url: String, key: String) -> (url: String, key: String) {
        (
            url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Self.url : url,
            key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Self.key : key
        )
    }
}
