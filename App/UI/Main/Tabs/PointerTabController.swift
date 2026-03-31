//
//  PointerTabItemController.swift
//  tabTestStoryboards
//
//  Created by Noah Nübling on 24.07.21.
//

import Cocoa

class PointerTabController: NSViewController, NSSearchFieldDelegate {
    
    /// Legacy storyboard outlets kept so the old scene can still load safely.
    
    @IBOutlet weak var sensitivitySlider: NSSlider!
    @IBOutlet weak var sensitivityDisplay: SensitivityDisplay!
    
    @IBOutlet weak var accelerationStack: CollapsingStackView!
    @IBOutlet weak var accelerationPicker: NSPopUpButton!
    @IBOutlet weak var accelerationHint: NSTextField!
    
    private struct InstalledApp {
        let bundleID: String
        let displayName: String
        let appURL: URL
    }
    
    private let listWidth: CGFloat = 280
    private let listHeight: CGFloat = 320
    private let tabHeight: CGFloat = 430
    
    private var installedApps: [InstalledApp] = []
    private var disallowedBundleIDs: Set<String> = []
    private var appIcons: [String: NSImage] = [:]
    private var appLoadGeneration: Int = 0
    private var isLoadingApps: Bool = false
    private var searchQuery: String = ""
    
    private weak var searchField: NSSearchField?
    private weak var summaryField: NSTextField?
    private weak var listDocumentView: NSView?
    private weak var appListStack: NSStackView?
    private weak var refreshButton: NSButton?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "Exceptions"
        
