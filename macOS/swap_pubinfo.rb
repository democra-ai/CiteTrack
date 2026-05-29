#!/usr/bin/env ruby
require 'xcodeproj'

path = '/Users/tao.shen/google_scholar_plugin/macOS/CiteTrack_macOS.xcodeproj'
project = Xcodeproj::Project.open(path)
app_target = project.targets.find { |t| t.product_type == 'com.apple.product-type.application' } || project.targets.first
sources_group = project.main_group['Sources'] || project.main_group

# Remove the heavy CitationManager (only needed PublicationInfo, now shimmed).
project.files.select { |f| f.display_name == 'CitationManager.swift' }.each do |fref|
  app_target.source_build_phase.files.select { |bf| bf.file_ref == fref }.each(&:remove_from_project)
  fref.remove_from_project
  puts "removed: CitationManager.swift"
end

# Add the PublicationInfo shim.
shim = 'PublicationInfoShim.swift'
fref = project.files.find { |f| f.display_name == shim } || sources_group.new_reference(shim)
unless app_target.source_build_phase.files_references.include?(fref)
  app_target.source_build_phase.add_file_reference(fref)
  puts "added: #{shim}"
end

project.save
puts "saved"
