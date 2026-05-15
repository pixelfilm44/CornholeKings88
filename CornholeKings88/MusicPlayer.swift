import AVFoundation

final class MusicPlayer {
    static let shared = MusicPlayer()
    private var player: AVAudioPlayer?
    private var currentTrack: String?

    private init() {}

    func play(named track: String) {
        guard track != currentTrack else { return }
        player?.stop()
        let url = Bundle.main.url(forResource: track, withExtension: "mp3", subdirectory: "Music")
               ?? Bundle.main.url(forResource: track, withExtension: "mp3")
        guard let url else { return }
        player = try? AVAudioPlayer(contentsOf: url)
        player?.numberOfLoops = -1
        player?.volume = 0.5
        player?.play()
        currentTrack = track
    }

    func stop() {
        player?.stop()
        player = nil
        currentTrack = nil
    }
}
