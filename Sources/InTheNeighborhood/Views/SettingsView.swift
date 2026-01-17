import SwiftUI

struct SettingsView: View {
    @StateObject private var settingsManager = SettingsManager.shared
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Deny List") {
                    ForEach(settingsManager.denyList.allDeniedDomains, id: \.self) { domain in
                        HStack {
                            Text(domain)
                            Spacer()
                            Button("Remove") {
                                settingsManager.removeDenyDomain(domain)
                            }
                            .foregroundColor(.red)
                        }
                    }
                    
                    Button("Add Domain") {
                        // TODO: Show add domain dialog
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
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
