#
# Be sure to run `pod lib lint SwiftyImageLoader.podspec' to ensure this is a
# valid spec before submitting.
#

Pod::Spec.new do |s|
  s.name             = 'SwiftyImageLoader'
  s.version          = '1.0.0'
  s.summary          = 'Pure Swift image loading library focused on simplicity and usability'
  s.homepage         = 'https://github.com/PeeJWeeJ/SwiftyImageLoader'

  s.license          = { :type => 'MIT',
  						 :file => 'LICENSE' }
  s.author           = { 'PJ Fechner' => 'peejweej.inc@gmail.com' }
  s.source           = { :git => 'https://github.com/PeeJWeeJ/SwiftyImageLoader.git',
  						 :tag => s.version.to_s }

  s.ios.deployment_target = '9.0'

  s.source_files = 'SwiftyImageLoader/Classes/**/*'
end
