//
//  ServerSelectionViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/6/5.
//

import UIKit

class ServerSelectionViewController: UIViewController {

    private var flowLayout: UICollectionViewFlowLayout!
    private var collectionView: UICollectionView!
    private var regions: [ServerRegion] = ServerRegion.defalutRegions
//    private var selectRegion: ServerRegion = .chinaMainland
    /// 切换地区回调
    var selectRegionCallback: ((ServerRegion)->Void)?
    
    override func viewDidLoad() {
        super.viewDidLoad()

        title = "server_selection".localizedString
        view.backgroundColor = Background_Color
        
        setupCollectionView()
    }
    
    private func setupCollectionView() {
        
        flowLayout = UICollectionViewFlowLayout()
        flowLayout.minimumLineSpacing = SCRYFrom(16)
        flowLayout.minimumInteritemSpacing = 0
        
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
        collectionView.contentInset = UIEdgeInsets(top: SCRYFrom(16), left: SCRXFrom(18), bottom: SCRYFrom(16), right: SCRXFrom(14))
        collectionView.register(ServerSelectionViewCell.classForCoder(), forCellWithReuseIdentifier: "cell")
        collectionView.backgroundColor = Background_Color
        collectionView.alwaysBounceVertical = true
        collectionView.dataSource = self
        collectionView.delegate = self
        view.addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.top.equalTo(view.safeAreaLayoutGuide)
        }
        let itemW = view.width - collectionView.contentInset.left - collectionView.contentInset.right
        flowLayout.itemSize = CGSize(width: CGFloat(floor(itemW)), height: SCRYFrom(76))
    }
    
}

extension ServerSelectionViewController: UICollectionViewDataSource, UICollectionViewDelegate {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return regions.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! ServerSelectionViewCell
        let region = regions[indexPath.item]
        cell.iconImageView.image = UIImage(named: region.data.icon)
        cell.nameLabel.text = region.data.name
        cell.selectedImageView.isHidden = region != UserData.currentServerRegion
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let region = regions[indexPath.item]
        if region != UserData.currentServerRegion {
            UserData.currentServerRegion = region
            selectRegionCallback?(region)
        }
        navigationController?.popViewController(animated: true)
    }
    
}

class ServerSelectionViewCell: UICollectionViewCell {
    
    var iconImageView: UIImageView!
    var nameLabel: UILabel!
    var selectedImageView: UIImageView!
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        layer.cornerRadius = SCRYFrom(10)
        backgroundColor = .white
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        
        iconImageView = UIImageView()
        contentView.addSubview(iconImageView)
        iconImageView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(12))
            make.centerY.equalToSuperview()
        }
        
        nameLabel = UILabel(text: "", textColor: TextBlack_Color, fontSize: 14)
        contentView.addSubview(nameLabel)
        nameLabel.snp.makeConstraints { make in
            make.left.equalTo(iconImageView.snp.right).offset(SCRXFrom(12))
            make.centerY.equalToSuperview()
        }
        
        selectedImageView = UIImageView(image: UIImage(named: "server_select"))
        selectedImageView.isHidden = true
        contentView.addSubview(selectedImageView)
        selectedImageView.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-12))
            make.centerY.equalToSuperview()
        }
        
    }
    
}

/// 服务器地区
enum ServerRegion {
    
    static let defalutRegions: [ServerRegion] = [.chinaMainland, .northAmerica, .europe]
    
    var rawValue: Int {
        switch self {
        case .chinaMainland:
            return 1
        case .northAmerica:
            return 2
        case .europe:
            return 3
        }
    }
    
    var data: (icon: String, name: String) {
        switch self {
        case .chinaMainland:
            return ("china_map", "china_mainland".localizedString)
        case .northAmerica:
            return ("north_america_map", "north_america".localizedString)
        case .europe:
            return ("europe_map", "europe".localizedString)
        }
    }
    
    init?(rawValue: Int) {
        switch rawValue {
        case 1:
            self = .chinaMainland
        case 2:
            self = .northAmerica
        case 3:
            self = .europe
        default:
            return nil
        }
    }
    
    init?(regionCode: String?) {
        guard let code = regionCode else {
            return nil
        }
        if String.isChina(regionCode: code) {
            self = .chinaMainland
        }else if String.isNorthAmerica(regionCode: code) {
            self = .northAmerica
        }else if String.isEurope(regionCode: code) {
            self = .europe
        }else {
            return nil
        }
    }
    
    /// 中国大陆
    case chinaMainland
    /// 北美
    case northAmerica
    /// 欧洲
    case europe
}
