import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject var model: LibraryModel
    @State private var folderPicker = false
    @State private var showHelp = false
    @State private var confirmBatch = false
    @State private var search = ""
    private var filtered: [IPAItem] {
        guard !search.isEmpty else { return model.items }
        return model.items.filter { $0.title.localizedCaseInsensitiveContains(search) || $0.filename.localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    hero
                    if model.folder != nil {
                        HStack(spacing: 10) {
                            Label(model.folder?.lastPathComponent ?? "", systemImage: "folder.fill").lineLimit(1)
                            Spacer()
                            Text("\(model.items.count) 个 IPA").foregroundStyle(.secondary)
                        }.font(.subheadline)
                        Toggle("点击 App 时自动重命名", isOn: $model.autoRename)
                            .font(.subheadline)
                        if model.loading || model.busy {
                            HStack { ProgressView(); Text(model.progress).font(.subheadline).foregroundStyle(.secondary) }
                        }
                        if filtered.isEmpty && !model.loading {
                            emptyState(title: search.isEmpty ? "这个文件夹还没有 IPA" : "没有匹配的 App",
                                       subtitle: search.isEmpty ? "把文件放进选定文件夹，返回这里后会重新读取。" : "试试 App 名称或文件名。")
                        } else {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 155, maximum: 240), spacing: 16)], spacing: 16) {
                                ForEach(filtered) { item in
                                    Button { Task { await model.open(item) } } label: { AppCard(item: item) }
                                        .buttonStyle(.plain).disabled(model.busy || model.loading)
                                }
                            }
                        }
                    } else {
                        emptyState(title: "把 IPA 整理得一目了然", subtitle: "选择“下载”中存放 IPA 的子文件夹。\n文件会保留在原位置。")
                        Button { folderPicker = true } label: {
                            Label("选择 IPA 文件夹", systemImage: "folder.badge.plus").frame(maxWidth: .infinity).padding(.vertical, 7)
                        }.buttonStyle(.borderedProminent).controlSize(.large)
                    }
                }.padding(24).frame(maxWidth: 1200)
                    .frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("IPA 图标")
            .searchable(text: $search, prompt: "搜索 App 或文件名")
            .refreshable { model.refresh() }
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button { folderPicker = true } label: { Image(systemName: "folder.badge.plus") }.accessibilityLabel("选择文件夹")
                        .disabled(model.busy)
                    Menu {
                        Button { model.refresh() } label: { Label("刷新", systemImage: "arrow.clockwise") }
                        Button { confirmBatch = true } label: { Label("批量重命名当前列表", systemImage: "textformat.abc") }
                            .disabled(model.items.isEmpty || model.busy || model.loading)
                        Button { Task { await model.undo() } } label: { Label("撤销上次重命名", systemImage: "arrow.uturn.backward") }
                            .disabled(model.undoRecords.isEmpty || model.busy || model.loading)
                        Toggle("包含子文件夹", isOn: $model.recursive).disabled(model.busy || model.loading)
                        Divider()
                        Button { showHelp = true } label: { Label("使用说明与图标检测", systemImage: "questionmark.circle") }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .onChange(of: model.recursive) { _ in model.refresh() }
            .sheet(isPresented: $folderPicker) { FolderPicker { model.chooseFolder($0) } }
            .sheet(isPresented: $showHelp) { HelpView().environmentObject(model) }
            .sheet(item: $model.selected) { item in ItemDetail(item: item).environmentObject(model) }
            .alert("提示", isPresented: Binding(get: { model.message != nil && model.selected == nil }, set: { if !$0 { model.message = nil } })) {
                if model.pendingOpen != nil { Button("选择所在文件夹") { model.message = nil; folderPicker = true } }
                Button("好", role: .cancel) { model.message = nil }
            } message: { Text(model.message ?? "") }
            .confirmationDialog("按 App 名称＋版本号重命名 \(filtered.filter { $0.info != nil }.count) 个文件？", isPresented: $confirmBatch, titleVisibility: .visible) {
                Button("开始重命名") { let batch = filtered; Task { await model.rename(batch) } }
            } message: { Text("例如：微信 8.0.60.ipa。同名文件自动加序号；可以撤销本次操作。") }
        }
    }

    private var hero: some View {
        HStack(spacing: 18) {
            Image("BrandMark").resizable().frame(width: 74, height: 74).clipShape(RoundedRectangle(cornerRadius: 17))
            VStack(alignment: .leading, spacing: 6) {
                Text("一眼认出每个 App").font(.title2.bold())
                Text("文件图标 · 名称识别 · 版本整理").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }.padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
    }

    private func emptyState(title: String, subtitle: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "square.grid.2x2").font(.system(size: 44, weight: .light)).foregroundStyle(.cyan)
            Text(title).font(.title3.bold())
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.padding(.vertical, 44).frame(maxWidth: .infinity)
    }
}

struct AppIconView: View {
    let data: Data?
    var size: CGFloat = 76
    var body: some View {
        Group {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: size * 0.22)
                    .fill(Color.cyan.opacity(0.13))
                    .overlay(Image(systemName: "app.dashed").font(.system(size: size * 0.43)).foregroundStyle(.secondary))
            }
        }.frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: size * 0.22))
    }
}

