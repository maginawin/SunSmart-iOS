import UIKit
import SnapKit

final class SimulateFaultSectionView: UIView {
    struct Item {
        let titleKey: String
        let action: SimulateFaultAction
    }

    struct TagStyle {
        let textColor: UIColor
        let backgroundColor: UIColor
    }

    struct Configuration {
        let titleKey: String
        let tagKey: String
        let tagStyle: TagStyle
        let items: [Item]
    }

    var onAction: ((SimulateFaultAction) -> Void)?

    private let configuration: Configuration
    private let titleLabel = UILabel()
    private let tagLabel = UILabel()
    private let flowLayout = UICollectionViewFlowLayout()
    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
    private var collectionHeightConstraint: Constraint?
    private var lastMeasuredWidth: CGFloat = 0

    init(configuration: Configuration) {
        self.configuration = configuration
        super.init(frame: .zero)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = collectionView.bounds.width
        guard width > 0, width != lastMeasuredWidth else { return }
        lastMeasuredWidth = width
        let height = SimulateFaultGridMetrics.collectionHeight(
            availableWidth: width,
            itemCount: configuration.items.count
        )
        collectionHeightConstraint?.update(offset: height)
        flowLayout.invalidateLayout()
    }

    private func setupUI() {
        backgroundColor = UIColor(red: 248 / 255, green: 250 / 255, blue: 252 / 255, alpha: 1)
        layer.cornerRadius = 14

        titleLabel.text = configuration.titleKey.localizedString
        titleLabel.textColor = UIColor(red: 27 / 255, green: 20 / 255, blue: 37 / 255, alpha: 1)
        titleLabel.font = .systemFont(ofSize: 14)

        tagLabel.text = configuration.tagKey.localizedString
        tagLabel.textColor = configuration.tagStyle.textColor
        tagLabel.backgroundColor = configuration.tagStyle.backgroundColor
        tagLabel.font = .systemFont(ofSize: 12)
        tagLabel.textAlignment = .center
        tagLabel.layer.cornerRadius = 6
        tagLabel.clipsToBounds = true

        flowLayout.itemSize = CGSize(
            width: SimulateFaultGridMetrics.itemWidth,
            height: SimulateFaultGridMetrics.itemHeight
        )
        flowLayout.minimumInteritemSpacing = SimulateFaultGridMetrics.interitemSpacing
        flowLayout.minimumLineSpacing = SimulateFaultGridMetrics.lineSpacing
        flowLayout.sectionInset = UIEdgeInsets(
            top: SimulateFaultGridMetrics.topInset,
            left: 0,
            bottom: 0,
            right: 0
        )

        collectionView.backgroundColor = .clear
        collectionView.isScrollEnabled = false
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(
            SimulateFaultButtonCell.self,
            forCellWithReuseIdentifier: SimulateFaultButtonCell.reuseIdentifier
        )

        addSubview(titleLabel)
        addSubview(tagLabel)
        addSubview(collectionView)

        titleLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(12)
            make.left.equalToSuperview().offset(16)
            make.height.equalTo(21)
        }
        tagLabel.snp.makeConstraints { make in
            make.centerY.equalTo(titleLabel)
            make.right.equalToSuperview().offset(-16)
            make.height.equalTo(20)
            make.width.greaterThanOrEqualTo(63)
        }
        collectionView.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom)
            make.left.equalToSuperview().offset(16)
            make.right.equalToSuperview().offset(-16)
            make.bottom.equalToSuperview().offset(-12)
            collectionHeightConstraint = make.height.equalTo(0).constraint
        }
    }
}

extension SimulateFaultSectionView: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        configuration.items.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: SimulateFaultButtonCell.reuseIdentifier,
            for: indexPath
        ) as! SimulateFaultButtonCell
        cell.configure(title: configuration.items[indexPath.item].titleKey.localizedString)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        onAction?(configuration.items[indexPath.item].action)
        collectionView.deselectItem(at: indexPath, animated: false)
    }
}

private final class SimulateFaultButtonCell: UICollectionViewCell {
    static let reuseIdentifier = "SimulateFaultButtonCell"
    private let titleLabel = UILabel()

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.1) {
                self.contentView.alpha = self.isHighlighted ? 0.55 : 1
                self.contentView.transform = self.isHighlighted
                    ? CGAffineTransform(scaleX: 0.96, y: 0.96)
                    : .identity
            }
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .white
        contentView.layer.cornerRadius = 8
        contentView.layer.borderWidth = 0.5
        contentView.layer.borderColor = UIColor(
            red: 236 / 255,
            green: 236 / 255,
            blue: 236 / 255,
            alpha: 1
        ).cgColor

        titleLabel.textColor = UIColor(
            red: 102 / 255,
            green: 103 / 255,
            blue: 171 / 255,
            alpha: 1
        )
        titleLabel.font = .systemFont(ofSize: 12)
        titleLabel.textAlignment = .center
        contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        contentView.alpha = 1
        contentView.transform = .identity
    }

    func configure(title: String) {
        titleLabel.text = title
    }
}
