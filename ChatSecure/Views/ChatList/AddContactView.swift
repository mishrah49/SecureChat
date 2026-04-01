//
//  AddContactView.swift
//  ChatSecure
//
//  Created by Harshit Mishra on 01/04/26.
//


import SwiftUI
import AVFoundation

struct AddContactView: View {
    @Environment(\.dismiss) var dismiss
    
    // 1. ADD THE VIEW MODEL
    @ObservedObject var viewModel: ChatViewModel
    
    @State private var selectedTab: QRTab = .scan
    @StateObject private var cameraManager = CameraManager()
    
    enum QRTab {
        case scan, show
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Main Content Window
                ZStack {
                    Color.black.ignoresSafeArea()
                    
                    if selectedTab == .scan {
                        ScannerLiveView(cameraManager: cameraManager)
                            .transition(.opacity)
                    } else {
                        MyQRCodeMockView()
                            .transition(.opacity)
                    }
                    
                    // 2. HIDDEN DEVELOPER BUTTON OVERLAY
                    VStack {
                        HStack {
                            Spacer()
                            Button {
                                // Trigger logic based on the current tab
                                if selectedTab == .scan {
                                    viewModel.addHiddenContact(name: "Anurag")
                                } else {
                                    viewModel.addHiddenContact(name: "Harshit")
                                }
                                
                                // Clean up and dismiss
                                cameraManager.stopCamera()
                                dismiss()
                            } label: {
                                // 0.01 opacity makes it invisible but still tappable
                                Color.white.opacity(0.01)
                                    .frame(width: 80, height: 80)
                            }
                        }
                        Spacer()
                    }
                }
                .frame(maxHeight: .infinity)
                
                // Bottom Toggle Bar
                HStack(spacing: 0) {
                    TabButton(title: "Scan Code", isSelected: selectedTab == .scan) {
                        withAnimation { selectedTab = .scan }
                    }
                    
                    TabButton(title: "My Code", isSelected: selectedTab == .show) {
                        withAnimation { selectedTab = .show }
                    }
                }
                .padding(.vertical, 16)
                .background(Color(uiColor: .systemGray6))
            }
            .navigationTitle(selectedTab == .scan ? "Scan QR Code" : "My QR Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        cameraManager.stopCamera()
                        dismiss()
                    }
                    .foregroundColor(.teal)
                }
            }
        }
        .onDisappear {
            cameraManager.stopCamera()
        }
    }
}

// MARK: - Live Scanner View
private struct ScannerLiveView: View {
    @ObservedObject var cameraManager: CameraManager
    
    var body: some View {
        ZStack {
            // Unwrapping the optional background session
            if cameraManager.permissionGranted, let session = cameraManager.captureSession {
                CameraPreviewView(session: session)
                    .ignoresSafeArea()
            } else if !cameraManager.permissionGranted {
                Text("Camera access denied.\nPlease enable it in Settings.")
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
            } else {
                // Show a spinner while the camera loads in the background
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.5)
            }
            
            // The WhatsApp-style Overlay (Keep your existing overlay code)
            VStack(spacing: 30) {
                Spacer()
                
                Text("Align the QR code within the frame to scan.")
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Capsule())
                
                ZStack {
                    Group {
                        CornerBracket().position(x: 0, y: 0)
                        CornerBracket().rotationEffect(.degrees(90)).position(x: 250, y: 0)
                        CornerBracket().rotationEffect(.degrees(180)).position(x: 250, y: 250)
                        CornerBracket().rotationEffect(.degrees(270)).position(x: 0, y: 250)
                    }
                    .frame(width: 250, height: 250)
                }
                
                Spacer()
                Spacer()
            }
        }
    }
}
// MARK: - Reusable Views (Keep these from the previous code)
private struct CornerBracket: View {
    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 40))
            path.addLine(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: 40, y: 0))
        }
        .stroke(Color.teal, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
        .frame(width: 40, height: 40)
    }
}

private struct TabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 15, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .teal : .gray)
                
                Rectangle()
                    .fill(isSelected ? Color.teal : Color.clear)
                    .frame(height: 2)
                    .padding(.horizontal, 30)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct MyQRCodeMockView: View {
    var body: some View {
        VStack(spacing: 24) {
            Text("Your friends can scan this code to connect with you.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white)
                    .frame(width: 260, height: 260)
                    .shadow(radius: 10)
                
                Image("qrCode")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 200)
                    .foregroundColor(.black)
            }
        }
    }
}