struct AppCard: View {
    let item: IPAItem
    var body: some View {
        VStack(spacing: 10) {
            AppIconView(data: item.info?.icon)
            Text(item.title).font(.headline).lineLimit(2).multilineTextAlignment(.center).frame(height: 43)
            Text(item.info?.version ?? "读取失败").font(.caption.weight(.medium))
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(Color.cyan.opacity(0.12), in: Capsule())
            Text(item.filename).font(.caption2).foregroundStyle(.secondary).lineLimit(2).frame(height: 30)
        }.frame(maxWidth: .infinity).padding(18)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
            .accessibilityElement(children: .combine)
    }
}

struct ItemDetail: View {
    let item: IPAItem
    @EnvironmentObject var model: LibraryModel
    @Environment(\.dismiss) var dismiss
    private var current: IPAItem { model.items.first(where: { $0.id == item.id }) ?? item }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 12) {
                        AppIconView(data: current.info?.icon, size: 100)
                        Text(current.title).font(.title2.bold())
                        Text(current.info?.version ?? "读取失败").foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity).padding(.vertical, 18)
                }
                if let error = current.error { Section("读取信息") { Text(error) } }
                if let info = current.info {
                    Section("文件") {
                        row("当前名称", current.filename)
                        row("标准名称", info.suggestedName)
                        row("大小", ByteCountFormatter.string(fromByteCount: current.size, countStyle: .file))
                        Button { Task { await model.rename([current]) } } label: { Label("按名称＋版本号重命名", systemImage: "textformat.abc") }.disabled(model.busy)
                        if !model.undoRecords.isEmpty {
                            Button { Task { await model.undo() } } label: { Label("撤销上次重命名", systemImage: "arrow.uturn.backward") }.disabled(model.busy)
                        }
                        ShareLink(item: current.url) { Label("分享 IPA", systemImage: "square.and.arrow.up") }.disabled(model.busy)
                    }
                    Section("应用信息") {
                        row("Bundle ID", info.bundleID)
                        row("构建号", info.build)
                        row("最低系统", info.minimumOS)
                        row("图标来源", info.iconSource)
                    }
                    Section("“文件”中的图标") {
                        Text("这里的检测会请求系统生成缩略图，可核对扩展安装后的效果。")
                            .font(.footnote).foregroundStyle(.secondary)
                        Button { model.checkThumbnail(current.url) } label: { Label("检测系统缩略图", systemImage: "photo") }
                            .disabled(model.checking || model.busy)
                        if model.checking { ProgressView() }
                        if !model.diagnostic.isEmpty { Text(model.diagnostic).font(.footnote).textSelection(.enabled) }
                        if let image = model.diagnosticImage { Image(uiImage: image).resizable().scaledToFit().frame(width: 100, height: 100) }
                    }
                }
            }.navigationTitle("App 详情").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
                .onAppear { model.clearDiagnostic() }
                .onDisappear { model.clearDiagnostic() }
                .alert("提示", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
                    Button("好", role: .cancel) { model.message = nil }
                } message: { Text(model.message ?? "") }
        }
    }
    private func row(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled)
        }
    }
}

struct FolderPicker: UIViewControllerRepresentable {
    let selected: (URL) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(selected: selected) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let selected: (URL) -> Void
        init(selected: @escaping (URL) -> Void) { self.selected = selected }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let url = urls.first { selected(url) }
        }
    }
}

struct HelpView: View {
    @EnvironmentObject var model: LibraryModel
    @Environment(\.dismiss) var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("在系统“文件”里显示图标") {
                    Text("安装后先打开本 App 一次，再到“文件”查看 IPA。右上角菜单切换为“图标”视图，并开启“显示图标预览”（如果菜单提供）。")
                    Text("缩略图由系统按需调用扩展生成。iCloud 中的 IPA 请先下载到本机。")
                    Text("签名时请保留并签名 IPAThumbnail.appex。若签名工具有“移除插件 / 移除扩展”选项，请关闭。")
                }
                Section("自动整理名称") {
                    Text("选择“下载”下的 IPA 文件夹。开启“点击 App 时自动重命名”后，点击本 App 中的应用卡片会改为“App 名称 版本号.ipa”。")
                    Text("通过系统“打开方式”交给本 App 的 IPA，也会在已授权的文件夹内执行同样操作。系统选择其他打开方式时，需要手动选择 IPA 图标。")
                    Text("同名文件加 (2)、(3) 等序号；文件内容不变。右上角菜单可批量整理、撤销上次重命名。")
                }
                Section("图标没有出现时") {
                    Text("先在 App 详情中检测系统缩略图。然后退出“文件”重新打开，或用下面的新样本排除旧缓存。")
                    Button { model.createSamples(); dismiss() } label: { Label("生成缩略图测试文件", systemImage: "doc.badge.plus") }
                    Text(".ipa 与 .ipacheck 是同一内容的两种扩展名。两者均应显示蓝色 App 图标；仅 .ipacheck 正常时，说明 IPA 文件类型关联可能被其他应用占用。测试文件仅用于查看图标。")
                    Text("部分 IPA 将图标放在特殊的 Assets.car 资源中，系统可能无法读取；详情会显示具体图标来源。")
                }
                Section {
                    Text("IPA 图标 1.0 · iPadOS 16+").font(.footnote)
                    Text("图标与应用信息在本机读取。IPA 内容不会上传。ZIP 读取使用 ZIPFoundation 0.9.20（MIT）。").font(.footnote).foregroundStyle(.secondary)
                }
            }.navigationTitle("使用说明").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}
