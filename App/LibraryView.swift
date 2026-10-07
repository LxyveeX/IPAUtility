import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject var model: LibraryModel
    @State private var picker: PickerKind?
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
                    if model.hasSource {
                        HStack(spacing: 10) {
                            Label(model.folder?.lastPathComponent ?? "已选中的文件", systemImage: model.folder == nil ? "doc.on.doc" : "folder.fill").lineLimit(1)
                            Spacer()
                            Text("\(model.items.count) 个 IPA").foregroundStyle(.secondary).accessibilityIdentifier("ipaCount")
                        }.font(.subheadline)
                        if model.folder != nil {
                            Toggle("点击 App 时自动重命名", isOn: $model.autoRename).font(.subheadline)
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("当前为原文件预览。导入本地库后，可以整理副本名称。")
                                    .font(.subheadline).foregroundStyle(.secondary)
                                Button { Task { await model.importCopies(model.items.map(\.url)) } } label: { Label("导入这些 IPA 到本地库", systemImage: "square.and.arrow.down") }
                            }
                        }
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
                        emptyState(title: "文件图标，自动呈现", subtitle: "安装后回到系统“文件”查看 IPA 图标。\n需要整理名称时，再导入本地库。")
                        Button { picker = .importFiles } label: {
                            Label("导入 IPA（复制到本地库）", systemImage: "doc.badge.plus").frame(maxWidth: .infinity).padding(.vertical, 7)
                        }.buttonStyle(.borderedProminent).controlSize(.large).accessibilityIdentifier("importIPA")
                        Button { model.openLocalLibrary() } label: {
                            Label("打开本地 IPA 库", systemImage: "tray.full").frame(maxWidth: .infinity)
                        }.accessibilityIdentifier("localLibrary")
                        Text("导入会保留原文件。本地副本位于“文件 → 我的 iPad → IPA 图标 → IPA”，也可以直接用系统“文件”复制进去。显示缩略图无需导入。")
                            .font(.footnote).foregroundStyle(.secondary)
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
                    Menu {
                        Button { picker = .importFiles } label: { Label("导入 IPA（复制到本地库）", systemImage: "square.and.arrow.down") }
                        Button { model.openLocalLibrary() } label: { Label("打开本地 IPA 库", systemImage: "tray.full") }
                    } label: { Image(systemName: "plus.circle") }.accessibilityLabel("选择 IPA").disabled(model.busy)
                    Menu {
                        Button { model.refresh() } label: { Label("刷新", systemImage: "arrow.clockwise") }
                        Button { confirmBatch = true } label: { Label("批量重命名当前列表", systemImage: "textformat.abc") }
                            .disabled(model.folder == nil || model.items.isEmpty || model.busy || model.loading)
                        Button { Task { await model.undo() } } label: { Label("撤销上次重命名", systemImage: "arrow.uturn.backward") }
                            .disabled(model.undoRecords.isEmpty || model.busy || model.loading)
                        Toggle("包含子文件夹", isOn: $model.recursive).disabled(model.busy || model.loading)
                        Divider()
                        Button { showHelp = true } label: { Label("使用说明与图标检测", systemImage: "questionmark.circle") }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .onChange(of: model.recursive) { _ in model.refresh() }
            .background {
                DocumentPicker(kind: $picker, directory: model.suggestedFolder ?? model.localLibraryURL) { kind, urls in
                    applySelection(kind, urls: urls)
                }.frame(width: 0, height: 0)
            }
            .sheet(isPresented: $showHelp) { HelpView().environmentObject(model) }
            .sheet(item: $model.selected) { item in ItemDetail(item: item).environmentObject(model) }
            .alert("提示", isPresented: Binding(get: { model.message != nil && model.selected == nil }, set: { if !$0 { model.message = nil } })) {
                Button("好", role: .cancel) { model.message = nil }
            } message: { Text(model.message ?? "") }
            .confirmationDialog("按 App 名称＋版本号重命名 \(filtered.filter { $0.info != nil }.count) 个文件？", isPresented: $confirmBatch, titleVisibility: .visible) {
                Button("开始重命名") { let batch = filtered; Task { await model.rename(batch) } }
            } message: { Text("例如：微信 8.0.60.ipa。同名文件自动加序号；可以撤销本次操作。") }
        }
    }

    private func applySelection(_ kind: PickerKind, urls: [URL]) {
        guard !urls.isEmpty else { return }
        if kind == .importFiles { Task { await model.importCopies(urls) } }
        else if kind == .folder, let first = urls.first { model.chooseFolder(first) }
        else { model.chooseFiles(urls) }
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
                        if model.canRename(current.url) {
                            Button { Task { await model.rename([current]) } } label: { Label("按名称＋版本号重命名", systemImage: "textformat.abc") }.disabled(model.busy)
                        } else {
                            Button { Task { let url = current.url; dismiss(); await model.importCopies([url]) } } label: { Label("导入到本地库整理", systemImage: "square.and.arrow.down") }.disabled(model.busy)
                        }
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
                        if !model.diagnostic.isEmpty {
                            ShareLink(item: model.diagnostic) { Label("分享检测结果", systemImage: "square.and.arrow.up") }
                        }
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

enum PickerKind: String, Identifiable {
    case folder, files, importFiles
    var id: String { rawValue }
}

struct DocumentPicker: UIViewControllerRepresentable {
    @Binding var kind: PickerKind?
    let directory: URL?
    let completed: (PickerKind, [URL]) -> Void

    func makeUIViewController(context: Context) -> Presenter { Presenter() }
    func updateUIViewController(_ controller: Presenter, context: Context) {
        controller.requestedKind = kind
        controller.directory = directory
        controller.completed = { selectedKind, urls in
            kind = nil
            completed(selectedKind, urls)
        }
        DispatchQueue.main.async { controller.presentIfNeeded() }
    }

    // UIDocumentPicker owns a remote view controller. Present it using UIKit's
    // modal lifecycle rather than making it the root of a SwiftUI full-screen cover.
    final class Presenter: UIViewController, UIAdaptivePresentationControllerDelegate {
        var requestedKind: PickerKind?
        var directory: URL?
        var completed: ((PickerKind, [URL]) -> Void)?
        private var activeKind: PickerKind?
        private var pickerDelegate: SelectionDelegate?

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            presentIfNeeded()
        }

        func presentIfNeeded() {
            guard let kind = requestedKind, activeKind == nil,
                  viewIfLoaded?.window != nil, presentedViewController == nil else { return }
            activeKind = kind
            let picker = UIDocumentPickerViewController(
                forOpeningContentTypes: kind == .folder ? [.folder] : [.data],
                asCopy: kind == .importFiles)
            picker.allowsMultipleSelection = kind != .folder
            picker.shouldShowFileExtensions = true
            picker.directoryURL = directory
            picker.modalPresentationStyle = .formSheet
            pickerDelegate = SelectionDelegate { [weak self] urls in self?.finish(urls) }
            picker.delegate = pickerDelegate
            present(picker, animated: true)
            picker.presentationController?.delegate = self
        }

        private func finish(_ urls: [URL]) {
            guard let kind = activeKind else { return }
            activeKind = nil
            requestedKind = nil
            pickerDelegate = nil
            // Consume the actual delegate result before any dismissal callback.
            completed?(kind, urls)
            dismiss(animated: true)
        }

        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            finish([])
        }
    }

    final class SelectionDelegate: NSObject, UIDocumentPickerDelegate {
        let completed: ([URL]) -> Void
        private var finished = false
        init(completed: @escaping ([URL]) -> Void) { self.completed = completed }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            finish(urls)
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { finish([]) }
        private func finish(_ urls: [URL]) {
            guard !finished else { return }
            finished = true; completed(urls)
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
                    Text("缩略图由系统按需生成，无需选择文件夹或导入本地库。iCloud 中的 IPA 请先下载到本机。")
                    Text("签名时请保留并签名 IPAThumbnail.appex。若签名工具有“移除插件 / 移除扩展”选项，请关闭。")
                }
                Section("自动整理名称") {
                    Text("“导入 IPA”会复制到本地库，原文件保持原样。若系统选择器无响应，先打开本地库，再从系统“文件”将 IPA 复制到“我的 iPad → IPA 图标 → IPA”，返回本 App 刷新。")
                    Text("在本地库开启“点击 App 时自动重命名”后，点击应用卡片会将副本改为“App 名称 版本号.ipa”。")
                    Text("从系统“文件”打开的外部 IPA 会显示详情；需要重命名时，可在详情中导入到本地库。")
                    Text("同名文件加 (2)、(3) 等序号；文件内容不变。右上角菜单可批量整理、撤销上次重命名。")
                }
                Section("图标没有出现时") {
                    Button { Task { await model.runSelfCheck() } } label: {
                        Label("一键检测（无需选择文件）", systemImage: "checkmark.magnifyingglass")
                    }.disabled(model.selfChecking).accessibilityIdentifier("selfCheck")
                    if model.selfChecking { ProgressView("正在检测系统缩略图…") }
                    if !model.selfCheckReport.isEmpty {
                        Text(model.selfCheckReport).font(.footnote).textSelection(.enabled)
                        ShareLink(item: model.selfCheckReport) { Label("分享检测结果", systemImage: "square.and.arrow.up") }
                        ScrollView(.horizontal) {
                            HStack {
                                ForEach(Array(model.selfCheckImages.enumerated()), id: \.offset) { _, image in
                                    Image(uiImage: image).resizable().scaledToFit().frame(width: 80, height: 80)
                                }
                            }
                        }
                    }
                    Text("先在 App 详情中检测系统缩略图。然后退出“文件”重新打开，或用下面的新样本排除旧缓存。")
                    Button { model.createSamples(); dismiss() } label: { Label("生成缩略图测试文件", systemImage: "doc.badge.plus") }
                    Text(".ipa 与 .ipacheck 是同一内容的两种扩展名。两者均应显示蓝色 App 图标；仅 .ipacheck 正常时，说明 IPA 文件类型关联可能被其他应用占用。测试文件仅用于查看图标。")
                    Text("部分 IPA 将图标放在特殊的 Assets.car 资源中，系统可能无法读取；详情会显示具体图标来源。")
                }
                Section {
                    Text("IPA 图标 1.3 · iPadOS 16+").font(.footnote)
                    Text("图标与应用信息在本机读取。IPA 内容不会上传。ZIP 读取使用 ZIPFoundation 0.9.20（MIT）。").font(.footnote).foregroundStyle(.secondary)
                }
            }.navigationTitle("使用说明").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}
