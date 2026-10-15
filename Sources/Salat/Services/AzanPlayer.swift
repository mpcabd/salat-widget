import AppKit
import AVFoundation
import PrayerKit

/// Plays the call to prayer with optional fade-in and "short" mode.
@MainActor
@Observable
final class AzanPlayer: NSObject {
    private(set) var isPlaying = false
    private(set) var playingPrayer: Prayer?
    private(set) var isPreview = false

    private var player: AVAudioPlayer?
    private var chime: NSSound?
    private var shortStopWork: DispatchWorkItem?
    /// Last playback position and when we saw it change, to detect a player that stopped advancing.
    private var lastProgress: (time: TimeInterval, at: Date)?

    /// How long playback may stand still before we treat it as dead. AVAudioPlayer never calls its delegate
    /// when audio output disappears (e.g. playing during a maintenance wake, then the Mac sleeps again).
    static let stallTimeout: TimeInterval = 10

    static let shortDuration: TimeInterval = 28

    func play(url: URL?, volume: Double, fadeIn: Bool, short: Bool, prayer: Prayer?, preview: Bool = false) {
        stop()
        isPreview = preview
        playingPrayer = prayer

        guard let url else {
            playChime(volume: volume)
            return
        }
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.delegate = self
            p.prepareToPlay()
            let target = Float(max(0, min(1, volume)))
            if fadeIn {
                p.volume = 0
                p.play()
                p.setVolume(target, fadeDuration: 4)
            } else {
                p.volume = target
                p.play()
            }
            player = p
            isPlaying = true
            lastProgress = (p.currentTime, Date())
            if short || preview {
                let work = DispatchWorkItem { [weak self] in self?.fadeOutAndStop() }
                shortStopWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + (preview ? 12 : Self.shortDuration), execute: work)
            }
        } catch {
            NSLog("Salat: could not play azan at \(url.path): \(error)")
            playChime(volume: volume)
        }
    }

    private func playChime(volume: Double) {
        let s = NSSound(named: "Glass") ?? NSSound(named: "Ping")
        s?.volume = Float(volume)
        s?.play()
        chime = s
        isPlaying = false
        playingPrayer = nil
    }

    /// Called every clock tick: resets the state if playback has stalled.
    func checkStalled(now: Date = Date()) {
        guard isPlaying, let p = player, let last = lastProgress else { return }
        if p.isPlaying && p.currentTime != last.time {
            lastProgress = (p.currentTime, now)
        } else if now.timeIntervalSince(last.at) > Self.stallTimeout {
            NSLog("Salat: azan playback stalled at \(p.currentTime)s, stopping")
            stop()
        }
    }

    func fadeOutAndStop() {
        guard let p = player, p.isPlaying else { stop(); return }
        p.setVolume(0, fadeDuration: 2.5)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { [weak self] in
            guard let self, self.player === p else { return }
            self.stop()
        }
    }

    func stop() {
        shortStopWork?.cancel()
        shortStopWork = nil
        player?.stop()
        player = nil
        lastProgress = nil
        chime?.stop()
        chime = nil
        isPlaying = false
        playingPrayer = nil
        isPreview = false
    }
}

extension AzanPlayer: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            if self.player === player { self.stop() }
        }
    }
}
