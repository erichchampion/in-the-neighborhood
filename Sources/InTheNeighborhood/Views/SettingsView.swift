import SwiftUI
import LLMIntegration

struct SettingsView: View {
    @StateObject private var settingsManager = SettingsManager.shared
    @ObservedObject private var downloadManager = LLMModelDownloadManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showAddDomainAlert = false
    @State private var newDomain = ""
    @State private var showDomainError = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section("AI Model") {
                    Picker("Query enhancement model", selection: $settingsManager.selectedModelID) {
                        ForEach(LLMModelCatalog.shared.recommendedModels, id: \.id) { modelConfig in
                            Text("\(modelConfig.id.displayName) (\(modelConfig.fileSizeDescription))")
                                .tag(modelConfig.id)
                        }
                    }
                    if !downloadManager.isModelAvailable(for: settingsManager.selectedModelID) {
                        if downloadManager.downloadState == .downloading {
                            VStack(alignment: .leading, spacing: 4) {
                                ProgressView(value: downloadManager.downloadProgress)
                                Text("Downloading: \(Int(downloadManager.downloadProgress * 100))%")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } else if downloadManager.downloadState == .failed {
                            Text("Download failed. Please try again.")
                                .font(.caption)
                                .foregroundColor(.red)
                            Button("Download") {
                                Task {
                                    try? await downloadManager.startDownload(for: settingsManager.selectedModelID)
                                }
                            }
                        } else {
                            HStack {
                                Text("Not downloaded")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Button("Download") {
                                    Task {
                                        try? await downloadManager.startDownload(for: settingsManager.selectedModelID)
                                    }
                                }
                            }
                        }
                    }
                }
                
                Section("Deny List") {
                    ForEach(settingsManager.denyList.allDeniedDomains, id: \.self) { domain in
                        HStack {
                            Text(domain)
                            Spacer()
                            Button("Remove") {
                                settingsManager.removeDenyDomain(domain)
                            }
                            .foregroundColor(.red)
                            .accessibilityLabel("Remove \(domain) from deny list")
                            .accessibilityHint("Removes this domain from the blocked list")
                        }
                    }
                    
                    Button("Add Domain") {
                        showAddDomainAlert = true
                    }
                    .accessibilityLabel("Add domain to deny list")
                    .accessibilityHint("Add a domain to block from search results")
                    .alert("Add Domain to Deny List", isPresented: $showAddDomainAlert) {
                        TextField("example.com", text: $newDomain)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                        Button("Cancel", role: .cancel) {
                            newDomain = ""
                        }
                        Button("Add") {
                            if validateDomain(newDomain) {
                                settingsManager.addDenyDomain(newDomain.lowercased())
                                newDomain = ""
                            } else {
                                showDomainError = true
                            }
                        }
                    } message: {
                        Text("Enter a domain to block from search results (e.g., example.com)")
                    }
                    .alert("Invalid Domain", isPresented: $showDomainError) {
                        Button("OK", role: .cancel) {
                            newDomain = ""
                        }
                    } message: {
                        Text("Please enter a valid domain name (e.g., example.com)")
                    }
                }
                
                Section("Search Radius") {
                    Picker("Radius", selection: $settingsManager.searchRadius) {
                        Text("5 miles").tag(8047.0) // meters
                        Text("10 miles").tag(16093.0)
                        Text("25 miles").tag(40234.0)
                        Text("50 miles").tag(80467.0)
                    }
                }
                
                Section("Privacy") {
                    Button("Clear Search History") {
                        settingsManager.clearSearchHistory()
                    }
                    .foregroundColor(.red)
                    .accessibilityLabel("Clear search history")
                    .accessibilityHint("Clears all stored search history data")
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .accessibilityLabel("Done")
                    .accessibilityHint("Closes settings")
                }
            }
        }
    }
    
    private func validateDomain(_ domain: String) -> Bool {
        // Basic domain validation - should be a valid domain format
        let trimmed = domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return false }
        
        // Basic regex for domain validation (allows domains like example.com, sub.example.com)
        let domainPattern = #"^([a-z0-9]([a-z0-9\-]{0,61}[a-z0-9])?\.)+[a-z]{2,}$"#
        let regex = try? NSRegularExpression(pattern: domainPattern, options: .caseInsensitive)
        let range = NSRange(location: 0, length: trimmed.utf16.count)
        return regex?.firstMatch(in: trimmed, options: [], range: range) != nil
    }
}
