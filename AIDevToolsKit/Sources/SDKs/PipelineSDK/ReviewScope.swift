public enum ReviewScope: Sendable {
    case allSinceLastReview
    case lastN(Int)
    case stepIDs([String])
}