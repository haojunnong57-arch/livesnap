//
//  LiveSnapApp.swift
//  实况工坊 LiveSnap
//

import SwiftUI

@main
struct LiveSnapApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .tint(Palette.amber)
        }
    }
}
