import UIKit

/// Interactive UIKit Test Runner Dashboard for physical iPad / iOS testing
public final class TestHarnessViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {

    private let tabManager: BrowserTabManager
    private var testCases: [TestCase] = []

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let headerContainer = UIView()
    private let summaryStack = UIStackView()
    private let serverStatusLabel = UILabel()

    public init(tabManager: BrowserTabManager) {
        self.tabManager = tabManager
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        title = "V4.4 Test Harness Runner"
        view.backgroundColor = .systemGroupedBackground

        setupNavigationBar()
        setupHeaderView()
        setupTableView()
        bindTestEngine()

        testCases = TestHarnessEngine.shared.testCases
        updateSummaryHeader()
    }

    private func setupNavigationBar() {
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "✕ Close",
            style: .plain,
            target: self,
            action: #selector(closeTapped)
        )

        let runAllBtn = UIBarButtonItem(
            title: "▶ Run All Auto",
            style: .done,
            target: self,
            action: #selector(runAllAutoTapped)
        )
        runAllBtn.tintColor = .systemGreen

        let copyBtn = UIBarButtonItem(
            title: "📋 Copy",
            style: .plain,
            target: self,
            action: #selector(copyReportTapped)
        )

        navigationItem.rightBarButtonItems = [runAllBtn, copyBtn]
    }

    private func setupHeaderView() {
        headerContainer.backgroundColor = .clear
        headerContainer.translatesAutoresizingMaskIntoConstraints = false

        summaryStack.axis = .horizontal
        summaryStack.distribution = .fillEqually
        summaryStack.spacing = 8
        summaryStack.translatesAutoresizingMaskIntoConstraints = false

        serverStatusLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        serverStatusLabel.textColor = .secondaryLabel
        serverStatusLabel.textAlignment = .center
        serverStatusLabel.translatesAutoresizingMaskIntoConstraints = false

        headerContainer.addSubview(summaryStack)
        headerContainer.addSubview(serverStatusLabel)

        NSLayoutConstraint.activate([
            summaryStack.topAnchor.constraint(equalTo: headerContainer.topAnchor, constant: 8),
            summaryStack.leadingAnchor.constraint(equalTo: headerContainer.leadingAnchor, constant: 16),
            summaryStack.trailingAnchor.constraint(equalTo: headerContainer.trailingAnchor, constant: -16),
            summaryStack.heightAnchor.constraint(equalToConstant: 44),

            serverStatusLabel.topAnchor.constraint(equalTo: summaryStack.bottomAnchor, constant: 6),
            serverStatusLabel.leadingAnchor.constraint(equalTo: headerContainer.leadingAnchor, constant: 16),
            serverStatusLabel.trailingAnchor.constraint(equalTo: headerContainer.trailingAnchor, constant: -16),
            serverStatusLabel.bottomAnchor.constraint(equalTo: headerContainer.bottomAnchor, constant: -6)
        ])
    }

    private func setupTableView() {
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(TestHarnessCell.self, forCellReuseIdentifier: TestHarnessCell.reuseId)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 110

        view.addSubview(headerContainer)
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            headerContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            headerContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            tableView.topAnchor.constraint(equalTo: headerContainer.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func bindTestEngine() {
        TestHarnessEngine.shared.onTestsUpdated = { [weak self] updatedCases in
            DispatchQueue.main.async {
                self?.testCases = updatedCases
                self?.tableView.reloadData()
                self?.updateSummaryHeader()
            }
        }
    }

    private func updateSummaryHeader() {
        summaryStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let passRuntimeCount = testCases.filter { $0.status == .passRuntime }.count
        let readyCount = testCases.filter { $0.status == .readyDevice }.count
        let passStaticCount = testCases.filter { $0.status == .passStatic }.count
        let failCount = testCases.filter { $0.status == .failRuntime }.count
        let manualCount = testCases.filter { $0.status == .manual }.count

        summaryStack.addArrangedSubview(createChip(title: "RUNTIME PASS", count: passRuntimeCount, color: .systemGreen))
        summaryStack.addArrangedSubview(createChip(title: "READY (DEVICE)", count: readyCount, color: .systemOrange))
        summaryStack.addArrangedSubview(createChip(title: "STATIC PASS", count: passStaticCount, color: .systemBlue))
        summaryStack.addArrangedSubview(createChip(title: "FAIL", count: failCount, color: .systemRed))
        summaryStack.addArrangedSubview(createChip(title: "MANUAL", count: manualCount, color: .systemGray))

        let port = EmbeddedHttpServer.shared.port
        let serverRunning = EmbeddedHttpServer.shared.isRunning
        serverStatusLabel.text = "Local Server: http://127.0.0.1:\(port) [\(serverRunning ? "ONLINE" : "OFFLINE")] | Active Tabs: \(tabManager.tabs.count)"
    }

    private func createChip(title: String, count: Int, color: UIColor) -> UIView {
        let chip = UIView()
        chip.backgroundColor = color.withAlphaComponent(0.15)
        chip.layer.cornerRadius = 8
        chip.layer.borderWidth = 1
        chip.layer.borderColor = color.withAlphaComponent(0.3).cgColor

        let countLabel = UILabel()
        countLabel.text = "\(count)"
        countLabel.font = .systemFont(ofSize: 15, weight: .bold)
        countLabel.textColor = color
        countLabel.textAlignment = .center
        countLabel.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 9, weight: .semibold)
        titleLabel.textColor = color
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        chip.addSubview(countLabel)
        chip.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            countLabel.topAnchor.constraint(equalTo: chip.topAnchor, constant: 4),
            countLabel.centerXAnchor.constraint(equalTo: chip.centerXAnchor),

            titleLabel.topAnchor.constraint(equalTo: countLabel.bottomAnchor, constant: 1),
            titleLabel.centerXAnchor.constraint(equalTo: chip.centerXAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: chip.bottomAnchor, constant: -4)
        ])

        return chip
    }

    // MARK: - Actions
    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    @objc private func runAllAutoTapped() {
        navigationItem.rightBarButtonItems?.first?.isEnabled = false
        TestHarnessEngine.shared.runAllAutomatedRuntimeTests(tabManager: tabManager) { [weak self] in
            DispatchQueue.main.async {
                self?.navigationItem.rightBarButtonItems?.first?.isEnabled = true
            }
        }
    }

    @objc private func copyReportTapped() {
        let report = TestHarnessEngine.shared.generateReportText()
        UIPasteboard.general.string = report

        let alert = UIAlertController(title: "Report Copied", message: "Full V4.4 test harness status copied to clipboard.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    // MARK: - UITableViewDataSource & Delegate
    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return testCases.count
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: TestHarnessCell.reuseId, for: indexPath) as? TestHarnessCell else {
            return UITableViewCell()
        }
        let tc = testCases[indexPath.row]
        cell.configure(with: tc)

        cell.onActionTapped = { [weak self] in
            guard let self = self else { return }
            self.executeTest(for: tc)
        }

        return cell
    }

    private func executeTest(for tc: TestCase) {
        if tc.id == "Q" {
            let alert = UIAlertController(
                title: "Process Termination (MANUAL)",
                message: "App Store guidelines prohibit unprivileged/private kill calls. To test crash recovery on iPad:\n\n1. Inspect with Mac Safari Web Inspector -> Debugger -> Terminate WebProcess\nOR\n2. Trigger Jetsam memory pressure via multiple background apps.\n\nVerified in code: Tab-specific isolation & 3-second rapid crash loop guard prevent infinite CPU hang.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }

        if tc.requiresRealDevice && (tc.id == "B" || tc.id == "D" || tc.id == "E" || tc.id == "F" || tc.id == "G") {
            // Interactive popup test
            TestHarnessEngine.shared.runTest(id: tc.id, tabManager: tabManager) { [weak self] in
                DispatchQueue.main.async {
                    let alert = UIAlertController(
                        title: "Test [\(tc.id)] Loaded",
                        message: "Fixture page loaded in the active tab. Tap Close to switch to the browser view and tap the [\(tc.id)] action button to trigger the WebKit event.",
                        preferredStyle: .alert
                    )
                    alert.addAction(UIAlertAction(title: "Go to Browser", style: .default, handler: { _ in
                        self?.dismiss(animated: true)
                    }))
                    alert.addAction(UIAlertAction(title: "Stay Here", style: .cancel))
                    self?.present(alert, animated: true)
                }
            }
            return
        }

        // Automated or server test
        TestHarnessEngine.shared.runTest(id: tc.id, tabManager: tabManager) {
            // Live update handled via onTestsUpdated
        }
    }
}

// MARK: - Custom Test Harness Cell
final class TestHarnessCell: UITableViewCell {
    static let reuseId = "TestHarnessCell"

    var onActionTapped: (() -> Void)?

    private let titleLabel = UILabel()
    private let categoryBadge = UILabel()
    private let statusBadge = UILabel()
    private let durationLabel = UILabel()
    private let evidenceLabel = UILabel()
    private let errorLabel = UILabel()
    private let actionButton = UIButton(type: .system)

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        selectionStyle = .none

        titleLabel.font = .systemFont(ofSize: 14, weight: .bold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        categoryBadge.font = .systemFont(ofSize: 10, weight: .semibold)
        categoryBadge.textColor = .secondaryLabel
        categoryBadge.backgroundColor = .secondarySystemFill
        categoryBadge.layer.cornerRadius = 4
        categoryBadge.clipsToBounds = true
        categoryBadge.textAlignment = .center
        categoryBadge.translatesAutoresizingMaskIntoConstraints = false

        statusBadge.font = .systemFont(ofSize: 10, weight: .bold)
        statusBadge.layer.cornerRadius = 5
        statusBadge.clipsToBounds = true
        statusBadge.textAlignment = .center
        statusBadge.translatesAutoresizingMaskIntoConstraints = false

        durationLabel.font = .monospacedSystemFont(ofSize: 10, weight: .medium)
        durationLabel.textColor = .secondaryLabel
        durationLabel.translatesAutoresizingMaskIntoConstraints = false

        evidenceLabel.font = .systemFont(ofSize: 11, weight: .regular)
        evidenceLabel.textColor = .label
        evidenceLabel.numberOfLines = 0
        evidenceLabel.translatesAutoresizingMaskIntoConstraints = false

        errorLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        errorLabel.textColor = .systemRed
        errorLabel.numberOfLines = 0
        errorLabel.isHidden = true
        errorLabel.translatesAutoresizingMaskIntoConstraints = false

        actionButton.titleLabel?.font = .systemFont(ofSize: 11, weight: .bold)
        actionButton.layer.cornerRadius = 6
        actionButton.translatesAutoresizingMaskIntoConstraints = false
        actionButton.addAction(UIAction { [weak self] _ in
            self?.onActionTapped?()
        }, for: .touchUpInside)

        let topRow = UIStackView(arrangedSubviews: [titleLabel, categoryBadge, UIView(), statusBadge, durationLabel])
        topRow.axis = .horizontal
        topRow.spacing = 6
        topRow.alignment = .center
        topRow.translatesAutoresizingMaskIntoConstraints = false

        let contentStack = UIStackView(arrangedSubviews: [topRow, evidenceLabel, errorLabel, actionButton])
        contentStack.axis = .vertical
        contentStack.spacing = 6
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            contentStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14),
            contentStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),
            contentStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),

            categoryBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 54),
            categoryBadge.heightAnchor.constraint(equalToConstant: 18),

            statusBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 90),
            statusBadge.heightAnchor.constraint(equalToConstant: 20),

            actionButton.heightAnchor.constraint(equalToConstant: 28)
        ])
    }

    func configure(with tc: TestCase) {
        titleLabel.text = "[\(tc.id)] \(tc.title)"
        categoryBadge.text = " \(tc.category) "
        evidenceLabel.text = tc.evidence

        // Status Badge Style
        statusBadge.text = " \(tc.status.rawValue) "
        switch tc.status {
        case .passRuntime:
            statusBadge.backgroundColor = .systemGreen.withAlphaComponent(0.2)
            statusBadge.textColor = .systemGreen
        case .readyDevice:
            statusBadge.backgroundColor = .systemOrange.withAlphaComponent(0.2)
            statusBadge.textColor = .systemOrange
        case .failRuntime:
            statusBadge.backgroundColor = .systemRed.withAlphaComponent(0.2)
            statusBadge.textColor = .systemRed
        case .passStatic:
            statusBadge.backgroundColor = .systemBlue.withAlphaComponent(0.2)
            statusBadge.textColor = .systemBlue
        case .manual:
            statusBadge.backgroundColor = .systemGray.withAlphaComponent(0.2)
            statusBadge.textColor = .systemGray
        case .notRun:
            statusBadge.backgroundColor = .secondarySystemFill
            statusBadge.textColor = .secondaryLabel
        }

        // Duration Label
        if let ms = tc.durationMs {
            durationLabel.text = String(format: "⏱ %.1f ms", ms)
            durationLabel.isHidden = false
        } else {
            durationLabel.text = ""
            durationLabel.isHidden = true
        }

        // Error message
        if let err = tc.errorMessage, !err.isEmpty {
            errorLabel.text = "Error: \(err)"
            errorLabel.isHidden = false
        } else {
            errorLabel.isHidden = true
        }

        // Action button title & style
        if tc.id == "Q" {
            actionButton.setTitle("ℹ️ Physical Device Instructions", for: .normal)
            actionButton.backgroundColor = .systemGray.withAlphaComponent(0.15)
            actionButton.setTitleColor(.systemGray, for: .normal)
        } else if tc.requiresRealDevice {
            actionButton.setTitle("📱 Run Device Test / Open Fixture", for: .normal)
            actionButton.backgroundColor = .systemOrange.withAlphaComponent(0.15)
            actionButton.setTitleColor(.systemOrange, for: .normal)
        } else {
            actionButton.setTitle("▶ Run Test in WebKit", for: .normal)
            actionButton.backgroundColor = .systemBlue.withAlphaComponent(0.15)
            actionButton.setTitleColor(.systemBlue, for: .normal)
        }
    }
}
