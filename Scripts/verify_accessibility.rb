#!/usr/bin/env ruby
# frozen_string_literal: true

require "pathname"
require_relative "verify_localization"

AccessibilityIssue = Struct.new(:path, :line, :message)

ACCESSIBILITY_ROOT = Pathname(__dir__).parent.freeze
SPECIALIZED_FIXED_FONT_FILES = [].freeze

def accessibility_source_paths
  Dir.glob(ACCESSIBILITY_ROOT.join("{Modules,Sources}/**/*.swift"))
    .map { |path| Pathname(path) }
    .sort
end

def accessibility_scan_source(path)
  masking_preview_blocks(masking_comments(path.read))
end

def add_regex_issues(source, relative, expression, message, issues)
  source.to_enum(:scan, expression).each do
    match = Regexp.last_match
    issues << AccessibilityIssue.new(relative, line_number(source, match.begin(0)), message)
  end
end

def audit_accessibility_source(path, issues)
  relative = path.relative_path_from(ACCESSIBILITY_ROOT).to_s
  original = path.read
  source = accessibility_scan_source(path)

  unless SPECIALIZED_FIXED_FONT_FILES.include?(relative)
    add_regex_issues(
      source,
      relative,
      /\.font\s*\(\s*\.system\s*\(\s*size\s*:/,
      "fixed font size bypasses Dynamic Type; use a semantic text style or a resizable image",
      issues
    )
  end

  add_regex_issues(
    source,
    relative,
    /\.fontWeight\s*\(/,
    "fontWeight is disallowed by the project UI rules; use bold() or an appropriate semantic style",
    issues
  )

  source.to_enum(:scan, /\.onTapGesture\b/).each do
    match = Regexp.last_match
    suffix = source[match.begin(0), 180]
    next if suffix.match?(/onTapGesture\s*\(\s*(?:count|coordinateSpace)\s*:/)

    issues << AccessibilityIssue.new(
      relative,
      line_number(original, match.begin(0)),
      "simple tap interaction must be a Button; gestures are reserved for tap count or location"
    )
  end

  source.to_enum(:scan, /repeatForever\s*\(/).each do
    match = Regexp.last_match
    unless source.include?("accessibilityReduceMotion")
      issues << AccessibilityIssue.new(
        relative,
        line_number(original, match.begin(0)),
        "continuous animation does not honor Reduce Motion"
      )
    end
  end

  call_ranges(source, "TimelineView").each do |start_offset, _, arguments_start, arguments_end|
    arguments = source[arguments_start...arguments_end]
    next unless arguments.include?(".animation")
    next if arguments.include?("paused:") && source.include?("accessibilityReduceMotion")

    issues << AccessibilityIssue.new(
      relative,
      line_number(original, start_offset),
      "animation timeline must pause when Reduce Motion is enabled"
    )
  end

  call_ranges(source, "Slider").each do |start_offset, end_offset, arguments_start, arguments_end|
    arguments = source[arguments_start...arguments_end]
    suffix = source[end_offset, 700] || ""
    has_label = arguments.include?("label:") || suffix.match?(/\A\s*\{\s*(?:Text|Label)\s*\(/)
    has_accessibility_label = suffix.include?(".accessibilityLabel(")
    next if has_label || has_accessibility_label

    issues << AccessibilityIssue.new(
      relative,
      line_number(original, start_offset),
      "Slider requires an explicit localized label"
    )
  end

  source.to_enum(:scan, /^\s*\.opacity\s*\(\s*0(?:\.0+)?\s*\)/).each do
    match = Regexp.last_match
    nearby = source[match.begin(0), 500] || ""
    next if nearby.include?(".allowsHitTesting(false)") && nearby.include?(".accessibilityHidden(true)")

    issues << AccessibilityIssue.new(
      relative,
      line_number(original, match.begin(0)),
      "fully transparent content must also disable hit testing and accessibility exposure"
    )
  end
end

def run_accessibility_verifier
  issues = []
  accessibility_source_paths.each { |path| audit_accessibility_source(path, issues) }

  if issues.empty?
    puts "Accessibility source verification passed across #{accessibility_source_paths.count} production Swift files."
    return 0
  end

  warn "Accessibility source verification failed with #{issues.count} issue(s):"
  issues.each { |issue| warn "#{issue.path}:#{issue.line}: #{issue.message}" }
  1
end

exit run_accessibility_verifier if __FILE__ == $PROGRAM_NAME
