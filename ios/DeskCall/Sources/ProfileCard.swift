import SwiftUI

struct ProfileCard: View {
    let profile: CallerProfile
    @EnvironmentObject private var store: LookupStore
    @State private var reported = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            details
            Divider()
            actions
        }
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 18))
    }

    private var accent: Color {
        profile.isLikelySpam ? .red : .accentColor
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(accent.opacity(0.15))
                Image(systemName: profile.isLikelySpam ? "exclamationmark.triangle.fill" : "person.fill")
                    .font(.title2)
                    .foregroundStyle(accent)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 3) {
                Text(profile.isIdentified ? profile.name : "Unknown Caller")
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                Text(PhoneFormatter.prettyE164(profile.phoneNumber))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(18)
    }

    private var details: some View {
        VStack(spacing: 0) {
            if !profile.title.isEmpty, profile.title != "N/A" {
                row("Title", profile.title, icon: "briefcase")
            }
            if !profile.company.isEmpty, profile.company != "N/A" {
                row("Company", profile.company, icon: "building.2")
            }
            row("Line type", profile.lineType.capitalized, icon: "antenna.radiowaves.left.and.right")
            if !profile.carrier.isEmpty {
                row("Carrier", profile.carrier, icon: "network")
            }
            if profile.spamScore > 0 {
                row("Spam score", "\(profile.spamScore)/100", icon: "shield.lefthalf.filled")
            }
            row("Source", sourceLabel, icon: "arrow.triangle.branch")
        }
        .padding(.vertical, 6)
    }

    private var sourceLabel: String {
        let base: String
        switch profile.source {
        case "mock": base = "Demo data"
        case "telecom": base = "Carrier registry"
        case "b2b": base = "B2B enrichment"
        case "telecom+b2b": base = "Carrier + B2B"
        default: base = "No match"
        }
        return profile.cached ? "\(base) (cached)" : base
    }

    private func row(_ label: String, _ value: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 22)
                .foregroundStyle(.secondary)
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .padding(.horizontal, 18)
        .padding(.vertical, 7)
    }

    private var actions: some View {
        VStack(spacing: 0) {
            if !profile.linkedinURL.isEmpty, let url = URL(string: profile.linkedinURL) {
                Link(destination: url) {
                    actionLabel("Open LinkedIn profile", icon: "link")
                }
            }

            Button {
                store.toggleCallerID(for: profile)
            } label: {
                actionLabel(
                    store.isSavedForCallerID(profile)
                        ? "Remove from phone caller ID"
                        : "Show this name when they call",
                    icon: store.isSavedForCallerID(profile)
                        ? "phone.badge.checkmark"
                        : "phone.badge.plus"
                )
            }

            Button(role: .destructive) {
                reported = true
                Task { await store.reportSpam(profile) }
            } label: {
                actionLabel(reported ? "Reported as spam" : "Report as spam", icon: "flag")
            }
            .disabled(reported)
        }
        .padding(.vertical, 4)
    }

    private func actionLabel(_ text: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).frame(width: 22)
            Text(text)
            Spacer()
        }
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
    }
}
