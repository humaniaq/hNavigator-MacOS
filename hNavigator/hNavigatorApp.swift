//
//  hNavigatorApp.swift
//  hNavigator
//
//  Created by Leanid Losich on 11/06/2026.
//

import SwiftUI

@main
struct hNavigatorApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 1024, minHeight: 720)
                .background(Color.black)
        }
        .windowStyle(.hiddenTitleBar)
    }
}
