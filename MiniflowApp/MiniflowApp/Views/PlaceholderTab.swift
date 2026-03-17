import SwiftUI

struct PlaceholderTab: View {
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.custom("GeistPixel-Square", size: 28))
                .foregroundStyle(Color.black)
            Text("Coming soon.")
                .font(.system(size: 14))
                .foregroundStyle(Color.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(28)
    }
}
