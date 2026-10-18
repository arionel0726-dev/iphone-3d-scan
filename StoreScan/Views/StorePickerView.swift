import SwiftUI

/// Store + optional target layout picker. Layouts come back nested inside
/// GET /api/stores (Store.layouts) — the existing endpoint already supports
/// this, so no new API was added for it. Picking no layout means "create a
/// new layout from this scan" (targetLayoutId: nil in the DTO), decided
/// later by the manager in the web review screen.
struct StorePickerView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedStoreId: UUID?
    @State private var selectedLayoutId: UUID?

    private var selectedStore: Store? {
        appState.stores.first { $0.id == selectedStoreId }
    }

    var body: some View {
        NavigationStack {
            Group {
                if appState.isLoadingStores {
                    ProgressView("Загрузка магазинов…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = appState.storesLoadError {
                    ContentUnavailableMessage(
                        systemImage: "wifi.slash",
                        title: "Не удалось загрузить магазины",
                        message: error
                    ) {
                        Button("Повторить") { Task { await appState.loadStores() } }
                            .buttonStyle(.borderedProminent)
                    }
                } else if appState.stores.isEmpty {
                    ContentUnavailableMessage(
                        systemImage: "building.2",
                        title: "Нет доступных магазинов",
                        message: "Магазины создаются в веб-приложении планировщика."
                    ) {
                        Button("Обновить") { Task { await appState.loadStores() } }
                    }
                } else {
                    List {
                        Section("Магазин") {
                            ForEach(appState.stores) { store in
                                Button {
                                    selectedStoreId = store.id
                                    selectedLayoutId = nil
                                } label: {
                                    HStack {
                                        Text(store.name)
                                        Spacer()
                                        if selectedStoreId == store.id {
                                            Image(systemName: "checkmark").foregroundStyle(.tint)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        if let selectedStore {
                            Section("Планировка") {
                                Button {
                                    selectedLayoutId = nil
                                } label: {
                                    HStack {
                                        Text("Новая планировка из скана")
                                        Spacer()
                                        if selectedLayoutId == nil {
                                            Image(systemName: "checkmark").foregroundStyle(.tint)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)

                                ForEach(selectedStore.layouts) { layout in
                                    Button {
                                        selectedLayoutId = layout.id
                                    } label: {
                                        HStack {
                                            VStack(alignment: .leading) {
                                                Text(layout.name)
                                                Text("\(layout.widthCm) × \(layout.depthCm) см")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                            if selectedLayoutId == layout.id {
                                                Image(systemName: "checkmark").foregroundStyle(.tint)
                                            }
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Сканирование магазина")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if let name = appState.currentUserName {
                            Text(name)
                        }
                        Button("Выйти", role: .destructive) {
                            Task { await appState.signOut() }
                        }
                    } label: {
                        Image(systemName: "person.circle")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let selectedStore {
                    Button {
                        let layout = selectedStore.layouts.first { $0.id == selectedLayoutId }
                        appState.beginScan(store: selectedStore, targetLayout: layout)
                    } label: {
                        Text("Сканировать")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding()
                    .background(.bar)
                }
            }
        }
        .task { if appState.stores.isEmpty { await appState.loadStores() } }
    }
}

/// A tiny stand-in for ContentUnavailableView so this file works on the
/// iOS 16 deployment target (ContentUnavailableView itself is iOS 17+).
private struct ContentUnavailableMessage<Actions: View>: View {
    let systemImage: String
    let title: String
    let message: String
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage).font(.system(size: 40)).foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            actions
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    StorePickerView().environmentObject(AppState())
}
