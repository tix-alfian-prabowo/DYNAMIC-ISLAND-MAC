import SwiftUI

/// The Pet tab: your pet (choose it, let it out or call it home, throw it a ball) and friends to
/// play with: invite them, or join a friend who invited you.
struct PetTabView: View {
    @EnvironmentObject var layout: IslandLayout
    @EnvironmentObject var pokeService: PokeService
    @ObservedObject private var store = PetStore.shared
    @ObservedObject private var play = PetPlay.shared
    @ObservedObject private var world = PetWorld.shared
    @ObservedObject private var sounds = PetSounds.shared
    @State private var draft = PetLook(kind: .cat, coat: 0, name: PetKind.cat.defaultName)
    @State private var isEditing = false

    var body: some View {
        Group {
            if let look = store.look, !isEditing {
                HStack(alignment: .top, spacing: 24) {
                    yourPet(look)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    friends
                        .frame(width: layout.wide(270, 340), alignment: .leading)
                }
            } else {
                chooser
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Yours

    private func yourPet(_ look: PetLook) -> some View {
        VStack(alignment: .leading, spacing: layout.wide(10, 16)) {
            HStack(spacing: 12) {
                PetPortrait(look: look, action: store.isOut ? .sit : .sleep)
                    .frame(width: layout.wide(62, 84), height: layout.wide(52, 72))
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DropStyle.faint))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(DropStyle.line, lineWidth: 0.5))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(look.name)
                            .font(.system(size: layout.wide(18, 24), weight: .bold, design: .rounded))
                        Button {
                            draft = look
                            isEditing = true
                        } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(DropStyle.muted)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .pointingHandCursor()
                        .help("Change its kind, color, size or name")
                        Button {
                            sounds.isOn.toggle()
                            if sounds.isOn {
                                PetSounds.shared.play(.talk, for: look)
                            }
                        } label: {
                            Image(systemName: sounds.isOn ? "speaker.wave.2.fill" : "speaker.slash.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(DropStyle.muted)
                                .frame(width: 16)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .pointingHandCursor()
                        .help(sounds.isOn ? "Sounds on: click to keep \(look.name) quiet (it's quiet in Meet calls anyway)" : "Sounds off: click to hear \(look.name)")
                    }
                    Text("\(sizeName(look)) \(look.coatStyle.name.lowercased()) \(look.title.lowercased()) · \(store.isOut ? "out on the desktop" : "asleep in the notch")\(world.isHungry ? " · hungry" : world.isBored && store.isOut ? " · bored" : "")")
                        .font(.system(size: layout.wide(10, 11), design: .rounded))
                        .foregroundColor(DropStyle.muted)
                }
            }
            HStack(spacing: 6) {
                DropButton(title: store.isOut ? "Home" : "Let Out", systemImage: store.isOut ? "house.fill" : "pawprint.fill",
                           prominent: !store.isOut, height: 24) {
                    store.isOut.toggle()
                }
                .frame(width: 76)
                .help(store.isOut ? "Call \(look.name) home into the notch" : "Let \(look.name) out onto the desktop")
                DropButton(title: "Feed", systemImage: "fork.knife", prominent: world.isHungry, height: 24) {
                    world.feed()
                }
                .frame(width: 64)
                .disabled(world.isBowlOut)
                .opacity(world.isBowlOut ? 0.45 : 1)
                .help(world.isHungry ? "\(look.name) is hungry: put a bowl of food out" : "Put a bowl of food out (a treat; it gets hungry every few hours)")
                let isFull = world.ballCount >= PetWorld.maxBalls
                DropButton(title: world.ballCount > 0 ? "\(world.ballCount)/\(PetWorld.maxBalls)" : "Ball", systemImage: "tennisball.fill", height: 24) {
                    play.throwBall()
                }
                .frame(width: 70)
                .disabled(isFull)
                .opacity(isFull ? 0.45 : 1)
                .help(isFull ? "Ten balls are out: wait for the pets to bring some back" : "Throw a ball from the notch for the pets to fetch (up to \(PetWorld.maxBalls))")
                DropButton(title: "Basket", systemImage: "basket.fill", prominent: world.basketIsOut, height: 24) {
                    world.toggleBasket()
                }
                .frame(width: 76)
                .help(world.basketIsOut ? "Put the basket away; its balls stay in it"
                      : "Put a basket on the desktop: your pet brings the balls to it, and a click on it gives one back")
            }
            Text(world.basketIsOut ? "Click it to say hi, drag it to move it. Drag the basket anywhere; click it for a ball."
                 : "Click it to say hi, drag it to move it.")
                .font(.system(size: 9.5, design: .rounded))
                .foregroundColor(DropStyle.muted)
            Spacer(minLength: 0)
        }
    }

    // MARK: Friends

