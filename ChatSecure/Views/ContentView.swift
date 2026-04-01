// Views/ContentView.swift
// SecureChat — Root view with navigation

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = ChatViewModel()

    var body: some View {
        ZStack {
            ChatColors.bg.ignoresSafeArea()

            if viewModel.selectedConversationId != nil {
                ConversationView(viewModel: viewModel)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing),
                        removal: .move(edge: .trailing)
                    ))
            } else {
                ChatListView(viewModel: viewModel)
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading),
                        removal: .move(edge: .leading)
                    ))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.selectedConversationId)
        .preferredColorScheme(.dark)
    }
}

#Preview {
    ContentView()
}
