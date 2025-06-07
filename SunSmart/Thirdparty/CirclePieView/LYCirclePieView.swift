//
//  LYCirclePieView.swift
//  LYAdmin
//
//  Created by c.c on 2020/11/10.
//  Copyright © 2020 c.c. All rights reserved.
//

import UIKit

protocol LYCirclePieViewDelegate: AnyObject {
    
    /// 点击饼状图对应扇区回调 percent：对应扇区 pieColor: 颜色 point: 扇区中心点
    func circlePieView(_ circlePieView: LYCirclePieView, didSelectedPiePercent percent: LYAnglePercent, pieColor: UIColor, point: CGPoint)
    
}

/// 饼状图
@IBDesignable
class LYCirclePieView: UIView {
    
    var centerRadius:CGFloat = 60
    var pieRadius:CGFloat = 95
    
    var pieVisual:LYPieVisual!
    
    var angles: Array<LYAnglePercent> {
        pieVisual.angles
    }
    
    var colors:[UIColor] {
        pieVisual.colors
    }
    
    lazy var markerView: CirclePieMarkerView = {
        let markerView = CirclePieMarkerView()
        return markerView
    }()
    
    weak var delegate: LYCirclePieViewDelegate?
    
    let bottomColor: UIColor = #colorLiteral(red: 0.9254901961, green: 0.9254901961, blue: 0.9254901961, alpha: 1)
    
    override func draw(_ rect: CGRect) {
        super.draw(rect)
        guard pieVisual != nil else { return }
        
        let context = UIGraphicsGetCurrentContext()!
        let circleCenter = bounds.mid
        
        for index in 0..<angles.count {
            // 绘弧线
            draw(angle: angles[index], withColor: colors[index % colors.count], using: context)
        }
        
        // 如果没有angle 则单独绘制 0%
        // 如果有剩余 灰色补齐剩余
        if angles.count == 0 {
            drawZeroCicle(using: context)
        }
        else if pieVisual.totalPercent < 1 {
            let remaining = 1 - pieVisual.totalPercent
            let start = pieVisual.totalPercent
            
            let lastAngle = LYAnglePercent(title: nil, detail: nil, percentStart: start, percentLength: remaining)

            draw(angle: lastAngle, withColor: bottomColor, using: context)
        }
        
        context.move(to: circleCenter)
        context.addArc(center: circleCenter, radius: centerRadius, startAngle: 0, endAngle: CGFloat.pi * 2, clockwise: false)
        context.closePath()
        context.setFillColor(UIColor.systemBackground.cgColor)
        context.fillPath()
    }
    
    override var intrinsicContentSize: CGSize {
        return CGSize(width: 330, height: 270)
    }
    
    override func sizeThatFits(_ size: CGSize) -> CGSize {
        return CGSize(width: 330, height: 270)
    }
    
    private func getColor(_ index: Int) -> UIColor {
        return colors[index % colors.count]
    }
    
    // MARK: - Drawing
    
