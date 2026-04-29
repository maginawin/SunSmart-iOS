//
//  FireAlarmTableReusable.swift
//  SunSmart
//
//  Created by Plato Jobs on 2026/4/20.
//

import UIKit

protocol TableReusable: AnyObject {
    static var reuseIdentifier: String { get }
}

extension TableReusable where Self: UIView {
    static var reuseIdentifier: String {
        String(describing: Self.self)
    }
}

extension UITableViewCell: TableReusable {}
extension UITableViewHeaderFooterView: TableReusable {}
extension UICollectionViewCell: TableReusable {}

extension UITableView {

    func register<T: UITableViewCell>(_ cellType: T.Type) {
        register(cellType, forCellReuseIdentifier: cellType.reuseIdentifier)
    }

    func dequeueReusableCell<T: UITableViewCell>(for indexPath: IndexPath) -> T {
        guard let cell = dequeueReusableCell(withIdentifier: T.reuseIdentifier, for: indexPath) as? T else {
            fatalError("Failed to dequeue cell: \(T.reuseIdentifier)")
        }
        return cell
    }
}

extension UICollectionView {

    func register<T: UICollectionViewCell>(_ cellType: T.Type) {
        register(cellType, forCellWithReuseIdentifier: cellType.reuseIdentifier)
    }

    func dequeueReusableCell<T: UICollectionViewCell>(for indexPath: IndexPath) -> T {
        guard let cell = dequeueReusableCell(withReuseIdentifier: T.reuseIdentifier, for: indexPath) as? T else {
            fatalError("Failed to dequeue cell: \(T.reuseIdentifier)")
        }
        return cell
    }
}
