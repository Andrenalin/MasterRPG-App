#!/usr/bin/env ruby
# frozen_string_literal: true

# Audits the repository's SwiftUI source structure and computes declaration-level
# snapshot coverage. A view is covered when it is named as a `snapshot-root` in a
# test, or when it is a concrete child view reachable from one of those roots.
# This complements Xcode's line coverage: it answers "which View types are in a
# tested rendered tree?" while Xcode answers "which executable lines ran?".

require "pathname"
require "set"

ROOT = Pathname(__dir__).parent.freeze
MINIMUM_COVERAGE = Float(ENV.fetch("MINIMUM_VIEW_SNAPSHOT_COVERAGE", "80"))
SOURCE_GLOBS = ["Modules/**/*.swift", "Sources/**/*.swift"].freeze
TEST_GLOB = "Tests/**/*.swift"
EXCLUSIONS_PATH = ROOT.join("Scripts/snapshot_view_exclusions.txt")
SNAPSHOT_SUPPORT_PATH = ROOT.join("Tests/SnapshotTestSupport/SnapshotTestEnvironment.swift")
SNAPSHOT_ROOT = ROOT.join("Snapshots")
BASELINE_VARIANTS = %w[Xcode26 Xcode27].freeze

View = Struct.new(
  :key,
  :module_name,
  :name,
  :path,
  :source,
  :production_source,
  keyword_init: true
)

SnapshotRegistration = Struct.new(
  :key,
  :path,
  :line,
  keyword_init: true
)

def module_name(path)
  parts = path.each_filename.to_a
  root_index = parts.index { |part| part == "Modules" || part == "Sources" }
  parts.fetch(root_index + 1)
end

def view_declarations(source)
  source.scan(
    /^\s*(?:@\w+(?:\([^\n]*\))?\s+)*(?:(?:public|internal|private|fileprivate|package)\s+)*struct\s+([A-Za-z_]\w*)(?:\s*<[^>{}]*>)?\s*:\s*(?:SwiftUI\.)?View\b/m
  ).flatten
end

def preview_blocks(source)
  lines = source.lines
  blocks = []
  index = 0

  while index < lines.length
    unless lines[index].include?("#Preview")
      index += 1
      next
    end

    block = +""
    depth = 0
    saw_opening_brace = false
    while index < lines.length
      line = lines[index]
      block << line
      depth += line.count("{") - line.count("}")
      saw_opening_brace ||= line.include?("{")
      index += 1
      break if saw_opening_brace && depth <= 0
    end
    blocks << block
  end

  blocks
end

def removing_preview_blocks(source)
  preview_blocks(source).reduce(source) { |result, block| result.sub(block, "") }
end

