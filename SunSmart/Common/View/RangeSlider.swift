import UIKit
import QuartzCore

class RangeSliderTrackLayer: CALayer {
    weak var rangeSlider: RangeSlider?
  
    var isEnabled: Bool = true {
        didSet {
            setNeedsDisplay()
        }
    }
    
  override func draw(in ctx: CGContext) {
    guard let slider = rangeSlider else {
      return
    }
    
    // Clip
    let cornerRadius = bounds.height * slider.curvaceousness / 2.0
    let path = UIBezierPath(roundedRect: bounds, cornerRadius: cornerRadius)
    ctx.addPath(path.cgPath)
    
    // Fill the track
    ctx.setFillColor(slider.trackTintColor.cgColor)
    ctx.addPath(path.cgPath)
    ctx.fillPath()
    
    // Fill the highlighted range
      let highlightColor = isEnabled ? slider.trackHighlightTintColor : slider.trackHighlightDisableTintColor
    ctx.setFillColor(highlightColor.cgColor)
      let lowerValuePosition = CGFloat(slider.positionForValue(slider.lowerValue)) - slider.thumbWidth * 0.5
    let upperValuePosition = CGFloat(slider.positionForValue(slider.upperValue)) - slider.thumbWidth * 0.5
    let rect = CGRect(x: lowerValuePosition, y: 0.0, width: upperValuePosition - lowerValuePosition, height: bounds.height)
    ctx.fill(rect)
  }
}

class RangeSliderThumbLayer: CALayer {
  
  var highlighted: Bool = false {
    didSet {
      setNeedsDisplay()
    }
  }
    var isEnabled: Bool = true {
        didSet {
            setNeedsDisplay()
        }
    }
    
  weak var rangeSlider: RangeSlider?
  
  var strokeColor: UIColor = UIColor.gray {
    didSet {
      setNeedsDisplay()
    }
  }
  var lineWidth: CGFloat = 0.5 {
    didSet {
      setNeedsDisplay()
    }
  }
  
  override func draw(in ctx: CGContext) {
    guard let slider = rangeSlider else {
      return
    }
    
    let thumbFrame = bounds.insetBy(dx: 9.0, dy: 9.0)
    let cornerRadius = thumbFrame.height * slider.curvaceousness / 2.0
    let thumbPath = UIBezierPath(roundedRect: thumbFrame, cornerRadius: cornerRadius)
    
    // Fill
      let thumbColor = isEnabled ? slider.thumbTintColor : slider.thumbDisableTintColor
    ctx.setFillColor(thumbColor.cgColor)
    ctx.addPath(thumbPath.cgPath)
    ctx.fillPath()
    
    // Outline
    ctx.setStrokeColor(strokeColor.cgColor)
    ctx.setLineWidth(lineWidth)
    ctx.addPath(thumbPath.cgPath)
      ctx.setShadow(offset: CGSize(width: 0, height: 2), blur: 4, color: UIColor.black.withAlphaComponent(0.3).cgColor)
      ctx.fillEllipse(in: thumbFrame)
    ctx.strokePath()
      
      
    
//    if highlighted {
//      ctx.setFillColor(UIColor(white: 0.0, alpha: 0.1).cgColor)
//      ctx.addPath(thumbPath.cgPath)
//      ctx.fillPath()
//    }
  }
}

@IBDesignable
public class RangeSlider: UIControl {
    
    private var internalPanGesture: UIPanGestureRecognizer!
    
  @IBInspectable public var minimumValue: Double = 0.0 {
//    willSet(newValue) {
//      assert(newValue < maximumValue, "RangeSlider: minimumValue should be lower than maximumValue")
//    }
    didSet {
      updateLayerFrames()
    }
  }
  
  @IBInspectable public var maximumValue: Double = 1.0 {
//    willSet(newValue) {
//      assert(newValue > minimumValue, "RangeSlider: maximumValue should be greater than minimumValue")
//    }
    didSet {
      updateLayerFrames()
    }
  }
    
    private var _lowerValue: Double = 0.2
  
