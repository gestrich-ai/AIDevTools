struct AuthorOption {
    let login: String
    let name: String
    let avatarURL: String?

    init(login: String, name: String, avatarURL: String? = nil) {
        self.login = login
        self.name = name
        self.avatarURL = avatarURL
    }

    var displayLabel: String {
        if name.isEmpty || name == login {
            return login
        }
        return "\(name) (\(login))"
    }
}
