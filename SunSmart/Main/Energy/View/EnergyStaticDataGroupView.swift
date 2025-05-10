//
//  EnergyStaticDataGroupView.swift
//  SunSmart
//
//  Created by yuankehong on 2025/4/28.
//

import UIKit

class EnergyStaticDataGroupView: UIView {

    private var scrollView: UIScrollView!
    private var contentView: UIView!
    var pieChartView: LYCirclePieView!
    var totalEnergyUseLabel: UILabel!
    var totalEnergyDataLabel: UILabel!
    /// 节约比例
    var economyPercentageBtn: UIButton!
    /// 节约能源数据
    var economyValueBtn: UIButton!
    private var lineView: UIView!
    /// 点标记
    private var collectionView: UICollectionView!
    private var flowLayout: UICollectionViewFlowLayout!
    
    var energyPieDatas: [EnergyPieData] = []
    /// 优化排序后的数据
    private var sortEnergyPieDatas: [EnergyPieData] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        
        layer.cornerRadius = SCRYFrom(10)
        backgroundColor = .white
        
        setupData()
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    

    
    private func setupData() {
        
        let total: Double = 26782.02
        let tempColors = UIColor.generateDistinctColors(count: 16)
        let tempPercentages = EnergyTestData.generateRandomPercentages(count: 16, minimum: 0.01)
        let preDatas = tempColors.enumerated().map({
            let percentage = tempPercentages[$0.offset]
            return EnergyPieData(name: "Group \($0.offset + 1)", color: $0.element, percent: tempPercentages[$0.offset], data: String(format: "%.2f kWh", total * percentage))
        })
        
        energyPieDatas = preDatas
        sortEnergyPieDatas = EnergyTestData.smartReorderEntryPicDatas(preDatas)
    }
    
    private func setupUI() {
        
        scrollView = UIScrollView()
        scrollView.alwaysBounceVertical = false
        scrollView.showsVerticalScrollIndicator = false
        addSubview(scrollView)
        scrollView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        contentView = UIView()
        scrollView.addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.edges.width.equalToSuperview()
        }
        
        let tempDatas = sortEnergyPieDatas.map({
            LYPieData(title: $0.name, detail: String(format: "%d%%", Int($0.percent * 100.0)), percent: $0.percent)
        })
        
        let tempColors = sortEnergyPieDatas.map({ $0.color })
        let data = LYPieVisual.init(datas: tempDatas, colors: tempColors)
        
        pieChartView = LYCirclePieView()
        pieChartView.centerRadius = SCRXFrom(60)
        pieChartView.pieRadius = SCRXFrom(88)
        pieChartView.pieVisual = data
        pieChartView.backgroundColor = .white
        contentView.addSubview(pieChartView)
        pieChartView.snp.makeConstraints { make in
            make.top.equalTo(SCRYFrom(16))
            make.left.right.equalToSuperview()
            make.height.equalTo(SCRYFrom(282))
        }
        
        totalEnergyDataLabel = UILabel(text: "26782.02 kWh", textColor: TextBlack_Color)
        let totalEnergyAttStr = NSMutableAttributedString(string: "26782.02 kWh", attributes: [.font: UIFont.systemFont(ofSize: 16, weight: .semibold)])
        totalEnergyAttStr.addAttributes([.font: UIFont.systemFont(ofSize: 16)], range: (totalEnergyAttStr.string as NSString).range(of: "kWh"))
        totalEnergyDataLabel.attributedText = totalEnergyAttStr
        contentView.addSubview(totalEnergyDataLabel)
        totalEnergyDataLabel.snp.makeConstraints { make in
            make.center.equalTo(pieChartView)
        }
        
        totalEnergyUseLabel = UILabel(text: "total_energy_use:".localizedString, textColor: SubText_Color, fontSize: 14, fontWeight: .light, fit: false)
        contentView.addSubview(totalEnergyUseLabel)
        totalEnergyUseLabel.snp.makeConstraints { make in
            make.centerX.equalTo(totalEnergyDataLabel)
            make.bottom.equalTo(totalEnergyDataLabel.snp.top).offset(SCRYFrom(-10))
        }
        
