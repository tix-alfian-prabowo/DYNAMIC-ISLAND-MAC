import SwiftUI

/// The Pet tab: your pet (choose it, let it out or call it home, throw it a ball) and friends to
/// play with: invite them, or join a friend who invited you.
struct PetTabView: View {
    @EnvironmentObject var layout: IslandLayout
    @EnvironmentObject var pokeService: PokeService
    @ObservedObject private var store = PetStore.shared
    @ObservedObject private var play = PetPlay.shared
    @ObservedObject private var world = PetWorld.shared
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
                    Text(look.name)
                        .font(.system(size: layout.wide(18, 24), weight: .bold, design: .rounded))
                    Text("\(look.coatStyle.name) \(look.kind.title.lowercased()) · \(store.isOut ? "out on the desktop" : "asleep in the notch")")
                        .font(.system(size: layout.wide(10, 11), design: .rounded))
                        .foregroundColor(DropStyle.muted)
                }
            }
            HStack(spacing: 8) {
                DropButton(title: store.isOut ? "Call Home" : "Let Out", systemImage: store.isOut ? "house.fill" : "pawprint.fill",
                           prominent: true, height: 24) {
                    store.isOut.toggle()
                }
                .frame(width: 100)
                let isFull = world.ballCount >= PetWorld.maxBalls
                DropButton(title: world.ballCount > 0 ? "Ball \(world.ballCount)/\(PetWorld.maxBalls)" : "Ball", systemImage: "tennisball.fill", height: 24) {
                    play.throwBall()
                }
                .frame(width: 92)
                .disabled(isFull)
                .opacity(isFull ? 0.45 : 1)
                .help(isFull ? "Ten balls are out: wait for the pets to bring some back" : "Throw a ball from the notch for the pets to fetch (up to \(PetWorld.maxBalls))")
                DropButton(title: "Edit", height: 24) {
                    draft = look
                    isEditing = true
                }
                .frame(width: 54)
            }
            Text("Click it to say hi, drag it to move it.")
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

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, design: .rounded))
            .foregroundColor(DropStyle.muted)
    }

    // MARK: Choosing

    private var chooser: some View {
        HStack(alignment: .center, spacing: 20) {
            PetPortrait(look: draft, action: .sit)
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

/// Cat or dog, and its coat.
struct PetChooser: View {
    @Binding var look: PetLook
    let compact: Bool

    var body: some View {
        HStack(spacing: compact ? 8 : 10) {
            ForEach(PetKind.allCases, id: \.self) { kind in
                let selected = look.kind == kind
                Button {
                    guard kind != look.kind else { return }
                    // A name still the other kind's own follows the kind.
                    let keepsName = look.name != look.kind.defaultName && !look.name.isEmpty
                    look = PetLook(kind: kind, coat: min(look.coat, kind.coats.count - 1), name: keepsName ? look.name : kind.defaultName)
                } label: {
                    HStack(spacing: 4) {
                        PetPortrait(look: PetLook(kind: kind, coat: selected ? look.coat : 0, name: ""), action: .stand, animated: false)
                            .frame(width: compact ? 26 : 32, height: compact ? 20 : 26)
                        Text(kind.title)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.white.opacity(selected ? 0.18 : 0.06)))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(selected ? 0.5 : 0), lineWidth: 1))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 5) {
                ForEach(look.kind.coats.indices, id: \.self) { index in
                    let coat = look.kind.coats[index]
                    Button {
                        look.coat = index
                    } label: {
                        Circle()
                            .fill(coat.base.color)
                            .overlay(alignment: .topTrailing) {
                                if coat.marking == .patches {
                                    Circle().fill(coat.dark.color).frame(width: 6, height: 6).offset(x: -1, y: 1)
                                }
                            }
                            .clipShape(Circle())
                            .frame(width: 15, height: 15)
                            .overlay(Circle().strokeBorder(Color.white.opacity(look.coat == index ? 0.95 : 0.15), lineWidth: look.coat == index ? 2 : 1))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help(coat.name)
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
        if let pet { return "\(pet.name) the \(pet.kind.title.lowercased())" }
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
