import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct PlannerView: View {
    @StateObject private var model = PlannerModel()

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(model: model)
                .frame(width: 320)
            Divider()
            ZStack(alignment: .top) {
                PoolMapView(model: model)
                    .ignoresSafeArea()
                if model.poolCenter == nil {
                    Text("Double-tap the map to place the pool")
                        .font(.callout.weight(.medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.top, 12)
                }
            }
        }
        .onAppear { model.start() }
        .sheet(isPresented: Binding(
            get: { model.exportURLs != nil },
            set: { if !$0 { model.exportURLs = nil } }
        )) {
            if let urls = model.exportURLs {
                ActivityView(items: urls)
            }
        }
    }
}

/// UIActivityViewController wrapper — the standard share sheet.
private struct ActivityView: UIViewControllerRepresentable {
    let items: [URL]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

struct SidebarView: View {
    @ObservedObject var model: PlannerModel
    @State private var scenarioName = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var showFileImporter = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Pool Placement Planner")
                        .font(.headline)
                    Spacer()
                    Button {
                        model.undo()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .disabled(!model.canUndo)
                    Button {
                        model.redo()
                    } label: {
                        Image(systemName: "arrow.uturn.forward")
                    }
                    .disabled(!model.canRedo)
                }
                .buttonStyle(.bordered)

                searchSection
                shapeSection
                dimensionsSection
                rotationSection
                siteSection
                pinsSection
                measureSection
                sitePlanSection
                rulesSection
                scenariosSection
                unitsSection
                exportSection
                readoutSection

