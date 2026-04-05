import CoreGraphics

enum CompanionAnalyticsCaptureAvailabilityResolver {
    static func resolve(
        frontmostBundleId: String?,
        screenCaptureAccessGranted: Bool = CGPreflightScreenCaptureAccess()
    ) -> CompanionAnalyticsCaptureAvailability {
        guard let frontmostBundleId,
              AppUsageEntry.isBrowserBundleIdentifier(frontmostBundleId) else {
            return .available
        }

        guard BrowserDomainResolver.supports(bundleIdentifier: frontmostBundleId) == false else {
            return .available
        }

        return screenCaptureAccessGranted ? .available : .unavailable
    }
}
