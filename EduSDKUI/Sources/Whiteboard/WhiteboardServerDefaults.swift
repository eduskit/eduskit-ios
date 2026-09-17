/// DrawsKit Room API 默认走正式环境；私有部署由 `WhiteboardConfig` 覆盖。
public enum WhiteboardServerDefaults {
    public static let environment = "production"
    public static let configKeyEnvironment = "serverEnvironment"
    public static let configKeyCustomServer = "customServerConfig"
    public static let configKeyServerHost = "serverHost"
}
