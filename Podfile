# Uncomment the next line to define a global platform for your project
 platform :ios, '15.0'

abstract_target 'Common' do
  use_frameworks!
  
  # 自动布局
  pod 'SnapKit'
  # Bug捕捉
  pod 'Bugly'
  # 网络请求
  pod 'Moya', '~> 15.0'
  # Json
  pod 'SwiftyJSON', '~> 5.0.2'
  # zip解压
  pod 'ZIPFoundation', '~> 0.9'
  # 图表
#  pod 'Charts'

  target 'SunSmart' do
  end
  
  target 'Archipelago' do
  end
  
  target 'SylSmart' do
  end
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      deployment_target = config.build_settings['IPHONEOS_DEPLOYMENT_TARGET']
      next if deployment_target.nil?

      if Gem::Version.new(deployment_target) < Gem::Version.new('15.0')
        config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
      end
    end
  end
end

#target 'SunSmart' do
#  # Comment the next line if you don't want to use dynamic frameworks
#  use_frameworks!
#
#  # 自动布局
#  pod 'SnapKit'
#  # Bug捕捉
#  pod 'Bugly'
#  # 网络请求
#  pod 'Moya', '~> 15.0'
#  # Json
#  pod 'SwiftyJSON', '~> 5.0.2'
##  pod 'MMDrawerController'
#  # zip解压
#  pod 'ZIPFoundation', '~> 0.9'
#  # 图表
##  pod 'Charts'
#  # Pods for SunSmart
#  
#  target 'HomeeLife' do
#
#  end
#
#end
