import SwiftUI

struct ProfilesPage: View {
    @EnvironmentObject var model: AppModel
    @State private var editing: Profile?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(title: "Perfis", symbol: "square.stack.3d.up",
                       subtitle: "Combine ANC, sidetone, EQ, DPI e polling e troque tudo com um clique (ou atalho, ou automaticamente por app).")

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                ForEach(model.profiles.profiles) { p in
                    ProfileCard(profile: p, active: model.profiles.data.activeID == p.id) {
                        model.apply(p)
                    } onEdit: { editing = p }
                }
                Button { editing = model.profileFromCurrent(name: "Novo perfil") } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill").font(.system(size: 28))
                        Text("Novo perfil com o estado atual").font(.callout)
                    }
                    .foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .background(Theme.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.accent.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [5])))
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(item: $editing) { p in
            ProfileEditor(profile: p, isNew: !model.profiles.profiles.contains { $0.id == p.id }) { result in
                if let result {
                    if model.profiles.profiles.contains(where: { $0.id == result.id }) { model.profiles.update(result) }
                    else { model.profiles.add(result) }
                }
                editing = nil
            } onDelete: {
                model.profiles.delete(p.id); editing = nil
            }
            .environmentObject(model)
        }
    }
}

struct PageHeader: View {
    let title: String
    let symbol: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            DeviceGlyph(symbol: symbol, tint: Theme.accent, size: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 24, weight: .bold, design: .rounded))
                Text(subtitle).foregroundStyle(.secondary)
            }
        }
    }
}

private struct ProfileCard: View {
    let profile: Profile
    let active: Bool
    let onApply: () -> Void
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: profile.symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .background((active ? Theme.accent : Color.gray).opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(active ? Theme.accent : .primary)
                VStack(alignment: .leading) {
                    Text(profile.name).font(.headline)
                    if active { Text("Ativo").font(.caption).foregroundStyle(Theme.accent) }
                }
                Spacer()
                Button(action: onEdit) { Image(systemName: "ellipsis.circle") }.buttonStyle(.borderless)
            }
            Text(profile.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            Button(active ? "Reaplicar" : "Aplicar", action: onApply)
                .buttonStyle(.borderedProminent).tint(active ? .gray : Theme.accent)
                .controlSize(.small)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .background(.background.secondary.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(active ? Theme.accent : Color.secondary.opacity(0.2), lineWidth: active ? 2 : 1))
    }
}

private struct ProfileEditor: View {
    @EnvironmentObject var model: AppModel
    @State var profile: Profile
    let isNew: Bool
    let onDone: (Profile?) -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isNew ? "Novo perfil" : "Editar perfil").font(.title2.bold())
            Form {
                TextField("Nome", text: $profile.name)
                Picker("Ícone", selection: $profile.symbol) {
                    ForEach(Profile.symbols, id: \.self) { Label($0, systemImage: $0).labelStyle(.iconOnly).tag($0) }
                }
                Section("Fone") {
                    optionalPicker("Modo de áudio", value: $profile.ancMode, options: AncMode.allCases.map { ($0, $0.title) })
                    if profile.ancMode != nil && profile.ancMode != .off {
                        Stepper("Intensidade: \(profile.ancLevel ?? 5)", value: Binding(get: { profile.ancLevel ?? 5 }, set: { profile.ancLevel = $0 }), in: 1...10)
                    }
                    optionalInt("Sidetone", value: $profile.sidetone, range: 0...100, step: 5)
                    optionalPicker("Slot de EQ", value: $profile.eqSlot, options: (0..<6).map { ($0, "Slot \($0 + 1)") })
                }
                Section("Mouse") {
                    optionalPicker("Estágio de DPI", value: $profile.dpiStage,
                                   options: model.mouse.config.stages.enumerated().map { ($0.offset, "\($0.offset + 1) · \($0.element.dpi) DPI") })
                    optionalPicker("Polling", value: $profile.pollingHz, options: AttackShark.pollingRates.map { ($0, "\($0) Hz") })
                }
            }
            .formStyle(.grouped)
            HStack {
                if !isNew { Button("Apagar perfil", role: .destructive, action: onDelete) }
                Spacer()
                Button("Cancelar") { onDone(nil) }.keyboardShortcut(.cancelAction)
                Button("Salvar") { onDone(profile) }.keyboardShortcut(.defaultAction).disabled(profile.name.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460, height: 560)
    }

    private func optionalPicker<T: Hashable>(_ title: String, value: Binding<T?>, options: [(T, String)]) -> some View {
        Picker(title, selection: value) {
            Text("Não alterar").tag(T?.none)
            ForEach(options, id: \.0) { Text($0.1).tag(T?.some($0.0)) }
        }
    }

    private func optionalInt(_ title: String, value: Binding<Int?>, range: ClosedRange<Int>, step: Int) -> some View {
        HStack {
            Toggle(title, isOn: Binding(get: { value.wrappedValue != nil }, set: { value.wrappedValue = $0 ? range.lowerBound : nil }))
            if let v = value.wrappedValue {
                Stepper("\(v)", value: Binding(get: { v }, set: { value.wrappedValue = $0 }), in: range, step: step).fixedSize()
            }
        }
    }
}
