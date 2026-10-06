import SwiftUI

/// Controls what iOS itself shows while the phone is ringing.
struct DirectoryView: View {
    @EnvironmentObject private var store: LookupStore

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(store.directoryStatus)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Button {
                        Task { await store.syncCallerID() }
                    } label: {
                        HStack {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("Sync to iPhone caller ID")
                            Spacer()
                            if store.isLoading { ProgressView().controlSize(.small) }
                        }
                    }
                    .disabled(store.isLoading)
                } header: {
                    Text("System integration")
                } footer: {
                    Text("Syncing hands your saved names and the spam blocklist to iOS. "
                         + "Enable DeskCall under Settings ▸ Apps ▸ Phone ▸ Call Blocking & Identification first.")
                }

                Section {
                    if store.savedForCallerID.isEmpty {
                        Text("Nothing saved yet. Look up a number, then tap \"Show this name when they call\".")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(store.savedForCallerID, id: \.number) { entry in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.label).font(.body)
                                Text(PhoneFormatter.prettyE164("+\(entry.number)"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .onDelete(perform: store.removeFromCallerID)
                    }
                } header: {
                    Text("Names shown while ringing (\(store.savedForCallerID.count))")
                }

                if !store.appGroupAvailable {
                    Section {
                        Label("App Group unavailable", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Text("This build was signed without an App Group entitlement, which is normal for a free Apple ID. "
                             + "Spam blocking still works — the extension downloads that list itself — but saved names "
                             + "can't cross into the system extension. See SIDELOADING.md for the paid-account steps.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Caller ID")
            .task { await store.refreshExtensionStatus() }
        }
    }
}
