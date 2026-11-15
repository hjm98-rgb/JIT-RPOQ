//
//  SoundPlayer.swift
//  JIT RPOQ
//
//  过渡音效：高空坠落风声 + 落地闷响。
//

import AVFoundation
import UIKit

@MainActor
final class SoundPlayer {
    static let shared = SoundPlayer()

    private var wind: AVAudioPlayer?
    private var impact: AVAudioPlayer?
    private var didSetup = false

    private init() {}

    private func setupIfNeeded() {
        guard !didSetup else { return }
        didSetup = true
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
        wind = load("wind_fall")
        impact = load("impact")
        wind?.volume = 0.55
        impact?.volume = 0.7
        wind?.prepareToPlay()
        impact?.prepareToPlay()
    }

    private func load(_ name: String) -> AVAudioPlayer? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav") else { return nil }
        let player = try? AVAudioPlayer(contentsOf: url)
        return player
    }

    /// 开始坠落：风声从 0 淡入，避免爆音
    func startFall() {
        setupIfNeeded()
        guard let wind else { return }
        wind.stop()
        wind.currentTime = 0
        wind.volume = 0
        wind.play()
        wind.setVolume(0.55, fadeDuration: 0.35)
    }

    /// 落地：闷响 + 轻微震动反馈
    func land() {
        setupIfNeeded()
        wind?.stop()
        impact?.stop()
        impact?.currentTime = 0
        impact?.play()
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }

    /// 被打断时收尾
    func stop() {
        wind?.stop()
        impact?.stop()
    }
}
