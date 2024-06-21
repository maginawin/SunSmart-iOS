//
//  CustomActivityItemSource.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/6/12.
//

import Foundation

class CustomActivityItemSource: NSObject, UIActivityItemSource {
    private var text: String
    private var title: String
    private var image: UIImage
    
    init(image: UIImage, text: String, title: String) {
        self.image = image
        self.text = text
        self.title = title
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, thumbnailImageForActivityType activityType: UIActivity.ActivityType?, suggestedSize size: CGSize) -> UIImage? {
        return UIImage(named: "group_image_2")
    }
    
    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        return title
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        return image
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        return title
    }
}
