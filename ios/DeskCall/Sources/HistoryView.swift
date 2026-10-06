import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var store: LookupStore

    var body: some View {
        NavigationStack {
            Group {
                if store.history.isEmpty {
                    ContentUnavailableView(
                        "No lookups yet",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Numbers you look up appear here. This list lives only on this iPhone.")
                    )
                } else {
                    List {
                        Section {
                            ForEach(store.history) { profile in
                                NavigationLink {
                                    ScrollView {
                                        ProfileCard(profile: profile).padding()
                                    }
                                    .background(Color(.systemGroupedBackground))
                                    .navigationTitle("Caller")
                                } label: {
                                    row(profile)
                                }
                            }
                            .onDelete(perform: store.deleteHistory)
                        } footer: {
                            Text("Stored unencrypted-at-rest only inside this app's container, never uploaded.")
                        }
                    }
                }
            }
            .navigationTitle("Recent")
            .toolbar {
                if !store.history.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Clear", role: .destructive) { store.clearHistory() }
                    }
                }
            }
        }
    }

    private func row(_ profile: CallerProfile) -> some View {
        HStack(spacing: 12) {
            Image(systemName: profile.isLikelySpam ? "exclamationmark.triangle.fill" : "person.crop.circle")
                .foregroundStyle(profile.isLikelySpam ? .red : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.isIdentified ? profile.name : "Unknown Caller")
                    .font(.body.weight(.medium))
                Text(PhoneFormatter.prettyE164(profile.phoneNumber))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if store.isSavedForCallerID(profile) {
                Image(systemName: "phone.badge.checkmark")
                    .foregroundStyle(.tint)
                    .font(.caption)
            }
        }
    }
}