    private var friends: some View {
        VStack(alignment: .leading, spacing: 8) {
            if case .playing(let friend, _) = play.state {
                HStack(spacing: 8) {
                    Image(systemName: "pawprint.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(DropStyle.accent)
                    Text("Playing with \(friend.name)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                    Spacer(minLength: 4)
                    DropButton(title: "Leave", height: 22) { play.leave() }
                        .frame(width: 60)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(DropStyle.faint))
            }
            DropCaption("Play with a friend")
            if pokeService.state != .ready {
                note("Pets meet through Poke. Set it up in the Poke tab first.")
            } else if pokeService.friends.isEmpty {
                note("Add a friend in the Poke tab to play together.")
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 5) {
                        ForEach(pokeService.friends) { friend in
                            PetFriendRow(friend: friend, pet: pokeService.friendPets[friend.id], isOnline: pokeService.isOnline(friend))
                        }
                    }
                }
            }
        }
    }

    private func sizeName(_ look: PetLook) -> String {
        PetLook.sizes.min { abs($0.scale - look.scale) < abs($1.scale - look.scale) }?.name ?? "Medium"
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, design: .rounded))
            .foregroundColor(DropStyle.muted)
    }

    // MARK: Choosing

    private var chooser: some View {
        HStack(alignment: .center, spacing: 20) {
            PetPortrait(look: draft, action: .sit, showsSize: true)
                .frame(width: layout.wide(90, 120), height: layout.wide(76, 100))
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(DropStyle.faint))
            VStack(alignment: .leading, spacing: 8) {
                Text(store.look == nil ? "Choose your pet" : "Change your pet")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                PetChooser(look: $draft, compact: false)
                HStack(spacing: 8) {
                    TextField("Name", text: $draft.name)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11, design: .rounded))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .frame(width: 130)
                        .onSubmit(save)
                    DropButton(title: store.look == nil ? "Adopt" : "Save", systemImage: "pawprint.fill", prominent: true, height: 24, action: save)
                        .frame(width: 90)
                    if store.look != nil {
                        DropButton(title: "Cancel", height: 24) { isEditing = false }
                            .frame(width: 66)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity)
    }

    private func save() {
        store.adopt(draft)
        isEditing = false
    }
}

/// Cat or dog, its coat and, unless compact, its size.
struct PetChooser: View {
    @Binding var look: PetLook
    let compact: Bool