        economyValueBtn = UIButton(title: "17018.66 kWh", titleSize: 12, titleWeight: .light, titleColor: TextBlack_Color, fit: false, normalImageName: "energy_reduce")
        economyValueBtn.isUserInteractionEnabled = false
        economyValueBtn.setImagePosition(position: .left, spacing: SCRXFrom(4))
        contentView.addSubview(economyValueBtn)
        economyValueBtn.snp.makeConstraints { make in
            make.top.equalTo(totalEnergyDataLabel.snp.bottom).offset(SCRYFrom(9))
            make.centerX.equalTo(totalEnergyDataLabel)
        }
        
        economyPercentageBtn = UIButton(title: "38.9%", titleSize: 12, titleWeight: .light, titleColor: TextBlack_Color, fit: false, normalImageName: "energy_reduce")
        economyPercentageBtn.isUserInteractionEnabled = false
        economyPercentageBtn.setImagePosition(position: .left, spacing: SCRXFrom(4))
        contentView.addSubview(economyPercentageBtn)
        economyPercentageBtn.snp.makeConstraints { make in
            make.centerX.equalTo(economyValueBtn)
            make.top.equalTo(economyValueBtn.snp.bottom)
        }
        
        lineView = UIView()
        lineView.backgroundColor = Line_Color
        contentView.addSubview(lineView)
        lineView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(15))
            make.top.equalTo(pieChartView.snp.bottom).offset(SCRYFrom(16))
            make.height.equalTo(1)
            make.right.equalToSuperview()
        }
     
        flowLayout = UICollectionViewFlowLayout()
        flowLayout.minimumLineSpacing = SCRYFrom(4)
        flowLayout.minimumInteritemSpacing = 0
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
        collectionView.backgroundColor = .clear
        collectionView.register(EnergyGroupDataSignViewCell.classForCoder(), forCellWithReuseIdentifier: "cell")
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.isScrollEnabled = false
        contentView.addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(10))
            make.right.equalTo(SCRXFrom(-9))
            make.top.equalTo(lineView.snp.bottom).offset(SCRYFrom(17))
            make.bottom.equalTo(SCRYFrom(-8))
            make.height.equalTo(SCRYFrom(41 + 4) * ceil(Double(energyPieDatas.count) / 3.0))
        }
        
    }
    
   
    class EnergyGroupDataSignViewCell: UICollectionViewCell {
        
        var signView: UIView!
        var nameLabel: UILabel!
        var dataLabel: UILabel!
        
        override init(frame: CGRect) {
            super.init(frame: frame)
            setupUI()
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        private func setupUI() {
            
            signView = UIView()
            signView.layer.cornerRadius = SCRYFrom(4)
            contentView.addSubview(signView)
            signView.snp.makeConstraints { make in
                make.left.equalTo(SCRXFrom(8))
                make.top.equalTo(SCRYFrom(8))
                make.width.height.equalTo(SCRYFrom(8))
            }
            
            nameLabel = UILabel(text: "Group 1", textColor: .black.withAlphaComponent(0.7), fontSize: 12)
            contentView.addSubview(nameLabel)
            nameLabel.snp.makeConstraints { make in
                make.left.equalTo(signView.snp.right).offset(SCRXFrom(8))
                make.right.equalToSuperview()
                make.centerY.equalTo(signView)
            }
            
            dataLabel = UILabel(text: "", textColor: SubText_Color, fontSize: 12, fontWeight: .light)
            contentView.addSubview(dataLabel)
            dataLabel.snp.makeConstraints { make in
                make.left.equalTo(nameLabel)
                make.bottom.right.equalToSuperview()
            }
        }
        
    }

    
    
//    private func setupChartData() {
//            let entries = [
//                PieChartDataEntry(value: 0.1, label: "Group 1"),
//                PieChartDataEntry(value: 0.3, label: "Group 2"),
//                PieChartDataEntry(value: 0.2, label: "Group 3"),
//                PieChartDataEntry(value: 0.1, label: "Group 4"),
//                PieChartDataEntry(value: 0.05, label: "Group 5"),
//                PieChartDataEntry(value: 0.25, label: "Group 6")
//            ]
//
//            let colors = [
//                UIColor.systemBlue,
//                UIColor.systemRed,
//                UIColor.systemTeal,
//                UIColor.systemOrange,
//                UIColor.systemIndigo,
//                UIColor.systemGreen
//            ]
//
//            let groupTitles = [
//                "Group 1",
//                "Group 2",
//                "Group 3",
//                "Group 4",
//                "Group 5",
//                "Group 6"
//            ]
//
//            let centerText = "Total energy use:\n26782.02 kWh"
//
//            donutChartView.configure(entries: entries, centerText: centerText, colors: colors, groupTitles: groupTitles)
//        }
    
//    private func setData() {
//        let entries: [PieChartDataEntry] = [
//            PieChartDataEntry(value: 5.0, label: "Group 1"),
//            PieChartDataEntry(value: 5.0, label: "Group 2"),
//            PieChartDataEntry(value: 5.0, label: "Group 3"),
//            PieChartDataEntry(value: 5.0, label: "Group 4"),
//            PieChartDataEntry(value: 5.0, label: "Group 5"),
//            PieChartDataEntry(value: 5.0, label: "Group 6"),
//            // 你可以继续添加更多 group
//        ]
//        
//        let dataSet = PieChartDataSet(entries: entries, label: "")
//        
//        // 配色
//        dataSet.colors = [
//            UIColor.systemBlue,
//            UIColor.systemRed,
//            UIColor.systemTeal,
//            UIColor.systemOrange,
//            UIColor.systemIndigo,
//            UIColor.systemGreen
//        ]
//        
//        dataSet.sliceSpace = 2  // 分片间隔
//        
//        let data = PieChartData(dataSet: dataSet)
//        data.setDrawValues(false)  // 不要在每个扇形上画数值
//        
//        pieChartView.data = data
//    }
    
}

