#!/usr/bin/env ruby
require 'xcodeproj'

path = '/Users/tao.shen/google_scholar_plugin/macOS/CiteTrack_macOS.xcodeproj'
project = Xcodeproj::Project.open(path)

app_target = project.targets.find { |t| t.product_type == 'com.apple.product-type.application' } || project.targets.first
sources_group = project.main_group['Sources'] || project.main_group

# Shared analysis engine — referenced relative to the Sources group (macOS/Sources)
# so ../../Shared/... resolves to repo/Shared/...
rel_paths = [
  '../../Shared/Managers/CitationManager.swift',
  '../../Shared/Models/CitationContext.swift',
  '../../Shared/Models/AnalysisResult.swift',
  '../../Shared/Services/CiteTrackAPIConfig.swift',
  '../../Shared/Services/OpenAlexEnrichmentClient.swift',
  '../../Shared/Services/SemanticScholarService.swift',
  '../../Shared/Services/CitationContextService.swift',
  '../../Shared/Services/CiteTrackAnalysisService.swift',
]

rel_paths.each do |rel|
  base = File.basename(rel)
  file_ref = project.files.find { |f| f.display_name == base && (f.path == rel || f.real_path.to_s.end_with?(rel.sub('../../', '/'))) }
  file_ref ||= project.files.find { |f| f.path == rel }
  if file_ref
    puts "ref exists: #{base}"
  else
    file_ref = sources_group.new_reference(rel)
    puts "added ref: #{base} (#{rel})"
  end
  unless app_target.source_build_phase.files_references.include?(file_ref)
    app_target.source_build_phase.add_file_reference(file_ref)
    puts "added to Sources phase: #{base}"
  end
end

project.save
puts "saved project: #{app_target.name}"
