//
//  EmerFireAlarmMonitorDelegates.swift
//  SunSmart
//
//  Created by Plato Jobs on 2026/5/7.
//

import UIKit
import NordicSigMeshSDK

extension EmerFireAlarmMonitorVC: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return groups.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! EmerFireAlarmMoniCell
        let group = groups[indexPath.row].group
        cell.configure(title: group.name, isOn: group.isOn)
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard indexPath.item < groups.count else { return }
        toggleAssociatedGroup(groups[indexPath.item].group)
    }
    
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        let page = Int(scrollView.contentOffset.x / scrollView.frame.size.width + 0.5)
        
        pageControl.currentPage = page
        
    }
    

}

extension EmerFireAlarmMonitorVC: MeshLibManagerMessageDelegate {

    func meshNetworkManager(_ manager: MeshNetworkManager, didReceiveMessage message: MeshMessage, sentFrom source: Address, to destination: Address) {
        EmergencyFireControllerSceneEventManager.dispatch(message: message, source: source, destination: destination)
    }

    func meshNetworkManager(_ manager: MeshNetworkManager, deviceDataUpdate node: Node) {
        renderNodeAvailabilityChange(node)
    }
}
