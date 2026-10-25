import SwiftUI

/// Book pose on iPhone Duo: a sheet is centred on the vertical crease and spans both pages. Instead of squeezing
/// everything onto the trailing page (which left the leading page blank, Duo frames 24 Oct), a sheet lays its content
/// out as a spread: one column per page, each scrolling on its own, with nothing on the 40 pt crease.
struct BookSpread<Left: View, Right: View>: View {
    @ViewBuilder var left: Left
    @ViewBuilder var right: Right

    var body: some View {
        GeometryReader { proxy in
            let page = max(0, proxy.size.width / 2 - ScreenBands.creaseHalf)
            HStack(spacing: ScreenBands.creaseHalf * 2) {
                column(left).frame(width: page)
                column(right).frame(width: page)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private func column<Content: View>(_ content: Content) -> some View {
        ScrollView {
            content
                .padding(.horizontal, Theme.s4)
                .padding(.top, Theme.s4)
                .padding(.bottom, Theme.s6)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
    }
}

enum SheetPose {
    /// A sheet lays out as a `BookSpread`: a Duo (a hinge has reported) in book pose (a landscape window).
    static func isBook(hasHinge: Bool, windowIsLandscape: Bool?) -> Bool {
        hasHinge && windowIsLandscape == true
    }
}
