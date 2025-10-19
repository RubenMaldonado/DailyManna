import XCTest
@testable import DailyManna
import SwiftUI

final class NewTemplateView_CompileTests: XCTestCase {
    func testViewCompiles() {
        _ = NewTemplateView(userId: UUID())
    }
}


