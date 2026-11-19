import AVFoundation
import Combine
import Foundation
import OSLog
import QuartzCore

/// The pets' voices: real cats and dogs, from the recordings in PetVoices (all public domain or
/// CC0; the README says whose they are). A cat meows, purrs and chirps, a dog barks and whines,
/// a poodle yips. A smaller pet sounds higher and a bigger one lower, and each pet's name tunes
/// its voice a little, so no two sound quite alike. The little noises around them (a bonk, a
/// ball popping out, crunching kibble) are made here from tones. The speaker button in the Pet
/// tab turns them off, and they keep quiet while you're in a Meet call.
final class PetSounds: ObservableObject {
    static let shared = PetSounds()

    enum Sound: String {
        /// Clicked, or coming out of the notch: a meow, a woof, a yip yip.
        case talk
        /// Picked up, startled: a squeaky mew or a yelp.
        case surprise
        /// Petted, or bringing the ball: a trill, or a happy bark or two.
        case happy
        /// Landing hard, then seeing stars.
        case bonk
        /// A ball out of the notch or the basket.
        case pop
        /// A ball dropping into the basket.
        case plop
        /// Nobody's played with it for a while: a long, lazy meow, or a dog's whine.
        case bored
        /// Wants feeding: meow meow, or a whine and a woof.
        case hungry
        /// Crunching kibble.
        case munch
        /// Snapping up a ball: "hap!".
        case chomp
        /// Being stroked: a cat purrs, a dog sighs happily.
        case purr

        /// The pet itself speaking (a recording), rather than a noise made from tones.
        var isVoice: Bool {
            switch self {
            case .talk, .surprise, .happy, .bored, .hungry, .purr: return true
            case .bonk, .pop, .plop, .munch, .chomp: return false
            }
        }
    }

