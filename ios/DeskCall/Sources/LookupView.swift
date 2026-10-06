import SwiftUI

struct LookupView: View {
    @EnvironmentObject private var store: LookupStore
    @State private var input = ""
    @State private var profile: CallerProfile?
    @FocusState private var fieldFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    entryCard

                    if let profile {
                        ProfileCard(profile: profile)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else if !store.isLoading {
                        placeholder
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("DeskCall")
            .animation(.snappy, value: profile)
            .alert("Lookup failed", isPresented: errorBinding) {
                Button("OK") { store.lastError = nil }
            } message: {
                Text(store.lastError ?? "")
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { store.lastError != nil },
                set: { if !$0 { store.lastError = nil } })
    }

    private var entryCard: some View {
        VStack(spacing: 14) {
            TextField("(415) 555-1234", text: $input)
                .textFieldStyle(.plain)
                .font(.system(size: 30, weight: .medium, design: .rounded))
                .multilineTextAlignment(.center)
                .keyboardType(.phonePad)
                .focused($fieldFocused)
                .onChange(of: input) { _, new in
                    input = PhoneFormatter.formatForDisplay(new)
                }

            Divider()

            Button {
                fieldFocused = false
                Task { profile = await store.lookup(input) }
            } label: {
                HStack {
                    if store.isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "magnifyingglass")
                    }
                    Text(store.isLoading ? "Looking up…" : "Identify caller")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(store.isLoading || PhoneFormatter.digits(input).count < 7)
        }
        .padding(20)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 18))
    }

    private var placeholder: some View {
        VStack(spacing: 10) {
            Image(systemName: "lock.shield")
                .font(.system(size: 34))
                .foregroundStyle(.tint)
            Text("Your contacts stay on your phone")
                .font(.headline)
            Text("DeskCall never asks for address-book access. Only the number you type is sent, and results expire after 24 hours.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 40)
        .padding(.horizontal)
    }
}