        loadDisallowedBundleIDsFromConfig()
        installSimpleInterface()
        loadInstalledApps()
    }
    
    private func installSimpleInterface() {
        
        for constraint in view.constraints {
            view.removeConstraint(constraint)
        }
        for subview in view.subviews {
            subview.removeFromSuperview()
        }
        
        let wrapperView = NSView()
        wrapperView.translatesAutoresizingMaskIntoConstraints = false
        
        let masterStack = NSStackView()
        masterStack.orientation = .vertical
        masterStack.alignment = .leading
        masterStack.spacing = 10
        masterStack.translatesAutoresizingMaskIntoConstraints = false
        
        let titleField = NSTextField(labelWithString: "Exceptions")
        titleField.font = .boldSystemFont(ofSize: NSFont.systemFontSize + 2)
        
        let hint = CoolNSTextField(hintWithString: "Check apps here to exclude them from smooth scrolling.")
        hint.lineBreakMode = .byWordWrapping
        hint.cell?.wraps = true
        hint.setContentCompressionResistancePriority(.init(999), for: .horizontal)
        
        let summary = CoolNSTextField(hintWithString: "")
        summary.lineBreakMode = .byWordWrapping
        summary.cell?.wraps = true
        summary.setContentCompressionResistancePriority(.init(999), for: .horizontal)
        summaryField = summary
        
        let searchField = NSSearchField()
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholderString = "Search apps"
        searchField.delegate = self
        searchField.sendsSearchStringImmediately = true
        searchField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        searchField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        searchField.heightAnchor.constraint(equalToConstant: 22).isActive = true
        self.searchField = searchField
        
        let refreshButton = NSButton(title: "Refresh Apps", target: self, action: #selector(reloadInstalledApps))
        refreshButton.bezelStyle = .rounded
        refreshButton.setContentHuggingPriority(.required, for: .horizontal)
        refreshButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        self.refreshButton = refreshButton
        
        let controlsRow = NSStackView()
        controlsRow.orientation = .horizontal
        controlsRow.alignment = .centerY
        controlsRow.spacing = 8
        controlsRow.translatesAutoresizingMaskIntoConstraints = false
        controlsRow.widthAnchor.constraint(equalToConstant: listWidth).isActive = true
        controlsRow.addArrangedSubview(searchField)
        controlsRow.addArrangedSubview(refreshButton)
        
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.widthAnchor.constraint(equalToConstant: listWidth).isActive = true
        scrollView.heightAnchor.constraint(equalToConstant: listHeight).isActive = true
        
        let documentView = NSView(frame: NSRect(x: 0, y: 0, width: listWidth, height: listHeight))
        let listStack = NSStackView()
        listStack.orientation = .vertical
        listStack.alignment = .leading
        listStack.spacing = 4
        listStack.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(listStack)
        listStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor).isActive = true
        listStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor).isActive = true
        listStack.topAnchor.constraint(equalTo: documentView.topAnchor).isActive = true
        
        scrollView.documentView = documentView
        listDocumentView = documentView
        appListStack = listStack
        
        masterStack.addArrangedSubview(titleField)
        masterStack.addArrangedSubview(hint)
        masterStack.addArrangedSubview(controlsRow)
        masterStack.addArrangedSubview(summary)
        masterStack.addArrangedSubview(scrollView)
        
        view.addSubview(wrapperView)
        wrapperView.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
        wrapperView.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
        wrapperView.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
        wrapperView.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
        
        wrapperView.addSubview(masterStack)
        masterStack.leadingAnchor.constraint(equalTo: wrapperView.leadingAnchor, constant: 30).isActive = true
        masterStack.trailingAnchor.constraint(equalTo: wrapperView.trailingAnchor, constant: -30).isActive = true
        masterStack.topAnchor.constraint(equalTo: wrapperView.topAnchor, constant: 28).isActive = true
        masterStack.bottomAnchor.constraint(equalTo: wrapperView.bottomAnchor, constant: -20).isActive = true
        
        applyHardcodedTabWidth("exceptions", self, widthControllingTextFields: [hint, summary])
        view.heightAnchor.constraint(equalToConstant: tabHeight).isActive = true
        updateSummary()
    }
    
    @objc private func reloadInstalledApps() {
        loadInstalledApps()
    }
    
    private func loadInstalledApps() {
        
        appLoadGeneration += 1
        let generation = appLoadGeneration
        isLoadingApps = true
        
        refreshButton?.isEnabled = false
        renderStatusRow("Loading apps…")
        updateSummary(isLoading: true)
        
        let directories = applicationDirectories()
        DispatchQueue.global(qos: .userInitiated).async {
            let apps = Self.discoverInstalledApps(in: directories)
            DispatchQueue.main.async { [weak self] in
                guard let self, generation == self.appLoadGeneration else { return }
                self.installedApps = apps
                self.isLoadingApps = false
                self.refreshButton?.isEnabled = true
                self.renderInstalledApps()
            }
        }
    }
    
    private func renderInstalledApps() {
        
        guard let listDocumentView, let appListStack else { return }
        
        clearRows()
        
        let visibleApps = filteredInstalledApps()
        
        if installedApps.isEmpty {
            let emptyField = CoolNSTextField(hintWithString: "No apps found in Applications folders.")
            appListStack.addArrangedSubview(emptyField)
        } else if visibleApps.isEmpty {
            let noMatchesField = CoolNSTextField(hintWithString: "No apps match \"\(searchQuery)\".")
            appListStack.addArrangedSubview(noMatchesField)
        } else {
            for app in visibleApps {
                appListStack.addArrangedSubview(makeRow(for: app))
            }
        }
        
        listDocumentView.layoutSubtreeIfNeeded()
        let fittedHeight = max(listHeight, appListStack.fittingSize.height)
        listDocumentView.frame = NSRect(x: 0, y: 0, width: listWidth, height: fittedHeight)
        updateSummary(isLoading: false)
    }
    
    private func renderStatusRow(_ message: String) {
        
        guard let listDocumentView, let appListStack else { return }
        
        clearRows()
        let statusField = CoolNSTextField(hintWithString: message)
        appListStack.addArrangedSubview(statusField)
        listDocumentView.frame = NSRect(x: 0, y: 0, width: listWidth, height: listHeight)
    }
    
    private func clearRows() {
        
        guard let appListStack else { return }
        
        for subview in appListStack.arrangedSubviews {
            appListStack.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }
    }
    
    func controlTextDidChange(_ obj: Notification) {
        
        guard let changedField = obj.object as? NSSearchField, changedField == searchField else { return }
        
        searchQuery = changedField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if !isLoadingApps {
            renderInstalledApps()
        }
    }
    
    private func makeRow(for app: InstalledApp) -> NSView {
        
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalToConstant: listWidth).isActive = true
        
        let iconView = NSImageView()
        if let cachedIcon = appIcons[app.bundleID] {
            iconView.image = cachedIcon
        } else {
            let icon = NSWorkspace.shared.icon(forFile: app.appURL.path)
            appIcons[app.bundleID] = icon
            iconView.image = icon
        }
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 20).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 20).isActive = true
        
        let checkbox = NSButton(checkboxWithTitle: app.displayName, target: self, action: #selector(toggleException(_:)))
        checkbox.identifier = NSUserInterfaceItemIdentifier(app.bundleID)
        checkbox.toolTip = app.bundleID
        checkbox.state = disallowedBundleIDs.contains(app.bundleID) ? .on : .off
        checkbox.lineBreakMode = .byTruncatingTail
        checkbox.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        
        row.addArrangedSubview(iconView)
        row.addArrangedSubview(checkbox)
        
        return row
    }
    
    @objc private func toggleException(_ sender: NSButton) {
        
        guard let bundleID = sender.identifier?.rawValue else { return }
        
        if sender.state == .on {
            disallowedBundleIDs.insert(bundleID)
        } else {
            disallowedBundleIDs.remove(bundleID)
        }
        
        writeDisallowedBundleIDsToConfig()
        updateSummary()
    }
    
    private func updateSummary(isLoading: Bool = false) {
        
        guard let summaryField else { return }
        
        if isLoading {
            summaryField.stringValue = "Loading apps from your Applications folders…"
            return
        }
        
        let names = selectedAppNames()
        
        if names.isEmpty {
            summaryField.stringValue = "No exceptions selected. Smooth scrolling runs in every app."
            return
        }
        
        if names.count == 1 {
            summaryField.stringValue = "Disabled in: \(names[0])"
        } else if names.count <= 3 {
            summaryField.stringValue = "Disabled in: \(names.joined(separator: ", "))"
        } else {
            summaryField.stringValue = "Disabled in \(disallowedBundleIDs.count) apps, including \(names.joined(separator: ", "))"
        }
    }
    
    private func loadDisallowedBundleIDsFromConfig() {
        
        let bundleIDs: [String]
        if let raw = config("Scroll.appFilter.bundleIDs") as? [String] {
            bundleIDs = raw
        } else if let raw = config("Scroll.appFilter.bundleIDs") as? [NSString] {
            bundleIDs = raw.map { $0 as String }
        } else if let raw = config("Scroll.appFilter.bundleIDs") as? NSArray {
            bundleIDs = raw.compactMap { $0 as? String }
        } else {
            bundleIDs = []
        }
        
        disallowedBundleIDs = Set(bundleIDs)
    }
    
    private func writeDisallowedBundleIDsToConfig() {
        
        setConfig("Scroll.appFilter.mode", "excludeListed" as NSString)
        setConfig("Scroll.appFilter.bundleIDs", disallowedBundleIDs.sorted() as NSArray)
        commitConfig()
    }
    
    private func selectedAppNames() -> [String] {
        
        let names = disallowedBundleIDs.map(appDisplayName(bundleIdentifier:))
        return names.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }
    
    private func filteredInstalledApps() -> [InstalledApp] {
        
        guard !searchQuery.isEmpty else { return installedApps }
        
        return installedApps.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchQuery)
                || $0.bundleID.localizedCaseInsensitiveContains(searchQuery)
        }
    }
    
    private func appDisplayName(bundleIdentifier: String) -> String {
        
        if let app = installedApps.first(where: { $0.bundleID == bundleIdentifier }) {
            return app.displayName
        }
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier),
           let bundle = Bundle(url: appURL) {
            return (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? appURL.deletingPathExtension().lastPathComponent
        }
        
        return bundleIdentifier
    }
    
    private func applicationDirectories() -> [URL] {
        
        let homeApplications = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        let candidates = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            homeApplications,
        ]
        
        return candidates.filter {
            FileManager.default.fileExists(atPath: $0.path)
        }
    }
    
    private static func discoverInstalledApps(in directories: [URL]) -> [InstalledApp] {
        
        var appsByBundleID: [String: InstalledApp] = [:]
        let fileManager = FileManager.default
        
        for directory in directories {
            guard let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
                continue
            }
            
            for case let url as URL in enumerator {
                guard url.pathExtension == "app" else { continue }
                guard let bundle = Bundle(url: url) else { continue }
                guard let bundleID = bundle.bundleIdentifier, !bundleID.isEmpty else { continue }
                
                let displayName =
                    (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String) ??
                    (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String) ??
                    url.deletingPathExtension().lastPathComponent
                
                if appsByBundleID[bundleID] == nil {
                    appsByBundleID[bundleID] = InstalledApp(bundleID: bundleID, displayName: displayName, appURL: url)
                }
            }
        }
        
        return appsByBundleID.values.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }
}
