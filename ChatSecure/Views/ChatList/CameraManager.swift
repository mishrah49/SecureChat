//
//  CameraManager.swift
//  ChatSecure
//
//  Created by Harshit Mishra on 01/04/26.
//


import SwiftUI
import AVFoundation
import Combine

// MARK: - Camera Manager

class CameraManager: ObservableObject {
    @Published var permissionGranted = false
    @Published var captureSession: AVCaptureSession? // Now optional and Published
    
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    
    init() {
        checkPermission()
    }
    
    func checkPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            DispatchQueue.main.async { self.permissionGranted = true }
            self.setupCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async { self?.permissionGranted = granted }
                if granted { self?.setupCamera() }
            }
        default:
            DispatchQueue.main.async { self.permissionGranted = false }
        }
    }
    
    private func setupCamera() {
        // Build the heavy camera session entirely on a background thread
        sessionQueue.async { [weak self] in
            let session = AVCaptureSession()
            
            guard let videoDevice = AVCaptureDevice.default(for: .video),
                  let videoInput = try? AVCaptureDeviceInput(device: videoDevice) else { return }
            
            if session.canAddInput(videoInput) {
                session.addInput(videoInput)
            }
            
            session.startRunning()
            
            // Pass the ready session back to the main thread for the UI
            DispatchQueue.main.async {
                self?.captureSession = session
            }
        }
    }
    
    func stopCamera() {
        sessionQueue.async { [weak self] in
            self?.captureSession?.stopRunning()
        }
    }
}

// MARK: - Camera Preview Wrapper
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    
    func makeUIView(context: Context) -> VideoPreviewView {
        let view = VideoPreviewView()
        view.backgroundColor = .black
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }
    
    func updateUIView(_ uiView: VideoPreviewView, context: Context) {}
    
    class VideoPreviewView: UIView {
        override class var layerClass: AnyClass {
            return AVCaptureVideoPreviewLayer.self
        }
        
        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            return layer as! AVCaptureVideoPreviewLayer
        }
    }
}