    /// 绘制弧线
    func draw(angle: LYAnglePercent, withColor color: UIColor, using context: CGContext) {
        let circleCenter = bounds.mid
        
        let path = UIBezierPath()
        path.move(to: circleCenter)
        path.addArc(withCenter: circleCenter, radius: pieRadius, startAngle: angle.startAngle, endAngle: angle.endAngle, clockwise: true)
        path.close()
        path.lineWidth = 0
        
        color.setFill()
        UIColor.white.setStroke()
        
        path.fill()
        path.stroke()
        
        // 绘外置点
        guard angle.title != nil else { return }
        
        let textTranslation = angle.getTranslation(newRadius: pieRadius)
        let textStartPoint = CGPoint(
            x: circleCenter.x + textTranslation.width,
            y: circleCenter.y + textTranslation.height
        )
        
        context.move(to: textStartPoint)
//        context.addArc(center: textStartPoint, radius: 4, startAngle: 0, endAngle: CGFloat.pi * 2, clockwise: false)
        context.closePath()
        
        context.setFillColor(color.cgColor)
        context.fillPath()
        
        // 延长线
        context.move(to: textStartPoint)
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(1)
        // 0度 90度上下设置多一些偏移值，避免重叠
//        var offset: CGFloat = 0
//        
//        let centerAngle = (angle.percentStart + angle.percentLength / 2) * 360 - 90 // 每个扇区中点角度
//        let centerAngleRad = centerAngle * .pi / 180 // 转弧度
//
//        let normalizedAngle = centerAngleRad.truncatingRemainder(dividingBy: 360)
//        // 计算离90°或270°的最近距离
//        let distanceTo90 = abs(normalizedAngle - 90)
//        let distanceTo270 = abs(normalizedAngle - 270)
//        // 设一个容忍范围，比如30°
//        let tolerance: Double = 20.0
//        
//        if distanceTo90 <= tolerance {
//            // 靠近顶部，偏移向下
//            let ratio = (tolerance - distanceTo90) / tolerance  // 距离越近偏移越大
//            offset = CGFloat(ratio) * tolerance
//        } else if distanceTo270 <= tolerance {
//            // 靠近底部，偏移向上
//            let ratio = (tolerance - distanceTo270) / tolerance
//            offset = CGFloat(-ratio) * tolerance
//        } else {
//            // 其他角度，不偏移
//            offset = 0
//        }
        
        // 计算偏移量
//        let yOffset = sin(centerAngleRad) * 20.0 // 最大偏移20px，根据sin变化
        
//        if (angle.percentStart >= 0 && angle.percentStart <= 0.05) || (angle.percentStart >= 0.95 && angle.percentStart <= 1) {
//            
//            print("\(angle.title) -20")
//            offset = -20
//        }else if angle.percentStart >= 0.45 && angle.percentStart <= 0.55 {
//            offset = 20
//            print("\(angle.title) +20")
//        }
//        print("\(angle.title) \(offset)")
        // 折线
        let line_1_translation = angle.getTranslation(newRadius: pieRadius + 20)
        let line_1_point = CGPoint(
            x: circleCenter.x + line_1_translation.width,
            y: circleCenter.y + line_1_translation.height
        )
        
        // 平线
        let line_2_x_offset:CGFloat = line_1_translation.width > 0 ? 62:-62
        let line_2_point = CGPoint(
            x: line_1_point.x + line_2_x_offset,
            y: line_1_point.y
        )
        
        context.addLines(between: [textStartPoint, line_1_point, line_2_point])
        context.strokePath()
        
        // 上字
        let topText = NSAttributedString(
            string: angle.title,
            attributes: [
                NSAttributedString.Key.font : UIFont.systemFont(ofSize: 12),
                NSAttributedString.Key.foregroundColor: UIColor.black.withAlphaComponent(0.7)
            ]
        )
        
        let topTextSize = topText.size()
        let topTextPoint = CGPoint(
            x: line_2_point.x + (line_1_translation.width > 0 ? -topTextSize.width: 0),
            y: line_2_point.y - 1 - topTextSize.height
        )
        
        topText.draw(at: topTextPoint)
        
        // 下字
        guard let detailText = angle.detail else {
            return
        }
        
        let bottomText = NSAttributedString(
            string: detailText,
            attributes: [
                NSAttributedString.Key.font : UIFont.systemFont(ofSize: 12, weight: UIFont.Weight.bold),
                NSAttributedString.Key.foregroundColor: color
            ]
        )
        
        let bottomTextSize = bottomText.size()
        let bottomTextPoint = CGPoint(
            x: line_2_point.x + (line_1_translation.width > 0 ? -bottomTextSize.width: 0),
            y: line_2_point.y + 1
        )
        
        bottomText.draw(at: bottomTextPoint)
    }
    