extension EnergyStaticDataGroupView: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return energyPieDatas.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! EnergyGroupDataSignViewCell
        let data = energyPieDatas[indexPath.row]
        cell.signView.backgroundColor = data.color
        cell.nameLabel.text = data.name
        cell.dataLabel.text = data.data
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        var itemW = collectionView.width / 3.0
        itemW = CGFloat(floorf(Float(itemW) * 100) / 100.0)
        return CGSize(width: itemW, height: SCRYFrom(41))
    }
    
}

//class DonutChartView: UIView {
//
//    private let pieChartView = PieChartView()
//    private let legendStackView = UIStackView()
//    private var customLabels: [UILabel] = []
//    private var entries: [PieChartDataEntry] = []
//    
//    override init(frame: CGRect) {
//        super.init(frame: frame)
//        setupChart()
//        setupLegendStack()
//    }
//
//    required init?(coder: NSCoder) {
//        super.init(coder: coder)
//        setupChart()
//        setupLegendStack()
//    }
//
//    private func setupChart() {
//        pieChartView.translatesAutoresizingMaskIntoConstraints = false
//        addSubview(pieChartView)
//
//        NSLayoutConstraint.activate([
//            pieChartView.topAnchor.constraint(equalTo: topAnchor),
//            pieChartView.centerXAnchor.constraint(equalTo: centerXAnchor),
//            pieChartView.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.8),
//            pieChartView.heightAnchor.constraint(equalTo: pieChartView.widthAnchor)
//        ])
//
//        pieChartView.holeRadiusPercent = 0.6
//        pieChartView.transparentCircleRadiusPercent = 0.0
//        pieChartView.legend.enabled = false
//        pieChartView.centerTextRadiusPercent = 0.95
//        pieChartView.extraTopOffset = 20
//        pieChartView.extraBottomOffset = 20
//        pieChartView.extraLeftOffset = 20
//        pieChartView.extraRightOffset = 20
////        pieChartView.animate(xAxisDuration: 1.0, easingOption: .easeOutBack)
//    }
//
//    private func setupLegendStack() {
//        legendStackView.axis = .vertical
//        legendStackView.spacing = 8
//        legendStackView.alignment = .leading
//        legendStackView.translatesAutoresizingMaskIntoConstraints = false
//
//        addSubview(legendStackView)
//
//        NSLayoutConstraint.activate([
//            legendStackView.topAnchor.constraint(equalTo: pieChartView.bottomAnchor, constant: 16),
//            legendStackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
//            legendStackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
//            legendStackView.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor)
//        ])
//    }
//    
//    override func layoutSubviews() {
//        super.layoutSubviews()
//        
////        if customLabels.isEmpty {
////            self.addCustomLabels(entries: entries, valueFirst: false)
////        }
//    }
//
//    // MARK: - Public Methods
//
//    func configure(
//        entries: [PieChartDataEntry],
//        centerText: String,
//        colors: [UIColor],
//        groupTitles: [String]
//    ) {
//        self.entries = entries
//        // 清除之前的标签
//        customLabels.forEach { $0.removeFromSuperview() }
//        customLabels.removeAll()
//        
//        let dataSet = PieChartDataSet(entries: entries, label: "")
//            dataSet.colors = colors
//            dataSet.sliceSpace = 0
//
//            // 添加线条和标签到外面
//            dataSet.xValuePosition = .outsideSlice
//            dataSet.yValuePosition = .outsideSlice
//            dataSet.valueLinePart1OffsetPercentage = 0.8
//            dataSet.valueLinePart1Length = 0.3
//            dataSet.valueLinePart2Length = 0.5
//            dataSet.valueLineWidth = 1
////            dataSet.valueLineColor = .lightGray
//        
//            dataSet.useValueColorForLine = true
//        
//            let data = PieChartData(dataSet: dataSet)
//            data.setValueFont(UIFont.systemFont(ofSize: 12))
////        data.setDrawValues(false)
//            data.setValueTextColor(.darkGray)
//
//            pieChartView.data = data
//            pieChartView.centerText = centerText
//        
////        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
////            self?.addCustomLabels(entries: entries, valueFirst: false)
////        }
//
//            setupLegend(groups: zip(colors, groupTitles))
//    }
//

