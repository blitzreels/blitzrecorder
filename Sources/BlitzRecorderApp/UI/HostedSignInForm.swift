import SwiftUI

/// Email-code sign-in for BlitzRecorder sharing. Centered on empty pages, leading inside panels.
struct HostedSignInForm: View {
    enum Layout { case leading, centered }

    @Bindable var controller: HostedVideoShareController
    let layout: Layout
    @State private var email = ""
    @State private var code = ""
    @State private var shakes = 0
    @FocusState private var focusedField: Field?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private enum Field { case email, code }

    static let width: CGFloat = 300

    private var alignment: HorizontalAlignment { layout == .centered ? .center : .leading }
    private var textAlignment: TextAlignment { layout == .centered ? .center : .leading }
    private var emailIsPlausible: Bool {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        return trimmed.contains("@") && trimmed.contains(".") && trimmed.count >= 5
    }

    var body: some View {
        ZStack(alignment: layout == .centered ? .top : .topLeading) {
            if let challenge = controller.challenge {
                codeStep(challenge)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                            removal: .move(edge: .leading).combined(with: .opacity)))
            } else {
                emailStep
                    .transition(.asymmetric(insertion: .move(edge: .leading).combined(with: .opacity),
                                            removal: .move(edge: .leading).combined(with: .opacity)))
            }
        }
        .frame(maxWidth: Self.width, alignment: layout == .centered ? .top : .topLeading)
        .clipped()
        .animation(reduceMotion ? nil : .smooth(duration: 0.15), value: controller.challenge?.challenge)
        .onChange(of: controller.challenge?.challenge) {
            code = ""
            focusedField = controller.challenge == nil ? .email : .code
        }
        .onChange(of: controller.accountMessage) {
            guard controller.challenge != nil, controller.accountMessage != nil else { return }
            code = ""
            focusedField = .code
            withAnimation(reduceMotion ? nil : .linear(duration: 0.24)) { shakes += 1 }
        }
        .onAppear { focusedField = controller.challenge == nil ? .email : .code }
    }

    private var emailStep: some View {
        VStack(alignment: alignment, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "envelope")
                    .font(BlitzType.symbol(13))
                    .foregroundStyle(focusedField == .email ? BlitzUI.supportingText : BlitzUI.tertiaryText)
                TextField("you@example.com", text: $email)
                    .textFieldStyle(.plain)
                    .font(BlitzType.callout)
                    .textContentType(.emailAddress)
                    .focused($focusedField, equals: .email)
                    .accessibilityLabel("Email address")
                    .onSubmit(requestCode)
                submitArrow
            }
            .padding(.leading, 14)
            .padding(.trailing, 6)
            .frame(height: 44)
            .blitzFieldChrome(isFocused: focusedField == .email)
            .contentShape(.rect)
            .onTapGesture { focusedField = .email }
            message("We’ll email you a sign-in code. No password needed.")
        }
    }

    private var submitArrow: some View {
        let isSending = controller.accountOperation == .sendingCode
        return Button(action: requestCode) {
            ZStack {
                Circle().fill(emailIsPlausible ? BlitzUI.accent : BlitzUI.quietFill)
                if isSending {
                    ProgressView().controlSize(.small).tint(BlitzUI.onAccent)
                } else {
                    Image(systemName: "arrow.right")
                        .font(BlitzType.symbol(13))
                        .foregroundStyle(emailIsPlausible ? BlitzUI.onAccent : BlitzUI.tertiaryText)
                }
            }
            .frame(width: 32, height: 32)
            .animation(.easeOut(duration: 0.1), value: emailIsPlausible)
        }
        .buttonStyle(BlitzPressButtonStyle())
        .disabled(!emailIsPlausible || controller.accountOperation != nil)
        .keyboardShortcut(.defaultAction)
        .accessibilityLabel("Continue with email")
        .help("Continue (Return)")
    }

    private func codeStep(_ challenge: HostedVideoShareController.SignInChallenge) -> some View {
        VStack(alignment: alignment, spacing: 14) {
            VStack(alignment: alignment, spacing: 4) {
                Text("Check your inbox").font(BlitzType.headline)
                Text("Enter the code we sent to \(challenge.email)")
                    .font(BlitzType.body).foregroundStyle(BlitzUI.supportingText)
                    .multilineTextAlignment(textAlignment)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            codeBoxes
                .modifier(Shake(animatableData: CGFloat(shakes)))
            if let error = controller.accountMessage {
                Text(error).font(BlitzType.caption).foregroundStyle(BlitzUI.warning)
                    .multilineTextAlignment(textAlignment)
                    .fixedSize(horizontal: false, vertical: true)
            }
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = max(0, Int(ceil(controller.resendAfter.timeIntervalSince(context.date))))
                HStack(spacing: 6) {
                    Button("Change email", action: controller.changeEmail)
                    Text("·").foregroundStyle(BlitzUI.tertiaryText)
                    Button(remaining > 0 ? "Resend in \(remaining)s" : "Resend code") {
                        Task { await controller.requestCode(email: challenge.email) }
                    }
                    .disabled(remaining > 0)
                }
                .font(BlitzType.caption)
                .foregroundStyle(BlitzUI.secondaryText)
                .buttonStyle(BlitzPressButtonStyle())
                .disabled(controller.accountOperation != nil)
                .monospacedDigit()
            }
        }
    }

    private var codeBoxes: some View {
        let digits = Array(code)
        let isVerifying = controller.accountOperation == .verifyingCode
        return ZStack {
            TextField("", text: $code)
                .textFieldStyle(.plain)
                .textContentType(.oneTimeCode)
                .focused($focusedField, equals: .code)
                .foregroundStyle(.clear)
                .tint(.clear)
                .opacity(0.02)
                .accessibilityLabel("6-digit code")
                .onChange(of: code) {
                    let cleaned = String(code.filter { $0.isASCII && $0.isNumber }.prefix(6))
                    if cleaned != code { code = cleaned }
                    if cleaned.count == 6 { verify() }
                }
            HStack(spacing: 8) {
                ForEach(0..<6, id: \.self) { index in
                    let isCurrent = focusedField == .code && index == min(digits.count, 5) && !isVerifying
                    ZStack {
                        if index < digits.count {
                            Text(String(digits[index]))
                                .font(BlitzType.largeTitle.monospacedDigit())
                                .transition(.scale(scale: 0.6).combined(with: .opacity))
                        } else if isCurrent {
                            Capsule().fill(BlitzUI.accent).frame(width: 2, height: 20)
                                .phaseAnimator([1.0, 0.15]) { caret, opacity in caret.opacity(opacity) }
                                    animation: { _ in .easeInOut(duration: 0.55) }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(BlitzUI.controlFill, in: .rect(cornerRadius: BlitzUI.cardRadius))
                    .overlay {
                        RoundedRectangle(cornerRadius: BlitzUI.cardRadius)
                            .strokeBorder(isCurrent ? BlitzUI.accent.opacity(0.6) : BlitzUI.separator, lineWidth: 1)
                    }
                    .opacity(isVerifying ? 0.5 : 1)
                    .animation(.easeOut(duration: 0.08), value: digits.count)
                }
            }
            .allowsHitTesting(false)
            if isVerifying { ProgressView().controlSize(.small) }
        }
        .frame(maxWidth: Self.width)
        .contentShape(.rect)
        .onTapGesture { focusedField = .code }
    }

    private func message(_ text: String) -> some View {
        Group {
            if let error = controller.accountMessage {
                Text(error).foregroundStyle(BlitzUI.warning)
            } else {
                Text(text).foregroundStyle(BlitzUI.secondaryText)
            }
        }
        .font(BlitzType.caption)
        .multilineTextAlignment(textAlignment)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func requestCode() {
        guard emailIsPlausible else { return }
        Task { await controller.requestCode(email: email) }
    }

    private func verify() {
        guard code.count == 6, controller.accountOperation == nil else { return }
        Task { await controller.verifyCode(code) }
    }
}

private struct Shake: GeometryEffect {
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 8 * sin(animatableData * .pi * 4), y: 0))
    }
}