    /// 绘制 纯灰圈(0%)
    func drawZeroCicle(using context: CGContext) {
        let circleCenter = bounds.mid
        
        let path = UIBezierPath()
        path.move(to: circleCenter)
        path.addArc(withCenter: circleCenter, radius: pieRadius, startAngle: 0, endAngle: CGFloat.pi * 2, clockwise: true)
        path.close()
        path.lineWidth = 3
        
        bottomColor.setFill()
        UIColor.white.setStroke()
        
        path.fill()
        
//        // 三角函数
//        let rad30 = 30.0 * CGFloat.pi / 180.0
//        
//        // 绘外置点
//        let textStartPoint = CGPoint(
//            x: circleCenter.x + (pieRadius + 15) * cos(rad30),
//            y: circleCenter.y + (pieRadius + 15) * sin(rad30)
//        )
//        
//        context.move(to: textStartPoint)
//        context.addArc(center: textStartPoint, radius: 4, startAngle: 0, endAngle: CGFloat.pi * 2, clockwise: false)
//        context.closePath()
//        
//        context.setFillColor(#colorLiteral(red: 1, green: 0.4392156863, blue: 0.2392156863, alpha: 1))
//        context.fillPath()
//        
//        // 延长线
//        context.move(to: textStartPoint)
//        context.setStrokeColor(#colorLiteral(red: 1, green: 0.4392156863, blue: 0.2392156863, alpha: 1))
//        context.setLineWidth(1.5)
//        
//        // 折线
//        let line_1_point = CGPoint(
//            x: circleCenter.x + (pieRadius + 25) * cos(rad30),
//            y: circleCenter.y + (pieRadius + 25) * sin(rad30)
//        )
//        
//        // 平线
//        let line_2_x_offset:CGFloat = 62
//        let line_2_point = CGPoint(
//            x: line_1_point.x + line_2_x_offset,
//            y: line_1_point.y
//        )
//        
//        context.addLines(between: [textStartPoint, line_1_point, line_2_point])
//        context.strokePath()
//        
//        // 上字
//        let topText = NSAttributedString(
//            string: "0%",
//            attributes: [
//                NSAttributedString.Key.font : UIFont.systemFont(ofSize: 14),
//                NSAttributedString.Key.foregroundColor: UIColor.black.withAlphaComponent(0.7)
//            ]
//        )
//        
//        let topTextSize = topText.size()
//        let topTextPoint = CGPoint(
//            x: line_2_point.x +  -topTextSize.width,
//            y: line_2_point.y - 5 - topTextSize.height
//        )
//        
//        topText.draw(at: topTextPoint)
    }
    
    // MARK: - nib
    
    override func prepareForInterfaceBuilder() {
        super.prepareForInterfaceBuilder()
        self.pieVisual = LYPieVisual.demo
    }
    
    // MARK: - Action
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        
        guard let point = touches.first?.location(in: self) else { return }
        
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        
        // Step 1: 判断是否在圆内
        let dx = point.x - center.x
        let dy = point.y - center.y
        let distance = sqrt(dx*dx + dy*dy)
        
        if distance > pieRadius || distance < centerRadius {
            return  // 不在扇形范围内
        }
        
        // Step 2: 计算点击点对应角度
        let angle = atan2(dy, dx)
        // 3. 将角度转换到与你系统相同的坐标系（-π/2作为起点）
        let normalizedTouchAngle = (angle + .pi * 2 + .pi / 2).truncatingRemainder(dividingBy: .pi * 2)
        
        // 4. 转换为百分比形式（0.0~1.0）
        let touchPercent = normalizedTouchAngle / (.pi * 2)
        
        
        // Step 3: 判断点击命中哪个扇区
        
        for (index, pieAngle) in angles.enumerated() {
            if touchPercent >= pieAngle.percentStart && touchPercent <= pieAngle.percentStart + pieAngle.percentLength {
                // ✅ 命中扇区
                //                    selectedSector = sector
                //                    showAnnotation(for: sector, at: point)
                let midAngle = (pieAngle.startAngle + pieAngle.endAngle) / 2
                let r = pieRadius * 0.8 // 控制偏移距离，比如 0.7 表示 70% 半径处放置标注
                
                let x = center.x + r * cos(midAngle)
                let y = center.y + r * sin(midAngle)
                
                delegate?.circlePieView(self, didSelectedPiePercent: pieAngle, pieColor: colors[index % colors.count], point: CGPoint(x: x, y: y))
//                markerView.updateData(data: pieAngle, color: colors[index % colors.count])
//                
//                if markerView.superview == nil {
//                    markerView.isHidden = false
//                    addSubview(markerView)
//                    markerView.snp.makeConstraints { make in
//                        make.center.equalTo(CGPoint(x: x, y: y))
//                        make.height.equalTo(38)
//                    }
//                }else {
//                    markerView.isHidden = false
//                    markerView.snp.updateConstraints { make in
//                        make.center.equalTo(CGPoint(x: x, y: y))
//                    }
//                }
                break
            }
        }
        
    }
    
}

extension CGRect {
    
    var mid: CGPoint { return CGPoint(x: midX, y: midY) }
    var upperLeft: CGPoint { return CGPoint(x: minX, y: minY) }
    var lowerLeft: CGPoint { return CGPoint(x: minX, y: maxY) }
    var upperRight: CGPoint { return CGPoint(x: maxX, y: minY) }
    var lowerRight: CGPoint { return CGPoint(x: maxX, y: maxY) }
    
    init(center: CGPoint, size: CGSize) {
        let upperLeft = CGPoint(x: center.x-size.width/2, y: center.y-size.height/2)
        self.init(origin: upperLeft, size: size)
    }
    
}