//    
//    private func addCustomLabels(entries: [PieChartDataEntry], valueFirst: Bool) {
//            guard let dataSet = pieChartView.data?.dataSets.first as? PieChartDataSet else { return }
//
//            let center = pieChartView.centerCircleBox
//            let radius = pieChartView.radius * 1.2 // 比饼图半径稍大，避免重叠
//            let rotationAngle = pieChartView.rotationAngle
//
//            var startAngle: CGFloat = 0
//            for (index, entry) in entries.enumerated() {
//                
//                let sweepAngle = pieChartView.drawAngles[index]
//                let midAngle = startAngle + sweepAngle / 2 + rotationAngle
//
//                let radians = midAngle * .pi / 180
//
//                let labelCenterX = center.x + radius * cos(radians)
//                let labelCenterY = center.y + radius * sin(radians)
//
//                let label = UILabel()
//                label.numberOfLines = 2
//                label.font = UIFont.systemFont(ofSize: 10)
//                label.textColor = .darkGray
//                label.textAlignment = .center
////                label.translatesAutoresizingMaskIntoConstraints = false
//                
//                let valueText = String(format: "%.1f", entry.value)
//                if valueFirst {
//                    
//                    label.text = "\(valueText)\n\(entry.label ?? "")"
//                } else {
//                    label.text = "\(entry.label ?? "")\n\(valueText)"
//                }
//                label.sizeToFit()
//                label.frame = CGRect(x: 0, y: 0, width: label.width, height: label.height)
//                addSubview(label)
//                customLabels.append(label)
//
//                label.center = CGPoint(x: labelCenterX, y: labelCenterY)
//                
//                startAngle += sweepAngle
//            }
//        }
//}
