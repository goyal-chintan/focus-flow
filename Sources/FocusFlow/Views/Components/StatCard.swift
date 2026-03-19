import SwiftUI

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        LiquidMetricCard(
            title: title,
            value: value,
            icon: icon,
            color: color
        )
    }
}
