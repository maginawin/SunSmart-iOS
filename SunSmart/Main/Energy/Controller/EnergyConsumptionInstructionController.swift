//
//  EnergyConsumptionInstructionController.swift
//  SunSmart
//
//  Created by yuankehong on 2025/5/7.
//

import UIKit

class EnergyConsumptionInstructionController: UIViewController {

    private var staticDataView: EnergyConsumptionInstructionView!
    private var timeSeriesDataView: EnergyConsumptionInstructionView!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        title = "energy_consumption_instruction".localizedString
        view.backgroundColor = Background_Color
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(named: "close")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(close))
        
        setupUI()
    }
    
    @objc private func close() {
        navigationController?.popViewController(animated: true)
    }
    
    private func setupUI() {
        
        staticDataView = EnergyConsumptionInstructionView(type: .staticData)
        staticDataView.titleLabel.text = "static_data".localizedString
        staticDataView.messageLabel.text = "static_data_instruction".localizedString
        view.addSubview(staticDataView)
        staticDataView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo(view.safeAreaLayoutGuide).offset(SCRYFrom(20))
        }
        
        timeSeriesDataView =  EnergyConsumptionInstructionView(type: .timeSeriesData)
        timeSeriesDataView.titleLabel.text = "time_series_data".localizedString
        timeSeriesDataView.messageLabel.text = "time_series_data_instruction".localizedString
        view.addSubview(timeSeriesDataView)
        timeSeriesDataView.snp.makeConstraints { make in
            make.left.right.equalTo(staticDataView)
            make.top.equalTo(staticDataView.snp.bottom).offset(SCRYFrom(40))
        }
        
    }


}