    @Published var isOn: Bool {
        didSet { UserDefaults.standard.set(isOn, forKey: Self.onKey) }
    }
    /// In a Meet call: no sounds.
    var isInCall = false

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "DynamicIsland", category: "PetSounds")
    private static let onKey = "petSoundsOn"
    private static let rate = 44_100.0
    /// Softer than the system's own sounds.
    private static let loudness: Float = 0.4
    private var cache: [String: Data] = [:]
    private var players: [AVAudioPlayer] = []
    private var lastPlayed: [Sound: CFTimeInterval] = [:]

    private init() {
        isOn = UserDefaults.standard.object(forKey: Self.onKey) as? Bool ?? true
    }

    /// Plays a sound in `look`'s voice; the same sound again within a moment is skipped.
    func play(_ sound: Sound, for look: PetLook? = nil, volume: Float = 1) {
        guard isOn, !isInCall else {
            Self.log.notice("\(sound.rawValue, privacy: .public) skipped: sounds \(self.isOn ? "on" : "off", privacy: .public), in call \(self.isInCall, privacy: .public)")
            return
        }
        let now = CACurrentMediaTime()
        if let last = lastPlayed[sound], now - last < 0.3 { return }
        lastPlayed[sound] = now
        let voice = Voice(look)
        let take = Int.random(in: 0..<Self.takes(sound, voice.kind))
        let key = "\(sound.rawValue)-\(voice.kind.rawValue)-\(voice.pitch)-\(take)"
        let data: Data
        if let cached = cache[key] {
            data = cached
        } else {
            data = Self.wav(Self.samples(sound, voice, take: take), normalize: !sound.isVoice)
            cache[key] = data
        }
        players.removeAll { !$0.isPlaying }
        guard let player = try? AVAudioPlayer(data: data, fileTypeHint: AVFileType.wav.rawValue) else {
            Self.log.error("\(sound.rawValue, privacy: .public) (\(voice.kind.rawValue, privacy: .public)): couldn't play \(data.count, privacy: .public) bytes")
            return
        }
        player.volume = Self.loudness * volume
        let started = player.play()
        players.append(player)
        Self.log.notice("\(sound.rawValue, privacy: .public) (\(voice.kind.rawValue, privacy: .public), take \(take + 1, privacy: .public)): \(String(format: "%.2f", player.duration), privacy: .public) s at volume \(String(format: "%.2f", player.volume), privacy: .public), started \(started, privacy: .public)")
    }

    // MARK: Voices

    private struct Voice {
        enum Kind: String {
            case cat, dog, poodle
        }

        let kind: Kind
        /// 1 for a medium pet; higher for a smaller one; each name a touch different.
        let pitch: Double

        init(_ look: PetLook?) {
            guard let look else {
                kind = .cat
                pitch = 1
                return
            }
            kind = look.kind == .cat ? .cat : look.isPoodle ? .poodle : .dog
            var hash: UInt32 = 2_166_136_261
            for byte in look.name.lowercased().utf8 {
                hash = (hash ^ UInt32(byte)) &* 16_777_619
            }
            let tune = Double(Int(hash % 11) - 5) * 0.012
            // Rounded, so a few voices are made and kept rather than one for every pet.
            pitch = ((1 / look.scale.squareRoot()) * (1 + tune) * 50).rounded() / 50
        }
    }

    /// How many takes a sound has; one is picked at random each time, so it doesn't get samey.
    private static func takes(_ sound: Sound, _ kind: Voice.Kind) -> Int {
        switch (sound, kind) {
        case (.talk, .cat), (.happy, .cat): return 3
        case (.talk, .dog): return 4
        case (.talk, .poodle), (.happy, .dog), (.bored, .dog), (.bored, .poodle): return 2
        default: return 1
        }
    }

    /// A poodle is a small dog: its barks are yips, higher than a big dog's.
    private static let yip = 1.45

    private static func samples(_ sound: Sound, _ voice: Voice, take: Int) -> [Float] {
        let pitch = voice.pitch
        func clip(_ name: String, _ shift: Double = 1) -> [Float] { recorded(name, pitch: pitch * shift) }
        func bark(_ number: Int, _ shift: Double = 1) -> [Float] { clip("dog-bark-\(number)", shift) }
        switch (sound, voice.kind) {
        case (.talk, .cat): return clip("cat-meow-\(take + 1)")
        case (.talk, .dog): return bark(take + 1)
        case (.talk, .poodle): return bark(take + 1, yip) + silence(0.04) + bark(take + 2, yip * 1.04)
        case (.surprise, .cat): return clip("cat-trill-1", 1.2)
        case (.surprise, .dog): return bark(3, 1.3)
        case (.surprise, .poodle): return bark(3, yip * 1.3)
        case (.happy, .cat): return take == 2 ? clip("cat-purr") : clip("cat-trill-\(take + 1)")
        case (.happy, .dog): return bark(take * 2 + 1, 1.06) + silence(0.09) + bark(take * 2 + 2, 1.06)
        case (.happy, .poodle):
            return bark(1, yip) + silence(0.03) + bark(2, yip * 1.05) + silence(0.03) + bark(4, yip)
        case (.bored, .cat): return clip("cat-plead-3")
        case (.bored, .dog), (.bored, .poodle):
            let shift = voice.kind == .dog ? 0.85 : 1
            return take == 0 ? clip("dog-whine-2", shift) : clip("dog-whine-1", shift) + silence(0.15) + clip("dog-whine-3", shift)
        case (.hungry, .cat): return clip("cat-plead-1") + silence(0.18) + clip("cat-plead-2")
        case (.hungry, .dog): return clip("dog-whine-1", 0.85) + silence(0.12) + bark(2)
        case (.hungry, .poodle):
            return clip("dog-whine-3") + silence(0.08) + bark(1, yip) + silence(0.04) + bark(2, yip * 1.04)
        case (.purr, .cat): return clip("cat-purr")
        case (.purr, _): return clip("dog-whine-1", 1.12)
        case (.munch, _): return munch()
        case (.chomp, _): return chomp(pitch: pitch)
        case (.bonk, _): return bonk()
        case (.pop, _): return sweep(from: 700, to: 1500, length: 0.07)
        case (.plop, _): return sweep(from: 650, to: 240, length: 0.12)
        }
    }

    private static func silence(_ seconds: Double) -> [Float] {
        [Float](repeating: 0, count: Int(seconds * rate))
    }

    // MARK: Recordings

    /// The PetVoices clips, read once each.
    private static var recordings: [String: [Float]] = [:]

    /// A recorded clip, played faster (higher and shorter) or slower (lower and longer) by
    /// `pitch`, the way a small animal sounds higher than a big one.
    private static func recorded(_ name: String, pitch: Double) -> [Float] {
        let source: [Float]
        if let loaded = recordings[name] {
            source = loaded
        } else {
            source = load(name)
            recordings[name] = source
        }
        guard abs(pitch - 1) > 0.005, source.count > 1 else { return source }
        var input = source
        if pitch > 1 {
            // Played faster, its highest notes would fold back as hiss; soften them first.
            let cutoff = 0.45 * rate / pitch
            let smooth = Float(1 - exp(-2 * .pi * cutoff / rate))
            var level: Float = 0
            for index in input.indices {
                level += (input[index] - level) * smooth
                input[index] = level
            }
        }
        let count = Int(Double(input.count) / pitch)
        var out = [Float](repeating: 0, count: count)
        for index in 0..<count {
            let at = Double(index) * pitch
            let whole = min(Int(at), input.count - 2)
            let part = Float(at - Double(whole))
            out[index] = input[whole] + (input[whole + 1] - input[whole]) * part
        }
        return out
    }

    /// A clip from the app's PetVoices folder (mono, 44.1 kHz), or nothing if it's missing.
    private static func load(_ name: String) -> [Float] {
        guard let url = Bundle.main.url(forResource: "petvoice-\(name)", withExtension: "wav"),
              let file = try? AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buffer)) != nil,
              let channel = buffer.floatChannelData?[0]
        else {
            log.error("Pet voice \(name, privacy: .public) is missing or unreadable")
            return []
        }
        return Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
    }

    // MARK: Made from tones


    /// A snap of the jaws: a click of teeth, then a short squeak of the ball.
    private static func chomp(pitch: Double) -> [Float] {
        let click = sweep(from: 2600 * pitch, to: 1300 * pitch, length: 0.025)
        let squeak = voiced(length: 0.09,
                            f0: { p in mix(1250, 1500, p) },
                            formant: { _ in 2600 },
                            envelope: { p in swell(p, attack: 0.2, release: 0.5) * 0.5 },
                            breath: 0, harmonics: 3)
        return click + silence(0.015) + squeak
    }

    /// Two crunchy bites of kibble.
    private static func munch() -> [Float] {
        var out: [Float] = []
        var random = Noise(seed: 77)
        for bite in 0..<2 {
            var crunch = Formant()
            crunch.tune(frequency: bite == 0 ? 1800 : 2300, bandwidth: 1400)
            let count = Int(0.07 * rate)
            for index in 0..<count {
                let t = Double(index) / rate
                // Gritty: noise that comes and goes.
                let grain = random.next() < 0.35 ? random.next() * 2 - 1 : 0
                out.append(Float(crunch.process(grain) * exp(-t * 45)))
            }
            out += silence(0.08)
        }
        return out
    }

    /// A resonance of the throat or mouth: a band-pass filter that can be retuned as it goes.
    private struct Formant {
        private var b0 = 0.0, b2 = 0.0, a1 = 0.0, a2 = 0.0
        private var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0

        mutating func tune(frequency: Double, bandwidth: Double) {
            let w = 2 * .pi * min(frequency, PetSounds.rate * 0.45) / PetSounds.rate
            let alpha = sin(w) / (2 * max(frequency / bandwidth, 0.5))
            let a0 = 1 + alpha
            b0 = alpha / a0
            b2 = -alpha / a0
            a1 = -2 * cos(w) / a0
            a2 = (1 - alpha) / a0
        }

        mutating func process(_ x: Double) -> Double {
            let y = b0 * x + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1
            x1 = x
            y2 = y1
            y1 = y
            return y
        }
    }

    /// The same noise every time, so a sound made twice is the same sound.
    private struct Noise {
        var seed: UInt32

        mutating func next() -> Double {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            return Double(seed >> 8) / Double(1 << 24)
        }
    }

    /// A cartoon thump, then a wobbly whistle for the stars.
    private static func bonk() -> [Float] {
        let length = 0.62
        let count = Int(length * rate)
        var out = [Float](repeating: 0, count: count)
        var thump = 0.0, whistle = 0.0
        for index in 0..<count {
            let t = Double(index) / rate
            thump += 2 * .pi * (55 + 105 * exp(-t * 30)) / rate
            var value = sin(thump) * exp(-t * 25)
            if t > 0.08 {
                let p = (t - 0.08) / (length - 0.08)
                whistle += 2 * .pi * (820 - 300 * p + 70 * sin(2 * .pi * 13 * t)) / rate
                value += 0.45 * sin(whistle) * swell(p, attack: 0.1, release: 0.5)
            }
            out[index] = Float(value)
        }
        return out
    }

    /// A plain tone gliding from one pitch to another, dying away: a pop or a plop.
    private static func sweep(from start: Double, to end: Double, length: Double) -> [Float] {
        let count = Int(length * rate)
        var out = [Float](repeating: 0, count: count)
        var phase = 0.0
        for index in 0..<count {
            let p = Double(index) / Double(count)
            phase += 2 * .pi * start * pow(end / start, p) / rate
            out[index] = Float(sin(phase) * min(p / 0.05, 1) * exp(-p * 4))
        }
        return out
    }

    /// A voice: the harmonics of `f0` shaped by a formant (the mouth) at `formant`, under
    /// `envelope`, with a little breath; each is given p, from 0 to 1 through the sound.
    private static func voiced(length: Double, f0: (Double) -> Double, formant: (Double) -> Double, width: Double = 450,
                               envelope: (Double) -> Double, breath: Double = 0.02, harmonics: Int = 10) -> [Float] {
        let count = Int(length * rate)
        var out = [Float](repeating: 0, count: count)
        var phase = 0.0
        var seed: UInt32 = 0x9E37_79B9
        for index in 0..<count {
            let t = Double(index) / rate
            let p = t / length
            let frequency = f0(p) * (1 + 0.012 * sin(2 * .pi * 5.5 * t))
            phase += 2 * .pi * frequency / rate
            let center = formant(p)
            var value = 0.0, total = 0.0
            for harmonic in 1...harmonics {
                let at = Double(harmonic) * frequency
                guard at < rate / 2 else { break }
                let strength = exp(-pow((at - center) / width, 2)) + 0.22 / Double(harmonic)
                value += strength * sin(Double(harmonic) * phase)
                total += strength
            }
            seed = seed &* 1_664_525 &+ 1_013_904_223
            let noise = Double(seed >> 8) / Double(1 << 24) * 2 - 1
            out[index] = Float((value / max(total, 0.001) + noise * breath) * envelope(p))
        }
        return out
    }

    private static func mix(_ a: Double, _ b: Double, _ p: Double) -> Double {
        a + (b - a) * min(max(p, 0), 1)
    }

    private static func ease(_ p: Double) -> Double {
        let p = min(max(p, 0), 1)
        return p * p * (3 - 2 * p)
    }

    /// Up over the first `attack` of the sound, down over the last `release`.
    private static func swell(_ p: Double, attack: Double, release: Double) -> Double {
        let up = attack > 0 ? ease(p / attack) : 1
        let down = release > 0 ? ease((1 - p) / release) : 1
        return up * down
    }

    /// 16-bit mono WAV. Tones are made as loud as they can go without clipping; the recordings
    /// were evened out when they were cut, so they're left as they are.
    private static func wav(_ samples: [Float], normalize: Bool) -> Data {
        let peak = max(samples.lazy.map { abs($0) }.max() ?? 1, 0.001)
        let gain = normalize ? 0.9 / peak : 1
        var pcm = Data(capacity: samples.count * 2)
        for sample in samples {
            var value = Int16(max(-1, min(1, sample * gain)) * 32_000).littleEndian
            withUnsafeBytes(of: &value) { pcm.append(contentsOf: $0) }
        }
        var data = Data()
        func text(_ string: String) { data.append(contentsOf: Array(string.utf8)) }
        func u32(_ number: UInt32) { var value = number.littleEndian; withUnsafeBytes(of: &value) { data.append(contentsOf: $0) } }
        func u16(_ number: UInt16) { var value = number.littleEndian; withUnsafeBytes(of: &value) { data.append(contentsOf: $0) } }
        text("RIFF"); u32(UInt32(36 + pcm.count)); text("WAVE")
        text("fmt "); u32(16); u16(1); u16(1); u32(UInt32(rate)); u32(UInt32(rate) * 2); u16(2); u16(16)
        text("data"); u32(UInt32(pcm.count))
        data.append(pcm)
        return data
    }
}