    private static let swatchesPerRow = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: compact ? 8 : 10) {
                ForEach(PetLook.choices.indices, id: \.self) { index in
                    kindChip(PetLook.choices[index].kind, breed: PetLook.choices[index].breed)
                }
                swatches
            }
            if !compact {
                sizes
            }
        }
    }

    /// A cat, a dog or a poodle.
    private func kindChip(_ kind: PetKind, breed: PetBreed) -> some View {
        let selected = look.kind == kind && look.breed == breed
        // Unpicked, a poodle shows white, the others their first coat.
        let preview = PetLook(kind: kind, coat: selected ? look.coat : breed == .poodle ? 4 : 0, name: "", breed: breed)
        return Button {
            guard !selected else { return }
            // A name still the old choice's own follows the new one.
            let keepsName = look.name != look.defaultName && !look.name.isEmpty
            var changed = PetLook(kind: kind, coat: min(look.coat, kind.coats.count - 1), name: "", scale: look.scale, breed: breed)
            changed.name = keepsName ? look.name : changed.defaultName
            look = changed
        } label: {
            HStack(spacing: 4) {
                PetPortrait(look: preview, action: .stand, animated: false)
                    .frame(width: compact ? 26 : 32, height: compact ? 20 : 26)
                Text(preview.title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.white.opacity(selected ? 0.18 : 0.06)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(selected ? 0.5 : 0), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }

    /// The coats, in rows of six.
    private var swatches: some View {
        let coats = look.kind.coats
        let rows = stride(from: 0, to: coats.count, by: Self.swatchesPerRow).map { $0..<min($0 + Self.swatchesPerRow, coats.count) }
        return VStack(alignment: .leading, spacing: 5) {
            ForEach(rows, id: \.lowerBound) { row in
                HStack(spacing: 5) {
                    ForEach(row, id: \.self) { index in
                        swatch(coats[index], index: index)
                    }
                }
            }
        }
    }

    private func swatch(_ coat: PetCoat, index: Int) -> some View {
        Button {
            look.coat = index
        } label: {
            PetCoatSwatch(coat: coat, isCat: look.kind == .cat)
                .frame(width: 15, height: 15)
                .overlay(Circle().strokeBorder(Color.white.opacity(look.coat == index ? 0.95 : 0.15), lineWidth: look.coat == index ? 2 : 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .help(coat.name)
    }

    private var sizes: some View {
        HStack(spacing: 6) {
            Text("Size")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(DropStyle.muted)
            ForEach(PetLook.sizes, id: \.short) { size in
                let selected = abs(look.scale - size.scale) < 0.01
                Button {
                    look.scale = size.scale
                } label: {
                    Text(size.short)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .frame(minWidth: 18)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.white.opacity(selected ? 0.18 : 0.06)))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(selected ? 0.5 : 0), lineWidth: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
                .help(size.name)
            }
        }
    }
}

/// A coat in a little circle: its color with its stripes, patches or spots.
private struct PetCoatSwatch: View {
    let coat: PetCoat
    let isCat: Bool

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            context.clip(to: Path(ellipseIn: rect))
            context.fill(Path(rect), with: .color(coat.base.color))
            switch coat.marking {
            case .patches:
                context.fill(Path(ellipseIn: CGRect(x: -size.width * 0.2, y: size.height * 0.45, width: size.width * 0.7, height: size.height * 0.75)),
                             with: .color(coat.dark.color))
                context.fill(Path(ellipseIn: CGRect(x: size.width * 0.55, y: -size.height * 0.12, width: size.width * 0.55, height: size.height * 0.52)),
                             with: .color(coat.secondPatch(isCat: isCat).color))
            case .stripes:
                for x in [0.3, 0.6, 0.9] as [CGFloat] {
                    var stripe = Path()
                    stripe.move(to: CGPoint(x: size.width * x, y: 0))
                    stripe.addLine(to: CGPoint(x: size.width * (x - 0.3), y: size.height))
                    context.stroke(stripe, with: .color(coat.dark.color), lineWidth: size.width * 0.11)
                }
            case .spots:
                let colors = coat.spotColors
                let places: [(CGFloat, CGFloat)] = [(0.3, 0.28), (0.72, 0.32), (0.45, 0.7), (0.8, 0.75), (0.15, 0.62)]
                for (index, place) in places.enumerated() {
                    let radius = size.width * 0.13
                    context.fill(Path(ellipseIn: CGRect(x: size.width * place.0 - radius, y: size.height * place.1 - radius, width: radius * 2, height: radius * 2)),
                                 with: .color(colors[index % colors.count].color))
                }
            case .none:
                // A white chest, on a dark coat.
                if coat.light.red + coat.light.green + coat.light.blue - coat.base.red - coat.base.green - coat.base.blue > 1.5 {
                    context.fill(Path(ellipseIn: CGRect(x: size.width * 0.27, y: size.height * 0.62, width: size.width * 0.46, height: size.height * 0.46)),
                                 with: .color(coat.light.color))
                }
            }
        }
    }
}

/// A friend, their pet, and the button to play with them.
private struct PetFriendRow: View {
    @ObservedObject private var play = PetPlay.shared
    @ObservedObject private var store = PetStore.shared
    let friend: PokeService.Friend
    let pet: PetLook?
    let isOnline: Bool

    var body: some View {
        HStack(spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                if let pet {
                    PetPortrait(look: pet, action: .sit, animated: false)
                        .frame(width: 26, height: 24)
                } else {
                    Circle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 24, height: 24)
                        .overlay(Text(String(friend.name.prefix(1)).uppercased()).font(.system(size: 11, weight: .bold, design: .rounded)))
                }
                Circle()
                    .fill(isOnline ? Color.green : Color.gray)
                    .frame(width: 7, height: 7)
                    .overlay(Circle().stroke(Color.black, lineWidth: 1.5))
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(friend.name)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 9, design: .rounded))
                    .foregroundColor(DropStyle.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            buttons
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(DropStyle.faint))
    }

    private var subtitle: String {
        if play.invite(for: friend) != nil { return "Invited you to play" }
        if let pet { return "\(pet.name) the \(pet.title.lowercased())" }
        return isOnline ? "No pet yet" : "Offline"
    }

    @ViewBuilder
    private var buttons: some View {
        if play.state.friend?.id == friend.id {
            switch play.state {
            case .inviting:
                DropButton(title: "Cancel", height: 22) { play.leave() }
                    .frame(width: 64)
                    .help("Waiting for \(friend.name)…")
            case .joining:
                ProgressView().controlSize(.small).frame(width: 64)
            default:
                DropButton(title: "Leave", height: 22) { play.leave() }
                    .frame(width: 64)
            }
        } else if play.invite(for: friend) != nil {
            HStack(spacing: 4) {
                DropButton(title: "Join", systemImage: "pawprint.fill", prominent: true, height: 22) { play.join(friend) }
                    .frame(width: 64)
                    .disabled(store.look == nil)
                Button { play.decline(friend) } label: {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundColor(DropStyle.muted)
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
                .help("Not now")
            }
        } else {
            let canInvite = isOnline && store.look != nil
            DropButton(title: "Invite", systemImage: "paperplane.fill", prominent: canInvite, height: 22) { play.invite(friend) }
                .frame(width: 70)
                .disabled(!canInvite)
                .opacity(canInvite ? 1 : 0.45)
                .help(store.look == nil ? "Choose your pet first" : isOnline ? "Invite \(friend.name) to play" : "\(friend.name) is offline")
        }
    }
}