def exclusions
  return {} unless EXCLUSIONS_PATH.exist?

  EXCLUSIONS_PATH.each_line(chomp: true).each_with_object([]) do |line, entries|
    entry = line.strip
    next if entry.empty? || entry.start_with?("#")

    key, reason = entry.split(/\s+#\s+/, 2)
    entries << [key.strip, reason&.strip || "No reason supplied"]
  end.to_h
end

source_paths = SOURCE_GLOBS.flat_map { |glob| ROOT.glob(glob) }.uniq.sort
views = source_paths.flat_map do |path|
  source = path.read
  names = view_declarations(source)
  names.map do |name|
    owner = module_name(path.relative_path_from(ROOT))
    View.new(
      key: "#{owner}::#{name}",
      module_name: owner,
      name: name,
      path: path.relative_path_from(ROOT).to_s,
      source: source,
      production_source: removing_preview_blocks(source)
    )
  end
end

errors = []
views.group_by(&:path).each do |path, declarations|
  names = declarations.map(&:name)
  errors << "#{path}: contains #{names.length} View declarations (#{names.join(', ')})" if names.length > 1

  declarations.each do |view|
    previews = preview_blocks(view.source)
    errors << "#{path}: #{view.name} has no #Preview" if previews.empty?
    direct = previews.any? do |preview|
      preview.match?(/\b#{Regexp.escape(view.name)}\s*(?:<[^>]+>)?\s*(?:\(|\{)/)
    end
    errors << "#{path}: #Preview does not directly construct #{view.name}" unless direct
  end
end

duplicates = views.group_by(&:key).select { |_key, entries| entries.length > 1 }
duplicates.each do |key, entries|
  errors << "#{key}: declared more than once (#{entries.map(&:path).join(', ')})"
end

by_key = views.to_h { |view| [view.key, view] }
by_name = views.group_by(&:name)

edges = Hash.new { |hash, key| hash[key] = Set.new }
views.each do |view|
  view.production_source.scan(/\b([A-Z][A-Za-z0-9_]*)\s*(?:<[^>\n]+>)?\s*(?:\(|\{)/).flatten.uniq.each do |referenced_name|
    candidates = by_name.fetch(referenced_name, [])
    same_module = candidates.select { |candidate| candidate.module_name == view.module_name }
    target = if same_module.length == 1
               same_module.first
             elsif candidates.length == 1
               candidates.first
             end
    edges[view.key] << target.key if target && target.key != view.key
  end
end

registrations = []
ROOT.glob(TEST_GLOB).sort.each do |path|
  source = path.read
  relative_path = path.relative_path_from(ROOT).to_s
  contains_assertion = path != SNAPSHOT_SUPPORT_PATH && source.match?(/\bassertRepositorySnapshot\s*\(/)
  contains_direct_assertion = source.match?(/\bassertSnapshot\s*\(/)

  if contains_direct_assertion
    errors << "#{relative_path}: use assertRepositorySnapshot so the baseline is stored under Snapshots/<XcodeVersion>"
  end

  if contains_assertion
    unless source.include?(".deterministicSnapshotEnvironment()")
      errors << "#{relative_path}: snapshot assertion does not apply the shared deterministic environment"
    end
    unless source.match?(/@Suite\s*\(\s*\.serialized\b.*?\.snapshots\b/m)
      errors << "#{relative_path}: snapshot assertions must be in a serialized Swift Testing snapshot suite"
    end

    test_target = path.dirname.basename.to_s
    suite_name = path.basename(".swift").to_s
    xcode_27_directory = SNAPSHOT_ROOT.join("Xcode27", test_target, suite_name)
    unless xcode_27_directory.directory?
      errors << "#{relative_path}: missing Xcode27 baseline directory #{xcode_27_directory.relative_path_from(ROOT)}"
    end
  end

  lines = source.lines
  lines.each_with_index do |line, index|
    match = line.match(%r{//\s*snapshot-root:\s*([A-Za-z0-9_]+::[A-Za-z0-9_]+)\s*$})
    next unless match

    following_line = lines[(index + 1)..]&.find do |candidate|
      stripped = candidate.strip
      !stripped.empty? && !stripped.start_with?("//")
    end
    unless following_line&.match?(/^\s*@Test\b/)
      errors << "#{relative_path}:#{index + 1}: snapshot-root must be attached to the following @Test"
    end
    unless contains_assertion
      errors << "#{relative_path}:#{index + 1}: registered snapshot root has no SnapshotTesting assertion"
    end

    registrations << SnapshotRegistration.new(
      key: match[1],
      path: relative_path,
      line: index + 1
    )
  end
end

BASELINE_VARIANTS.each do |variant|
  directory = SNAPSHOT_ROOT.join(variant)
  errors << "Missing root snapshot baseline directory #{directory.relative_path_from(ROOT)}" unless directory.directory?
end

legacy_references = ROOT.glob("Tests/**/__Snapshots__/**/*").select(&:file?)
legacy_references.each do |path|
  errors << "#{path.relative_path_from(ROOT)}: move reference files into Snapshots/<XcodeVersion>/<TestTarget>/<Suite>"
end

unless SNAPSHOT_SUPPORT_PATH.exist?
  errors << "Missing shared snapshot support at #{SNAPSHOT_SUPPORT_PATH.relative_path_from(ROOT)}"
else
  snapshot_support = SNAPSHOT_SUPPORT_PATH.read
  unless snapshot_support.match?(/verifySnapshot\s*\(.*?snapshotDirectory:\s*SnapshotReferenceLocation\.directory/m)
    errors << "Shared snapshot assertion must pass an explicit root-level snapshotDirectory to verifySnapshot"
  end
  unless snapshot_support.include?('object(forInfoDictionaryKey: "DTXcode")')
    errors << "Shared snapshot location must select its baseline from the test bundle's DTXcode metadata"
  end
  unless snapshot_support.include?('"SNAPSHOT_BASELINE_VARIANT"')
    errors << "Shared snapshot location must support the SNAPSHOT_BASELINE_VARIANT override"
  end
end

snapshot_roots = registrations.map(&:key).to_set
snapshot_roots.merge(
  ENV.fetch("EXTRA_SNAPSHOT_ROOTS", "").split(",").map(&:strip).reject(&:empty?)
)

snapshot_roots.each do |key|
  errors << "Snapshot root #{key} does not match a concrete View declaration" unless by_key.key?(key)
end

excluded = exclusions
excluded.each_key do |key|
  errors << "Snapshot exclusion #{key} does not match a concrete View declaration" unless by_key.key?(key)
end

covered = Set.new
queue = snapshot_roots.to_a
until queue.empty?
  key = queue.shift
  next if covered.include?(key) || !by_key.key?(key)

  covered << key
  edges[key].each { |child| queue << child }
end

eligible = by_key.keys.to_set - excluded.keys.to_set
covered &= eligible

puts "SwiftUI source audit"
puts "  concrete views: #{views.length}"
puts "  snapshot registrations: #{registrations.length}"
puts "  unique snapshot roots: #{snapshot_roots.length}"
puts "  explicit exclusions: #{excluded.length}"
puts

eligible.group_by { |key| by_key.fetch(key).module_name }.sort.each do |owner, keys|
  module_covered = keys.count { |key| covered.include?(key) }
  percent = keys.empty? ? 100.0 : module_covered.fdiv(keys.length) * 100
  puts format("  %-24s %4d / %-4d %6.2f%%", owner, module_covered, keys.length, percent)
end

percentage = eligible.empty? ? 100.0 : covered.length.fdiv(eligible.length) * 100
puts
puts format("Snapshot view coverage: %d / %d (%.2f%%), required %.2f%%", covered.length, eligible.length, percentage, MINIMUM_COVERAGE)

unless errors.empty?
  warn "\nAudit errors:"
  errors.sort.each { |error| warn "  - #{error}" }
end

if percentage < MINIMUM_COVERAGE
  uncovered = eligible - covered
  warn "\nUncovered views (first 50):"
  uncovered.to_a.sort.first(50).each do |key|
    warn "  - #{key} (#{by_key.fetch(key).path})"
  end
  warn "  ... #{uncovered.length - 50} more" if uncovered.length > 50
end

exit(errors.empty? && percentage >= MINIMUM_COVERAGE ? 0 : 1)
