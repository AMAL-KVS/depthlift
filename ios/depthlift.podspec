Pod::Spec.new do |s|
  s.name             = 'depthlift'
  s.version          = '0.1.0'
  s.summary          = 'Convert any 2D image into a live 3D parallax scene.'
  s.description      = <<-DESC
  DepthLift uses on-device depth estimation (Core ML) and Metal rendering
  to transform any 2D image into an interactive 3D parallax scene.
                       DESC
  s.homepage         = 'https://github.com/yourusername/depthlift'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'Your Name' => 'your@email.com' }
  s.source           = { :http => 'https://github.com/yourusername/depthlift' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '14.0'
  s.swift_version    = '5.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
  }
end