  @IBInspectable public var lowerValue: Double {
      get {
          return _lowerValue
      }set {
          var newValue = newValue
          
          // 限制不能大于 upper - gap
          if newValue > upperValue - gapBetweenThumbs {
              newValue = upperValue - gapBetweenThumbs
          }
          // 限制不能超过最大值
          if newValue > maximumValue {
              newValue = maximumValue
          }
          _lowerValue = newValue
          updateLayerFrames()
      }
  }
  
    private var _upperValue: Double = 0.8
    
  @IBInspectable public var upperValue: Double {
      get {
          return _upperValue
      }
      set {
          var newValue = newValue
          
          // 限制不能小于 lower + gap
          if newValue < lowerValue + gapBetweenThumbs {
              newValue = lowerValue + gapBetweenThumbs
          }
          
          // 限制不能超过最大值
          if newValue > maximumValue {
              newValue = maximumValue
          }
          
          _upperValue = newValue
          updateLayerFrames()
      }
    
  }
    
    var trackLineHeight: CGFloat = 2 {
        didSet {
            updateLayerFrames()
        }
    }
    
    public override var isEnabled: Bool {
        didSet {
            trackLayer.isEnabled = isEnabled
            lowerThumbLayer.isEnabled = isEnabled
            upperThumbLayer.isEnabled = isEnabled
        }
    }
  
  var gapBetweenThumbs: Double {
    return 0.5 * Double(thumbWidth) * (maximumValue - minimumValue) / Double(bounds.width - thumbWidth * 2)
  }
  
    @IBInspectable public var trackTintColor: UIColor = UIColor(red: 229.0 / 255.0, green: 229 / 255.0, blue: 229 / 255.0, alpha: 1) {
    didSet {
      trackLayer.setNeedsDisplay()
    }
  }
  
  @IBInspectable public var trackHighlightTintColor: UIColor = UIColor(red: 0.0, green: 0.45, blue: 0.94, alpha: 1.0) {
    didSet {
      trackLayer.setNeedsDisplay()
    }
  }
    
    public var trackHighlightDisableTintColor: UIColor = UIColor(red: 0.0, green: 0.45, blue: 0.94, alpha: 1.0)
  
  @IBInspectable public var thumbTintColor: UIColor = UIColor.white {
    didSet {
      lowerThumbLayer.setNeedsDisplay()
      upperThumbLayer.setNeedsDisplay()
    }
  }
    
    public var thumbDisableTintColor: UIColor = UIColor.white
  
  @IBInspectable public var thumbBorderColor: UIColor = UIColor.gray {
    didSet {
      lowerThumbLayer.strokeColor = thumbBorderColor
      upperThumbLayer.strokeColor = thumbBorderColor
    }
  }
  
  @IBInspectable public var thumbBorderWidth: CGFloat = 0.5 {
    didSet {
      lowerThumbLayer.lineWidth = thumbBorderWidth
      upperThumbLayer.lineWidth = thumbBorderWidth
    }
  }
  
  @IBInspectable public var curvaceousness: CGFloat = 1.0 {
    didSet {
      if curvaceousness < 0.0 {
        curvaceousness = 0.0
      }
      
      if curvaceousness > 1.0 {
        curvaceousness = 1.0
      }
      
      trackLayer.setNeedsDisplay()
      lowerThumbLayer.setNeedsDisplay()
      upperThumbLayer.setNeedsDisplay()
    }
  }
  
  fileprivate var previouslocation = CGPoint()
  
  fileprivate let trackLayer = RangeSliderTrackLayer()
  fileprivate let lowerThumbLayer = RangeSliderThumbLayer()
  fileprivate let upperThumbLayer = RangeSliderThumbLayer()
  
  fileprivate var thumbWidth: CGFloat {
    return CGFloat(bounds.height)
  }
  
  override public var frame: CGRect {
    didSet {
      updateLayerFrames()
    }
  }
  
  override public init(frame: CGRect) {
    super.init(frame: frame)
    initializeLayers()
  }
  
  required public init?(coder: NSCoder) {
    super.init(coder: coder)
    initializeLayers()
  }
  
