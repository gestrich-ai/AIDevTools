public struct AppSettings: Codable, Sendable {
    public var userPhotoFilename: String?

    public init(userPhotoFilename: String? = nil) {
        self.userPhotoFilename = userPhotoFilename
    }
}
