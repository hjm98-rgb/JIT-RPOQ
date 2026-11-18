//
//  BackgroundKeepAlive.swift
//  JIT RPOQ
//
//  让调试会话在退到后台后继续存活：
//  1) 申请后台任务并循环续期
//  2) 播放极低音量的静音音轨（配合 Info.plist 的 audio 后台模式）
//

import AVFoundation
import UIKit

final class BackgroundKeepAlive {
    static let shared = BackgroundKeepAlive()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var task: UIBackgroundTaskIdentifier = .invalid
    private var renewTimer: Timer?
    private var running = false

    private init() {}

    func start() {
        guard !running else { return }
        running = true

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [])
        try? session.setActive(true)

        guard let format = AVAudioFormat(standardFormatWithSampleRate: 22_050, channels: 1) else { return }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 22_050) else { return }
        buffer.frameLength = 22_050
        if let channel = buffer.floatChannelData?[0] {
            for index in 0..<Int(buffer.frameLength) {
                // 极低但非零，避免被系统判定为静音而挂起
                channel[index] = 0.00002
            }
        }

        player.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
        do {
            try engine.start()
            player.play()
        } catch {
            running = false
        }

        beginTask()
        renewTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            self?.beginTask()
        }
    }

    func stop() {
        guard running else { return }
        running = false
        renewTimer?.invalidate()
        renewTimer = nil
        player.stop()
        engine.stop()
        engine.detach(player)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        endTask()
    }

    private func beginTask() {
        endTask()
        task = UIApplication.shared.beginBackgroundTask(withName: "JITSession") { [weak self] in
            self?.endTask()
        }
    }

    private func endTask() {
        guard task != .invalid else { return }
        UIApplication.shared.endBackgroundTask(task)
        task = .invalid
    }
}
