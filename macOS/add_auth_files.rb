#!/usr/bin/env ruby
require 'xcodeproj'

path = '/Users/tao.shen/google_scholar_plugin/macOS/CiteTrack_macOS.xcodeproj'
project = Xcodeproj::Project.open(path)

app_target = project.targets.find { |t| t.product_type == 'com.apple.product-type.application' } || project.targets.first
sources_group = project.main_group['Sources'] || project.main_group

new_files = ['GoogleAuthService.swift', 'GoogleSignInView.swift', 'LiquidGlassMac.swift', 'MacInsightsView.swift', 'MacMainWindow.swift']

new_files.each do |fname|
  file_ref = project.files.find { |f| f.display_name == fname }
  if file_ref
    puts "ref exists: #{fname}"
  else
    file_ref = sources_group.new_reference(fname)
    puts "added ref: #{fname}"
  end
  unless app_target.source_build_phase.files_references.include?(file_ref)
    app_target.source_build_phase.add_file_reference(file_ref)
    puts "added to Sources phase: #{fname}"
  end
end

project.save
puts "saved project: #{app_target.name}"