                Text("Planning aid, not a survey. Verify requirements with your local building/zoning authority.")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
    }

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Address", systemImage: "magnifyingglass")
                .font(.subheadline.weight(.semibold))
            HStack {
                TextField("Search address…", text: $model.searchText)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .onSubmit { model.search() }
                if model.isSearching {
                    ProgressView()
                } else {
                    Button("Go") { model.search() }
                        .buttonStyle(.bordered)
                }
            }
            if let err = model.searchError {
                Text(err).font(.footnote).foregroundStyle(.red)
            }
        }
    }

    private var shapeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Pool", systemImage: "circle.dashed")
                .font(.subheadline.weight(.semibold))
            Picker("Shape", selection: $model.shape) {
                Text("Oval").tag(PoolShapeKind.oval)
                Text("Round").tag(PoolShapeKind.round)
                Text("Rectangle").tag(PoolShapeKind.rect)
            }
            .pickerStyle(.segmented)
            Button {
                model.placePoolAtMapCenter()
            } label: {
                Label(
                    model.poolCenter == nil ? "Place pool at map center" : "Move pool to map center",
                    systemImage: "plus.circle"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            Menu {
                Section("Above-ground") {
                    ForEach(PoolPreset.aboveGround) { p in
                        Button(p.name) { model.apply(p) }
                    }
                }
                Section("Inground") {
                    ForEach(PoolPreset.inground) { p in
                        Button(p.name) { model.apply(p) }
                    }
                }
            } label: {
                Label("Presets", systemImage: "list.bullet")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    private var dimensionsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if model.shape == .round {
                dimensionRow(
                    "Diameter",
                    value: $model.widthFt,
                    display: model.formatter.poolDimension(model.widthFt * Geo.metersPerFoot)
                )
            } else {
                dimensionRow(
                    "Width",
                    value: $model.widthFt,
                    display: model.formatter.poolDimension(model.widthFt * Geo.metersPerFoot)
                )
                dimensionRow(
                    "Length",
                    value: $model.lengthFt,
                    display: model.formatter.poolDimension(model.lengthFt * Geo.metersPerFoot)
                )
            }
        }
    }

    private func dimensionRow(_ label: LocalizedStringKey, value: Binding<Double>, display: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(display)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Stepper(label, value: value, in: 4...60, step: 0.5)
                .labelsHidden()
        }
    }

    private var rotationSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Rotation", systemImage: "rotate.right")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(Int(model.rotationDeg))°")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: $model.rotationDeg, in: 0...180, step: 1)
                .disabled(model.shape == .round)
            Text("Tip: two-finger twist on the pool rotates it too.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
    }

    private var unitsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Units & view", systemImage: "ruler")
                .font(.subheadline.weight(.semibold))
            Picker("Units", selection: $model.units) {
                Text("ft / in").tag(UnitSystem.imperial)
                Text("m").tag(UnitSystem.metric)
                Text("Mixed").tag(UnitSystem.mixed)
            }
            .pickerStyle(.segmented)
            Toggle("Clean view (hide handles)", isOn: $model.cleanView)
                .font(.callout)
            DisclosureGroup {
                TextField(
                    "https://…/{z}/{x}/{y}.png",
                    text: Binding(
                        get: { model.customTileTemplate ?? "" },
                        set: { model.customTileTemplate = $0.isEmpty ? nil : $0 }
                    )
                )
                .textFieldStyle(.roundedBorder)
                .font(.footnote)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                Text("Replaces Apple imagery where it's stale (e.g. a Mapbox key URL). Leave empty for Apple Maps. Custom tiles don't appear in exports.")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            } label: {
                Text("Custom tile layer")
                    .font(.callout)
            }
        }
    }

    // MARK: Property & structures

    private var siteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Property & structures", systemImage: "square.dashed")
                .font(.subheadline.weight(.semibold))
            if model.drawMode == .none {
                HStack {
                    Button(model.lot.count >= 3 ? "Redraw lot" : "Draw lot") {
                        model.beginDraw(.lot)
                    }
                    Button("Add structure") {
                        model.beginDraw(.structure)
                    }
                    Button("Add zone") {
                        model.beginDraw(.zone)
                    }
                }
                .buttonStyle(.bordered)
                HStack {
                    if model.lot.count >= 3 {
                        Button("Clear lot", role: .destructive) { model.clearLot() }
                    }
                    if !model.structures.isEmpty {
                        Button("Remove structure (\(model.structures.count))", role: .destructive) {
                            model.removeLastStructure()
                        }
                    }
                }
                .buttonStyle(.borderless)
                .font(.footnote)
                zoneList
            } else {
                Text(drawModeHint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Finish (\(model.draftPoints.count))") { model.finishDraw() }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.draftPoints.count < 3)
                    Button("Cancel") { model.cancelDraw() }
                        .buttonStyle(.bordered)
                }
            }
        }
    }

    private var drawModeHint: String {
        switch model.drawMode {
        case .lot: return String(localized: "Tap the map at each property corner, then Finish.")
        case .structure: return String(localized: "Tap the map at each structure corner, then Finish.")
        case .zone: return String(localized: "Tap the map around the easement/zone, then Finish.")
        case .none: return ""
        }
    }

    @ViewBuilder
    private var zoneList: some View {
        ForEach(Array(model.zones.enumerated()), id: \.element.id) { i, zone in
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Circle()
                        .fill(Color(red: 0xD9 / 255, green: 0x82 / 255, blue: 0x2B / 255))
                        .frame(width: 10, height: 10)
                    Text("Zone \(i + 1)")
                    Spacer()
                    Toggle("Setback", isOn: Binding(
                        get: { zone.setbackM != nil },
                        set: { on in
                            model.recordUndo()
                            model.zones[i].setbackM = on ? 1.5 : nil
                        }
                    ))
                    .labelsHidden()
                    Button {
                        model.removeZone(id: zone.id)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .tint(.red)
                }
                .font(.callout)
                if let setback = zone.setbackM {
                    HStack {
                        Slider(
                            value: Binding(
                                get: { setback },
                                set: { model.zones[i].setbackM = $0 }
                            ),
                            in: 0...10, step: 0.05
                        )
                        Text(model.formatter.distance(setback))
                            .font(.footnote)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: Pins

    private var pinsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Equipment & safety pins", systemImage: "mappin.and.ellipse")
                .font(.subheadline.weight(.semibold))
            Menu {
                Section("Equipment (measured)") {
                    ForEach([PinKind.equipmentSet, .heatPump, .pump, .filter]) { kind in
                        Button(kind.label, systemImage: kind.symbolName) { model.requestPin(kind) }
                    }
                }
                Section("Safety (labels)") {
                    ForEach([PinKind.ladder, .gate, .selfClosingGate, .doorAlarm, .fenceOpening]) { kind in
                        Button(kind.label, systemImage: kind.symbolName) { model.requestPin(kind) }
                    }
                }
            } label: {
                Label("Add pin at map center", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            ForEach(model.pins) { pin in
                HStack {
                    Image(systemName: pin.kind.symbolName)
                        .frame(width: 20)
                    Text(pin.kind.label)
                    Spacer()
                    Button {
                        model.removePin(id: pin.id)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .tint(.red)
                }
                .font(.callout)
            }
            if !model.pins.isEmpty {
                Text("Drag a pin on the map to reposition it.")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: Measure

    private var measureSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Measure", systemImage: "ruler")
                .font(.subheadline.weight(.semibold))
            HStack {
                if model.measureMode {
                    Button("Stop measuring") { model.toggleMeasure() }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("Measure distances") { model.toggleMeasure() }
                        .buttonStyle(.bordered)
                }
                if model.measureMode, !model.measurePoints.isEmpty {
                    Button("Clear") { model.clearMeasure() }
                        .buttonStyle(.bordered)
                }
            }
            if model.measureMode {
                if let d = model.measureDistances {
                    let f = model.formatter
                    Text("Last: \(f.distance(d.last))  ·  Total: \(f.distance(d.total))")
                        .font(.callout)
                        .monospacedDigit()
                } else {
                    Text("Tap the map to measure. Taps snap to pool, lot, structure edges and pins.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Site plan

    private var sitePlanSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Site plan", systemImage: "doc.viewfinder")
                .font(.subheadline.weight(.semibold))
            if model.sitePlan == nil {
                HStack {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Text("Photos")
                    }
                    Button("File (PDF/image)") { showFileImporter = true }
                }
                .buttonStyle(.bordered)
                Text("Overlay a survey or site plan and scale it to match the map.")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            } else {
                sitePlanControls
            }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    model.importSitePlan(data: data, isPDF: false)
                }
                photoItem = nil
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.pdf, .image]
        ) { result in
            guard case .success(let url) = result else { return }
            let secured = url.startAccessingSecurityScopedResource()
            defer { if secured { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url) {
                model.importSitePlan(data: data, isPDF: url.pathExtension.lowercased() == "pdf")
            }
        }
    }

    @ViewBuilder
    private var sitePlanControls: some View {
        sitePlanSlider(
            "Width on ground",
            value: Binding(
                get: { model.sitePlan?.widthM ?? 30 },
                set: { model.sitePlan?.widthM = $0 }
            ),
            range: 2...120, step: 0.5,
            display: model.formatter.distance(model.sitePlan?.widthM ?? 30)
        )
        sitePlanSlider(
            "Rotation",
            value: Binding(
                get: { model.sitePlan?.rotationDeg ?? 0 },
                set: { model.sitePlan?.rotationDeg = $0 }
            ),
            range: 0...360, step: 1,
            display: "\(Int(model.sitePlan?.rotationDeg ?? 0))°"
        )
        sitePlanSlider(
            "Opacity",
            value: Binding(
                get: { model.sitePlan?.opacity ?? 0.7 },
                set: { model.sitePlan?.opacity = $0 }
            ),
            range: 0.1...1, step: 0.05,
            display: "\(Int((model.sitePlan?.opacity ?? 0.7) * 100)) %"
        )
        Toggle("White backing sheet", isOn: Binding(
            get: { model.sitePlan?.whiteBacking ?? true },
            set: { model.sitePlan?.whiteBacking = $0 }
        ))
        .font(.callout)
        HStack {
            Button("Center on map") { model.centerSitePlanAtMapCenter() }
            Button("Remove", role: .destructive) { model.removeSitePlan() }
        }
        .buttonStyle(.bordered)
    }

    private func sitePlanSlider(
        _ label: LocalizedStringKey, value: Binding<Double>,
        range: ClosedRange<Double>, step: Double, display: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                Spacer()
                Text(display)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
            Slider(value: value, in: range, step: step)
        }
    }

    // MARK: Export

    private var exportSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Export", systemImage: "square.and.arrow.up")
                .font(.subheadline.weight(.semibold))
            Button {
                model.export()
            } label: {
                if model.isExporting {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Label("Export plan (PDF + PNG)", systemImage: "doc.richtext")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isExporting)
            Text("Snapshots the visible map with all overlays, a scale bar and a compliance summary.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
            if let err = model.exportError {
                Text(err).font(.footnote).foregroundStyle(.red)
            }
        }
    }

    // MARK: Scenarios

    private var scenariosSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Scenarios", systemImage: "square.stack.3d.up")
                .font(.subheadline.weight(.semibold))
            HStack {
                TextField("Scenario name…", text: $scenarioName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { saveScenario() }
                Button("Save") { saveScenario() }
                    .buttonStyle(.bordered)
                    .disabled(scenarioName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            ForEach(model.scenarios) { s in
                HStack {
                    Button {
                        model.loadScenario(s)
                    } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(s.name)
                            Text("\(Int(s.widthFt)) × \(Int(s.lengthFt)) ft \(shapeName(s.shape)), \(Int(s.rotationDeg))°")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Button {
                        model.removeScenario(id: s.id)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .tint(.red)
                }
                .font(.callout)
            }
        }
    }

    private func saveScenario() {
        model.saveScenario(named: scenarioName)
        scenarioName = ""
    }

    private func shapeName(_ s: PoolShapeKind) -> String {
        switch s {
        case .oval: return String(localized: "oval")
        case .round: return String(localized: "round")
        case .rect: return String(localized: "rectangle")
        }
    }

    // MARK: Rules

    private var rulesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Rules", systemImage: "checkmark.shield")
                .font(.subheadline.weight(.semibold))
            Text("Example values — verify with your municipality.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
            distanceRuleRow("Property-line setback", keyPath: \.propertyLineSetbackM, defaultValue: 1.5)
            distanceRuleRow("Structure setback", keyPath: \.structureSetbackM, defaultValue: 1.5)
            distanceRuleRow("Equipment–pool clearance", keyPath: \.equipmentPoolClearanceM, defaultValue: 1.0)
            distanceRuleRow("Equipment–lot setback", keyPath: \.equipmentLotSetbackM, defaultValue: 1.5)
            coverageRuleRow
        }
    }

    private func distanceRuleRow(
        _ label: LocalizedStringKey,
        keyPath: WritableKeyPath<RuleProfile, Double?>,
        defaultValue: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle(isOn: Binding(
                get: { model.rules[keyPath: keyPath] != nil },
                set: { model.rules[keyPath: keyPath] = $0 ? defaultValue : nil }
            )) {
                HStack {
                    Text(label)
                    Spacer()
                    if let v = model.rules[keyPath: keyPath] {
                        Text(model.formatter.distance(v))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .font(.callout)
            if let v = model.rules[keyPath: keyPath] {
                Slider(
                    value: Binding(
                        get: { v },
                        set: { model.rules[keyPath: keyPath] = $0 }
                    ),
                    in: 0...5,
                    step: 0.05
                )
            }
        }
    }

    private var coverageRuleRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle(isOn: Binding(
                get: { model.rules.maxLotCoveragePct != nil },
                set: { model.rules.maxLotCoveragePct = $0 ? 15 : nil }
            )) {
                HStack {
                    Text("Max lot coverage")
                    Spacer()
                    if let v = model.rules.maxLotCoveragePct {
                        Text("\(Int(v)) %")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .font(.callout)
            if let v = model.rules.maxLotCoveragePct {
                Slider(
                    value: Binding(
                        get: { v },
                        set: { model.rules.maxLotCoveragePct = $0 }
                    ),
                    in: 1...50,
                    step: 1
                )
            }
        }
    }

    // MARK: Readout

    private var readoutSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if model.poolCenter != nil {
                let f = model.formatter
                Text("Pool: \(f.poolDimension(model.widthFt * Geo.metersPerFoot)) × \(f.poolDimension(model.lengthFt * Geo.metersPerFoot))")
                Text("Water area: \(f.area(model.footprintM2))")
                    .foregroundStyle(.secondary)
                if let report = model.report {
                    complianceRows(report: report, formatter: f)
                }
            } else {
                Text("No pool placed yet")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func complianceRows(report: ComplianceReport, formatter f: UnitFormatter) -> some View {
        if model.lot.count >= 3 {
            Divider()
            if report.poolCenterInsideLot == false {
                Text("Pool is outside the property outline")
                    .foregroundStyle(.red)
            } else {
                ForEach(Array(report.lotEdgeGaps.prefix(2).enumerated()), id: \.offset) { i, gap in
                    let viol = report.poolCenterInsideLot == false
                        || (model.rules.propertyLineSetbackM.map { gap.connector.d < $0 } ?? false)
                    HStack {
                        Text("Lot line \(i + 1): \(f.distance(gap.connector.d))")
                            .foregroundStyle(viol ? .red : .primary)
                        Spacer()
                        NudgeField(model: model, gap: gap, ref: report.ref)
                    }
                }
            }
            if let area = report.lotAreaM2 {
                let overCoverage = report.coverageViolation
                Text("Lot: \(f.area(area))"
                     + (report.coveragePct.map { String(format: " — pool covers %.1f%%", $0) } ?? ""))
                    .foregroundStyle(overCoverage ? .red : .secondary)
            }
        }
        if !model.structures.isEmpty {
            let nearest = report.structureGaps.compactMap { $0?.d }.min()
            if let nearest {
                let viol = model.rules.structureSetbackM.map { nearest < $0 } ?? false
                Text("Nearest structure: \(f.distance(nearest))")
                    .foregroundStyle(viol ? .red : .primary)
            }
        }
        if !model.zones.isEmpty {
            ForEach(Array(model.zones.enumerated()), id: \.element.id) { i, _ in
                if report.zoneGaps.indices.contains(i), let gap = report.zoneGaps[i] {
                    let viol = report.zoneViolations.indices.contains(i) && report.zoneViolations[i]
                    Text("Zone \(i + 1): \(f.distance(gap.d))")
                        .foregroundStyle(viol ? .red : .primary)
                }
            }
        }
        let measuredPins = model.measuredPins
        if !measuredPins.isEmpty {
            Divider()
            ForEach(Array(zip(measuredPins, report.equipment)), id: \.0.id) { pin, check in
                Text(equipmentLine(pin: pin, check: check, formatter: f))
                    .foregroundStyle(check.poolViolation || check.lotViolation ? .red : .primary)
            }
        }
        if model.lot.count >= 3 || !model.structures.isEmpty || !measuredPins.isEmpty || !model.zones.isEmpty {
            Text(report.hasViolation ? "⚠ Setback violations" : "✓ All enabled checks pass")
                .font(.callout.weight(.semibold))
                .foregroundStyle(report.hasViolation ? .red : .green)
        }
    }
}

extension SidebarView {
    fileprivate func equipmentLine(pin: PlacedPin, check: EquipmentCheck, formatter f: UnitFormatter) -> String {
        var line = String(
            localized: "\(pin.kind.label): pool \(check.toPoolM.map { f.distance($0) } ?? "–")"
        )
        if let toLot = check.toLotM {
            line += String(localized: ", lot \(f.distance(toLot))")
        }
        return line
    }
}

/// Type a target distance to slide the pool to that setback — the web app's
/// editable distance fields.
private struct NudgeField: View {
    @ObservedObject var model: PlannerModel
    let gap: EdgeGap
    let ref: LatLng
    @State private var text = ""

    var body: some View {
        TextField("m", text: $text)
            .textFieldStyle(.roundedBorder)
            .keyboardType(.decimalPad)
            .frame(width: 64)
            .font(.footnote)
            .onSubmit {
                if let target = Double(text.replacingOccurrences(of: ",", with: ".")) {
                    model.nudgePool(along: gap, ref: ref, target: target)
                    text = ""
                }
            }
    }
}

#Preview {
    PlannerView()
}