  override public func layoutSublayers(of: CALayer) {
    super.layoutSublayers(of:layer)
    updateLayerFrames()
  }
  
  fileprivate func initializeLayers() {
    layer.backgroundColor = UIColor.clear.cgColor
    
    trackLayer.rangeSlider = self
    trackLayer.contentsScale = UIScreen.main.scale
    layer.addSublayer(trackLayer)
    
    lowerThumbLayer.rangeSlider = self
    lowerThumbLayer.contentsScale = UIScreen.main.scale
    layer.addSublayer(lowerThumbLayer)
    
    upperThumbLayer.rangeSlider = self
    upperThumbLayer.contentsScale = UIScreen.main.scale
    layer.addSublayer(upperThumbLayer)
      
      // 添加一个透明的 pan 手势，为了抢占 gesture 权限
        internalPanGesture = UIPanGestureRecognizer(target: self, action: #selector(dummyPan))
//        internalPanGesture.delegate = self
        internalPanGesture.cancelsTouchesInView = false // 不拦截 touchesBegan
        self.addGestureRecognizer(internalPanGesture)
  }
  
    @objc private func dummyPan() {
        
    }
    
  func updateLayerFrames() {
      guard self.frame != .zero else {
          return
      }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
      var rect = bounds.insetBy(dx: thumbWidth / 2, dy: bounds.height * 0.5)
      rect.size.height = trackLineHeight
      trackLayer.frame = rect
      
    trackLayer.setNeedsDisplay()
    
    let lowerThumbCenter = CGFloat(positionForValue(lowerValue))
    lowerThumbLayer.frame = CGRect(x: lowerThumbCenter - thumbWidth/2.0, y: 0.0, width: thumbWidth, height: thumbWidth)
    lowerThumbLayer.setNeedsDisplay()
    
    let upperThumbCenter = CGFloat(positionForValue(upperValue))
    upperThumbLayer.frame = CGRect(x: upperThumbCenter - thumbWidth/2.0, y: 0.0, width: thumbWidth, height: thumbWidth)
    upperThumbLayer.setNeedsDisplay()
    
    CATransaction.commit()
  }
  
  func positionForValue(_ value: Double) -> Double {
    return Double(bounds.width - thumbWidth) * (value - minimumValue) /
    (maximumValue - minimumValue) + Double(thumbWidth/2.0)
  }
  
  func boundValue(_ value: Double, toLowerValue lowerValue: Double, upperValue: Double) -> Double {
    return min(max(value, lowerValue), upperValue)
  }
  
  
  // MARK: - Touches
  
  override public func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
    previouslocation = touch.location(in: self)
    
    // Hit test the thumb layers
      if upperThumbLayer.frame.contains(previouslocation) {
          upperThumbLayer.highlighted = true
      }else if lowerThumbLayer.frame.contains(previouslocation) {
          lowerThumbLayer.highlighted = true
      }
    
    return lowerThumbLayer.highlighted || upperThumbLayer.highlighted
  }
  
  override public func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
    let location = touch.location(in: self)
    
    // Determine by how much the user has dragged
    let deltaLocation = Double(location.x - previouslocation.x)
    let deltaValue = (maximumValue - minimumValue) * deltaLocation / Double(bounds.width - bounds.height)
    
    previouslocation = location
    
    // Update the values
    if lowerThumbLayer.highlighted {
      lowerValue = boundValue(lowerValue + deltaValue, toLowerValue: minimumValue, upperValue: upperValue - gapBetweenThumbs)
    } else if upperThumbLayer.highlighted {
      upperValue = boundValue(upperValue + deltaValue, toLowerValue: lowerValue + gapBetweenThumbs, upperValue: maximumValue)
    }
    
    sendActions(for: .valueChanged)
    
    return true
  }
  
  override public func endTracking(_ touch: UITouch?, with event: UIEvent?) {
    lowerThumbLayer.highlighted = false
    upperThumbLayer.highlighted = false
  }
    
    public override func cancelTracking(with event: UIEvent?) {
        print("cancel")
    }

}

