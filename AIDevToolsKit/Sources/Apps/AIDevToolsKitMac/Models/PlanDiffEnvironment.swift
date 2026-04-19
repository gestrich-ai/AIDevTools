import LocalDiffService
import SwiftUI

extension EnvironmentValues {
  @Entry var gitWorkingDirectoryMonitor = GitWorkingDirectoryMonitor()
  @Entry var localDiffService = LocalDiffService()
}
