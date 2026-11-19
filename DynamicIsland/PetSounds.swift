import AVFoundation
import Combine
import Foundation
import QuartzCore

/// The pets' voices, made here from tones rather than recordings: a cat meows, a dog woofs, a
/// poodle yips. A smaller pet sounds higher and a bigger one lower, and each pet's name tunes its
/// voice a little, so no two sound quite alike. The speaker button in the Pet tab turns them off,
/// and they keep quiet while you're in a Meet call.
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
    }

    @Published var isOn: Bool {
        didSet { UserDefaults.standard.set(isOn, forKey: Self.onKey) }
    }
    /// In a Meet call: no sounds.
    var isInCall = false

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
        guard isOn, !isInCall else { return }
        let now = CACurrentMediaTime()
        if let last = lastPlayed[sound], now - last < 0.3 { return }
        lastPlayed[sound] = now
        let voice = Voice(look)
        let key = "\(sound.rawValue)-\(voice.kind.rawValue)-\(voice.pitch)"
        let data: Data
        if let cached = cache[key] {
            data = cached
        } else {
            data = Self.wav(Self.samples(sound, voice))
            cache[key] = data
        }
        players.removeAll { !$0.isPlaying }
        guard let player = try? AVAudioPlayer(data: data, fileTypeHint: AVFileType.wav.rawValue) else { return }
        player.volume = Self.loudness * volume
        player.play()
        players.append(player)
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

    private static func samples(_ sound: Sound, _ voice: Voice) -> [Float] {
        let pitch = voice.pitch
        switch (sound, voice.kind) {
        case (.talk, .cat): return meow(pitch: pitch)
        case (.talk, .dog): return barks(.woof, pitch: pitch, count: 1, gap: 0)
        case (.talk, .poodle): return barks(.yip, pitch: pitch, count: 2, gap: 0.06)
        case (.surprise, .cat): return mew(pitch: pitch)
        case (.surprise, .dog): return barks(.yelp, pitch: pitch, count: 1, gap: 0)
        case (.surprise, .poodle): return barks(.yelp, pitch: pitch * 1.3, count: 1, gap: 0)
        case (.happy, .cat): return trill(pitch: pitch)
        case (.happy, .dog): return barks(.arf, pitch: pitch, count: 2, gap: 0.08)
        case (.happy, .poodle): return barks(.yip, pitch: pitch * 1.1, count: 3, gap: 0.05)
        case (.bonk, _): return bonk()
        case (.pop, _): return sweep(from: 700, to: 1500, length: 0.07)
        case (.plop, _): return sweep(from: 650, to: 240, length: 0.12)
        }
    }

    /// "Mi-aaa-ow": up, then down, the mouth opening and closing.
    private static func meow(pitch: Double) -> [Float] {
        voiced(length: 0.42,
               f0: { p in pitch * (p < 0.3 ? mix(520, 760, ease(p / 0.3)) : mix(760, 480, ease((p - 0.3) / 0.7))) },
               formant: { p in pitch.squareRoot() * (p < 0.25 ? mix(650, 1900, p / 0.25) : mix(1900, 850, (p - 0.25) / 0.75)) },
               envelope: { p in swell(p, attack: 0.12, release: 0.35) })
    }

    /// A short squeaky "mew?", going up.
    private static func mew(pitch: Double) -> [Float] {
        voiced(length: 0.2,
               f0: { p in pitch * mix(620, 980, ease(p)) },
               formant: { p in pitch.squareRoot() * mix(1500, 2300, p) },
               envelope: { p in swell(p, attack: 0.1, release: 0.3) })
    }

    /// "Mrrrp": a rolling little chirp.
    private static func trill(pitch: Double) -> [Float] {
        let length = 0.32
        return voiced(length: length,
                      f0: { p in pitch * mix(480, 640, ease(p)) },
                      formant: { p in pitch.squareRoot() * mix(1300, 1700, p) },
                      envelope: { p in swell(p, attack: 0.1, release: 0.3) * (0.65 + 0.35 * sin(2 * .pi * 30 * p * length)) })
    }

    /// How a bark goes: its pitch (in Hz, for a medium dog) at the start, the top and the end,
    /// how long, how wide the mouth opens ("woof" to "arf"), and how much growl is under it.
    private struct Bark {
        let base: Double
        let length: Double
        let open: Double
        let start: Double, peak: Double, peakAt: Double, end: Double
        let growl: Double

        /// A deep, round "woof".
        static let woof = Bark(base: 290, length: 0.21, open: 0.8, start: 0.78, peak: 1, peakAt: 0.2, end: 0.66, growl: 0.38)
        /// A short, bright "arf".
        static let arf = Bark(base: 370, length: 0.13, open: 1.1, start: 0.85, peak: 1, peakAt: 0.18, end: 0.72, growl: 0.25)
        /// A startled "kai!", up and down.
        static let yelp = Bark(base: 700, length: 0.16, open: 1.25, start: 0.88, peak: 1.18, peakAt: 0.35, end: 0.86, growl: 0.08)
        /// A little dog's quick "yip".
        static let yip = Bark(base: 620, length: 0.09, open: 1.25, start: 0.85, peak: 1.05, peakAt: 0.2, end: 0.8, growl: 0.1)
    }

    /// Barks one after another, each a touch higher.
    private static func barks(_ shape: Bark, pitch: Double, count: Int, gap: Double) -> [Float] {
        var out: [Float] = []
        for index in 0..<count {
            out += bark(shape, pitch: pitch * (1 + Double(index) * 0.05), seed: UInt32(index + 1))
            if index < count - 1 {
                out += [Float](repeating: 0, count: Int(gap * rate))
            }
        }
        return out
    }

    /// A bark the way a dog makes one: a buzzy, uneven voice with a growl under it and a puff of
    /// breath at each end, through a throat and mouth (three formants) that open on the "wo" and
    /// close on the "of".
    private static func bark(_ shape: Bark, pitch: Double, seed: UInt32) -> [Float] {
        let count = Int(shape.length * rate)
        var out = [Float](repeating: 0, count: count)
        var random = Noise(seed: seed &* 2_654_435_761)
        var phase = 0.0, under = 0.0, wobble = 0.0
        var throat = Formant(), mouth = Formant(), nose = Formant()
        let size = pitch.squareRoot()
        for index in 0..<count {
            let t = Double(index) / rate
            let p = t / shape.length
            let contour = p < shape.peakAt ? mix(shape.start, shape.peak, ease(p / shape.peakAt))
                : mix(shape.peak, shape.end, ease((p - shape.peakAt) / (1 - shape.peakAt)))
            // A real voice is never steady: a new wobble every millisecond and a half.
            if index % 64 == 0 {
                wobble = (random.next() * 2 - 1) * 0.04
            }
            let frequency = shape.base * pitch * contour * (1 + wobble)
            let step = frequency / rate
            phase += step
            if phase >= 1 { phase -= 1 }
            under += step / 2
            if under >= 1 { under -= 1 }
            // The buzz of the voice, the growl an octave under, and breath: a burst, then a puff at the end.
            let breath = 0.55 * exp(-t * 70) + 0.3 * ease((p - 0.55) / 0.45) + 0.1
            let source = saw(phase, step) + shape.growl * saw(under, step / 2) + (random.next() * 2 - 1) * breath
            if index % 32 == 0 {
                let open = (p < 0.25 ? mix(0.5, 1, ease(p / 0.25)) : mix(1, 0.55, ease((p - 0.25) / 0.75))) * shape.open
                throat.tune(frequency: (360 + 440 * open) * size, bandwidth: 140)
                mouth.tune(frequency: (850 + 750 * open) * size, bandwidth: 220)
                nose.tune(frequency: 2500 * size, bandwidth: 320)
            }
            let value = throat.process(source) + 0.6 * mouth.process(source) + 0.2 * nose.process(source)
            // A hard start, a short hold, then dying away.
            let envelope = min(t / 0.006, 1) * (p < 0.3 ? 1 : exp(-(p - 0.3) * 4)) * swell(p, attack: 0, release: 0.12)
            out[index] = Float(value * envelope)
        }
        return out
    }

    /// A sawtooth without the harsh edges a plain one has (PolyBLEP).
    private static func saw(_ phase: Double, _ step: Double) -> Double {
        var value = 2 * phase - 1
        if phase < step {
            let x = phase / step
            value -= x + x - x * x - 1
        } else if phase > 1 - step {
            let x = (phase - 1) / step
            value -= x * x + x + x + 1
        }
        return value
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

    /// 16-bit mono WAV, made as loud as it can go without clipping.
    private static func wav(_ samples: [Float]) -> Data {
        let peak = max(samples.lazy.map { abs($0) }.max() ?? 1, 0.001)
        var pcm = Data(capacity: samples.count * 2)
        for sample in samples {
            var value = Int16(max(-1, min(1, sample / peak * 0.9)) * 32_000).littleEndian
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
