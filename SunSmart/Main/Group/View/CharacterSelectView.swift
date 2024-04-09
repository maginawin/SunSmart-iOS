//
//  CharacterSelectView.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/12/12.
//

import UIKit

class CharacterSelectView: UIView {
    /// 选择字符回调
    typealias SelectCharacterCallback = ((Int, String)->Void)
    
    
    private var shadeView: UIView!
    private var contentView: UIView!
    private var titleLabel: UILabel!
    private var closeBtn: UIButton!
    private var collectionView: UICollectionView!
    private var flowLayout: UICollectionViewFlowLayout!
    
    private var title = "characters_select_title".localizedString
    private var characters = ["A","B","C","D","E","F",
                              "G","H","I","J","K","L",
                              "M","N","O","P","Q","R",
                              "S","T","U","V","W","X",
                              "Y","Z","1","2","3","4",
                              "5","6","7","8","9","10",
                              "11","12","13","14","15","16"]
    private var selectIndex: Int = 0
    private var selectCallback: SelectCharacterCallback?
    
    static func show(title: String? = nil, characters: [String]? = nil, selectText: String? = nil, selectBack: SelectCharacterCallback?) {
        
        let view = CharacterSelectView(frame: UIScreen.main.bounds)
        if characters?.count ?? 0 > 0 {
            view.characters = characters!
        }
        if title != nil {
            view.title = title!
        }
        if let text = selectText, let index = view.characters.firstIndex(of: text) {
            view.selectIndex = index
        }
        view.selectCallback = selectBack
        view.setupUI()
        UIApplication.shared.keyWindow().addSubview(view)
        view.showAnimation()
    }
    
    private func showAnimation() {
        
        contentView.layoutIfNeeded()
        contentView.transform = CGAffineTransformMakeScale(0.1, 0.1)
        shadeView.alpha = 0
        UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 1, options: .curveEaseInOut) {
            self.contentView.transform = .identity
            self.shadeView.alpha = 1
        }
        
    }
    
    private func dismiss() {
        
        UIView.animate(withDuration: 0.15) {
            self.shadeView.alpha = 0
            self.contentView.layer.addScaleAnimation(fromScale: 1, toScale: 0.7, duration: 0.2)
        } completion: { _ in
            self.removeFromSuperview()
        }
    }
    
    @objc private func shadeViewClick() {
        dismiss()
    }
    
    @objc private func closeBtnClick() {
        dismiss()
    }
    
    private func setupUI() {
        
        shadeView = UIView()
        shadeView.backgroundColor = RGB(0, 0, 0, 0.3)
        shadeView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(shadeViewClick)))
        addSubview(shadeView)
        shadeView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        contentView = UIView()
        contentView.backgroundColor = RGB(247, 247, 247)
        contentView.layer.cornerRadius = 20
        addSubview(contentView)
        contentView.snp.makeConstraints { make in
//            make.top.centerX.equalToSuperview()
            make.centerY.equalToSuperview()
            make.left.equalTo(SCRXFrom(10))
            make.right.equalTo(SCRXFrom(-9))
            make.height.equalTo(contentView.snp.width).multipliedBy(350.0 / 356)
        }
        
        titleLabel = UILabel(text: title, textColor: RGB(30, 35, 41), fontSize: 15, fontWeight: .light)
        contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(SCRYFrom(16))
            make.width.lessThanOrEqualTo(SCRXFrom(240))
        }
        
        closeBtn = UIButton(normalImageName: "close", target: self, action: #selector(closeBtnClick))
        contentView.addSubview(closeBtn)
        closeBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-10))
            make.top.equalTo(SCRYFrom(10))
        }
        
        flowLayout = UICollectionViewFlowLayout()
        flowLayout.minimumLineSpacing = SCRXFrom(8)
        flowLayout.minimumInteritemSpacing = SCRXFrom(8)
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
        collectionView.backgroundColor = .clear
        collectionView.register(CharacterViewCell.classForCoder(), forCellWithReuseIdentifier: "cell")
        collectionView.dataSource = self
        collectionView.delegate = self
        contentView.addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(14))
            make.right.equalTo(SCRXFrom(-14))
            make.top.equalTo(SCRYFrom(62))
            make.bottom.equalTo(SCRYFrom(-30))
        }
    }

}

extension CharacterSelectView: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return characters.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! CharacterViewCell
        cell.titleLabel.text = characters[indexPath.row]
        if selectIndex == indexPath.item {
            cell.backgroundColor = Bar_Color
            cell.titleLabel.textColor = .white
        }else {
            cell.backgroundColor = RGB(235, 235, 235)
            cell.titleLabel.textColor = TextBlack_Color
        }
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let colNum = 6
        var itemW = (collectionView.width - CGFloat(colNum - 1) * flowLayout.minimumInteritemSpacing) / CGFloat(colNum)
        itemW = CGFloat(floorf(Float(itemW) * 100) / 100.0)
        return CGSize(width: itemW, height: SCRYFrom(30))
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        
        selectCallback?(indexPath.item, characters[indexPath.row])
        dismiss()
    }
    
}


class CharacterViewCell: UICollectionViewCell {
    
    var titleLabel: UILabel!
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        layer.cornerRadius = 5
        backgroundColor = RGB(235, 235, 235)
        
        titleLabel = UILabel(text: nil, textColor: TextBlack_Color, fontSize: 15)
        titleLabel.font = UIFont.systemFont(ofSize: SCRYFrom(15), weight: .thin)
        titleLabel.textAlignment = .center
        contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.right.centerY.equalToSuperview()
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}
