//
//  outboundApp.swift
//  outbound
//
//  Created by Sun Chen on 10/9/26.
//

import SwiftUI
import SwiftData

@main
struct outboundApp: App {
    @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var auth = AuthStore()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            AuthView()
                .environment(auth)
        }
        .modelContainer(sharedModelContainer)
    }
}
