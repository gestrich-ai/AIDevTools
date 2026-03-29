import ArgumentParser
import ClaudeChainCLI

@main struct ClaudeChainMain {
    static func main() async {
        await ClaudeChainCLI.main()
    }
}
