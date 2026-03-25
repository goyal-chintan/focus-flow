import XCTest
@testable import FocusFlow

final class ProjectBlockingProfilesTests: XCTestCase {
    func testEffectiveBlockProfilesIncludeLegacySingleProfileWithoutDuplication() {
        let project = Project(name: "Interview Prep")
        let legacy = BlockProfile(name: "Legacy", websites: ["youtube.com"])
        let multi = BlockProfile(name: "Multi", websites: ["reddit.com"])

        project.blockProfile = legacy
        project.blockProfiles = [multi, legacy]

        let effective = project.effectiveBlockProfiles
        XCTAssertEqual(effective.count, 2)
        XCTAssertTrue(effective.contains(where: { $0.id == legacy.id }))
        XCTAssertTrue(effective.contains(where: { $0.id == multi.id }))
    }

    func testMergedBlockedTargetsUnionAcrossMultipleProfiles() {
        let project = Project(name: "Deep Work")
        let p1 = BlockProfile(
            name: "Web",
            websites: ["youtube.com", "reddit.com"],
            apps: ["com.tinyspeck.slackmacgap"]
        )
        let p2 = BlockProfile(
            name: "Apps+Web",
            websites: ["reddit.com", "x.com"],
            apps: ["com.tinyspeck.slackmacgap", "com.openai.chatgpt"]
        )

        project.blockProfiles = [p1, p2]

        XCTAssertEqual(project.mergedBlockedWebsites, Set(["youtube.com", "reddit.com", "x.com"]))
        XCTAssertEqual(project.mergedBlockedApps, Set(["com.tinyspeck.slackmacgap", "com.openai.chatgpt"]))
    }
}
