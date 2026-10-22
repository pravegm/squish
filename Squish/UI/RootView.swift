import SwiftUI

struct RootView: View {
    @State private var director = PressDirector()
    @State private var showTuning = false
    @State private var flashOpacity = 0.0
    @State private var showSafetyHint = false
    @AppStorage("squish.seenSafetyHint") private var seenSafetyHint = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Palette.backdropColor.ignoresSafeArea()

                PressSceneView(director: director)
                    .ignoresSafeArea()
                    .gesture(fallbackPress(height: geometry.size.height),
                             including: director.hingeAvailable ? .none : .all)

                // Failure flash on the top half: on a Duo it physically lights the bottom screen.
                VStack(spacing: 0) {
                    Color.white.opacity(flashOpacity)
                        .frame(height: geometry.size.height / 2)
                    Spacer(minLength: 0)
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)

                PressHints(director: director)

                if director.canChooseObject {
                    VStack {
                        HStack {
                            Spacer()
                            Button {
                                showTuning = true
                            } label: {
                                Image(systemName: "slider.horizontal.3")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Palette.graphiteColor.opacity(0.55))
                                    .padding(10)
                            }
                            .accessibilityLabel("Settings and tuning")
                        }
                        Spacer()
                        ObjectPicker(director: director)
                    }
                    .padding(16)
                    .transition(.opacity)
                }

                if let result = director.revealResult {
                    RevealCardView(result: result, specimenNumber: director.completedPresses) {
                        withAnimation(.spring(duration: 0.4)) { director.next() }
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if director.isShowingCover {
                    CoverView(director: director)
                        .transition(.opacity)
                }

                if showSafetyHint {
                    VStack {
                        Text("Squish is on-screen only. Never close your phone on real things.")
                            .font(.system(.footnote, design: .rounded, weight: .semibold))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(.top, 20)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.45, bounce: 0.25).delay(director.revealResult == nil ? 0 : 0.8),
                       value: director.revealResult)
            .animation(.easeInOut(duration: 0.25), value: director.canChooseObject)
            .animation(.easeInOut(duration: 0.25), value: director.isShowingCover)
        }
        .modifier(HingeReader(
            onUpdate: { angle, closed in director.hingeUpdate(angle: angle, closed: closed) },
            onUnavailable: { director.hingeUnavailable() }
        ))
        .onAppear {
            director.start()
            let demoSuppressesHint = DemoScenario.current.map { $0.name != "launch" } ?? false
            if !seenSafetyHint && !demoSuppressesHint {
                seenSafetyHint = true
                withAnimation { showSafetyHint = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) {
                    withAnimation { showSafetyHint = false }
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { director.sceneBecameActive() }
        }
        .onChange(of: director.failureFlashCount) { _, _ in
            flashOpacity = reduceMotion ? 0.3 : 0.85
            withAnimation(.easeOut(duration: 0.12)) { flashOpacity = 0 }
        }
        .sheet(isPresented: $showTuning) {
            TuningLabView(director: director)
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
    }

    /// Pinch Press fallback for iPhones without a hinge: drag down anywhere to lower the ram.
    private func fallbackPress(height: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                director.virtualPress(max(0, value.translation.height) / max(height * 0.5, 1))
            }
            .onEnded { _ in
                director.virtualRelease()
            }
    }
}

/// Wordless first-press hints: a pulsing chevron on the fold for Duo, a drag hint for the touch fallback.
private struct PressHints: View {
    let director: PressDirector
    @State private var pulse = false

    var body: some View {
        let showHint = director.completedPresses == 0 && director.engine.phase == .armed
            && director.engine.measuredDepth < 0.01 && !director.isShowingCover
        Group {
            if showHint {
                VStack(spacing: 6) {
                    Image(systemName: director.hingeAvailable ? "chevron.compact.down" : "hand.draw")
                        .font(.system(size: 34, weight: .bold))
                    if !director.hingeAvailable {
                        Text("Drag down to press")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    }
                }
                .foregroundStyle(Palette.graphiteColor.opacity(pulse ? 0.55 : 0.15))
                .offset(y: pulse ? 6 : -6)
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { pulse = true }
                }
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showHint)
    }
}

private struct ObjectPicker: View {
    let director: PressDirector

    var body: some View {
        HStack(spacing: 10) {
            ForEach(ObjectKind.allCases) { kind in
                let selected = kind == director.currentKind
                Button {
                    director.choose(kind)
                } label: {
                    Label(kind.displayName, systemImage: kind.symbolName)
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .foregroundStyle(selected ? Palette.graphiteColor : Palette.graphiteColor.opacity(0.6))
                        .background(selected ? Palette.yellowColor : Color.white.opacity(0.7), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
