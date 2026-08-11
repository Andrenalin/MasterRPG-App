#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "pathname"
require "set"

ROOT = Pathname(__dir__).parent.freeze
SWIFTUI_LITERAL_CALLS = %w[
  Button Label Toggle Picker Menu Section GroupBox TextField SecureField
  LabeledContent NavigationLink ContentUnavailableView ProgressView Gauge
].freeze
SWIFTUI_LITERAL_MODIFIERS = %w[
  navigationTitle navigationSubtitle accessibilityLabel accessibilityHint
  accessibilityValue help alert confirmationDialog
].freeze

CatalogResult = Struct.new(:path, :active, :german, :stale)
Issue = Struct.new(:path, :line, :message)
CATALOG_KEY_CACHE = {}

def line_number(source, offset)
  source[0...offset].count("\n") + 1
end

def call_ranges(source, name)
  ranges = []
  expression = /(?<![A-Za-z0-9_])#{Regexp.escape(name)}\s*\(/
  offset = 0

  while (match = expression.match(source, offset))
    opening = source.index("(", match.begin(0))
    depth = 0
    index = opening
    state = :code
    block_comment_depth = 0

    while index < source.length
      character = source[index]
      following = source[index, 2]

      case state
      when :code
        if following == "//"
          state = :line_comment
          index += 2
          next
        elsif following == "/*"
          state = :block_comment
          block_comment_depth = 1
          index += 2
          next
        elsif character == '"'
          state = :string
        elsif character == "("
          depth += 1
        elsif character == ")"
          depth -= 1
          if depth.zero?
            ranges << [match.begin(0), index + 1, opening + 1, index]
            offset = index + 1
            break
          end
        end
      when :string
        if character == "\\"
          index += 2
          next
        elsif character == '"'
          state = :code
        end
      when :line_comment
        state = :code if character == "\n"
      when :block_comment
        if following == "/*"
          block_comment_depth += 1
          index += 2
          next
        elsif following == "*/"
          block_comment_depth -= 1
          state = :code if block_comment_depth.zero?
          index += 2
          next
        end
      end

      index += 1
    end

    unless ranges.last&.first == match.begin(0)
      offset = match.end(0)
    end
  end

  ranges
end

def first_argument_is_literal?(arguments)
  arguments.lstrip.start_with?('"')
end

def first_literal_value(arguments)
  return nil if arguments.lstrip.start_with?('"""')

  match = arguments.lstrip.match(/\A"((?:\\.|[^"\\])*)"/m)
  return nil unless match
  return nil if match[1].include?("\\(") || match[1].include?("\\#")

  JSON.parse(%Q{"#{match[1]}"})
rescue JSON::ParserError
  nil
end

def catalog_path_for_source(relative)
  components = relative.split("/")
  if components.first == "Modules"
    ROOT.join("Modules", components.fetch(1), "Resources", "Localizable.xcstrings")
  elsif relative.start_with?("Sources/DiceRollerWidget/")
    ROOT.join("Sources/DiceRollerWidget/Localizable.xcstrings")
  elsif relative.start_with?("Sources/RPGShare/")
    ROOT.join("Sources/RPGShare/Localizable.xcstrings")
  elsif relative.start_with?("Sources/MasterRPG/") || relative.start_with?("Sources/MasterTV/")
    ROOT.join("Resources/Localizable.xcstrings")
  end
end

def active_catalog_keys(path)
  CATALOG_KEY_CACHE[path.to_s] ||= begin
    data = JSON.parse(path.read)
    data.fetch("strings").each_with_object(Set.new) do |(key, entry), keys|
      keys << key unless entry["extractionState"] == "stale"
    end.to_set
  end
end

def masking_comments(source)
  characters = source.chars
  masked = characters.dup
  state = :code
  block_depth = 0
  index = 0

  while index < characters.length
    character = characters[index]
    following = characters[index, 2]&.join

    case state
    when :code
      if following == "//"
        masked[index] = masked[index + 1] = " "
        state = :line_comment
        index += 2
        next
      elsif following == "/*"
        masked[index] = masked[index + 1] = " "
        state = :block_comment
        block_depth = 1
        index += 2
        next
      elsif character == '"'
        state = :string
      end
    when :string
      if character == "\\"
        index += 2
        next
      elsif character == '"'
        state = :code
      end
    when :line_comment
      if character == "\n"
        state = :code
      else
        masked[index] = " "
      end
    when :block_comment
      if following == "/*"
        masked[index] = masked[index + 1] = " "
        block_depth += 1
        index += 2
        next
      elsif following == "*/"
        masked[index] = masked[index + 1] = " "
        block_depth -= 1
        state = :code if block_depth.zero?
        index += 2
        next
      elsif character != "\n"
        masked[index] = " "
      end
    end

    index += 1
  end

  masked.join
end

def masking_preview_blocks(source)
  characters = source.chars
  masked = characters.dup
  search_offset = 0

  loop do
    preview_offset = source.index("#Preview", search_offset)
    break unless preview_offset

    opening = source.index("{", preview_offset)
    break unless opening

    depth = 0
    index = opening
    state = :code
    closing = nil
    while index < characters.length
      character = characters[index]
      if state == :string
        if character == "\\"
          index += 2
          next
        elsif character == '"'
          state = :code
        end
      elsif character == '"'
        state = :string
      elsif character == "{"
        depth += 1
      elsif character == "}"
        depth -= 1
        if depth.zero?
          closing = index
          break
        end
      end
      index += 1
    end

    break unless closing
    (preview_offset..closing).each do |masked_index|
      masked[masked_index] = " " unless masked[masked_index] == "\n"
    end
    search_offset = closing + 1
  end

  masked.join
end

def string_units(node)
  case node
  when Hash
    values = []
    values << node["value"] if node.key?("value")
    node.each_value { |value| values.concat(string_units(value)) }
    values
  when Array
    node.flat_map { |value| string_units(value) }
  else
    []
  end
end

def placeholders(value)
  printf_tokens = value.scan(/%(?!%)(?:\d+\$)?(?:[-+ 0#']*)(?:\d+|\*)?(?:\.(?:\d+|\*))?(?:hh|h|ll|l|L|z|j|t|q)?(?:@|[diuoxXfFeEgGaAcCsSp])/)
  shortcut_tokens = value.scan(/\$\{[A-Za-z0-9_.]+\}/)
  (printf_tokens + shortcut_tokens).map do |token|
    token
      .sub(/%\d+\$/, "%")
      .gsub(/[-+ 0#']/, "")
      .sub(/%\d+/, "%")
      .sub(/%\*/, "%")
      .sub(/\.\d+/, "")
      .sub(/\.\*/, "")
  end.sort
end

def audit_catalog(path, issues)
  relative = path.relative_path_from(ROOT).to_s
  data = JSON.parse(path.read)
  strings = data.fetch("strings")
  active = 0
  german = 0
  stale = 0

  strings.each do |key, entry|
    if entry["extractionState"] == "stale"
      stale += 1
      next
    end

    active += 1
    german_node = entry.dig("localizations", "de")
    german_values = string_units(german_node)
    if german_node.nil? || german_values.empty? || german_values.any? { |value| value.strip.empty? }
      issues << Issue.new(relative, 1, "active key #{key.inspect} has no complete German localization")
      next
    end
    german += 1

    source_node = entry.dig("localizations", data.fetch("sourceLanguage", "en"))
    source_values = string_units(source_node)
    source_values = [key] if source_values.empty?
    source_signatures = source_values.map { |value| placeholders(value) }.uniq

    german_values.each do |value|
      next if source_signatures.include?(placeholders(value))

      issues << Issue.new(
        relative,
        1,
        "placeholder mismatch for #{key.inspect}: source #{source_signatures.inspect}, German #{placeholders(value).inspect}"
      )
    end

    if entry["extractionState"] == "extracted_with_value" &&
       source_values.none? { |value| value.match?(/\s+\([^)]*\)\s*\z/) }
      german_values.each do |value|
        next unless value.match?(/\s+\([^)]*\)\s*\z/)

        issues << Issue.new(
          relative,
          1,
          "German value for #{key.inspect} leaks the catalog's contextual suffix into displayed text"
        )
      end
    end
  end

  if stale.positive?
    issues << Issue.new(relative, 1, "catalog contains #{stale} stale key(s); reconcile it with fresh compiler extraction")
  end

  CatalogResult.new(relative, active, german, stale)
rescue JSON::ParserError, KeyError => error
  issues << Issue.new(relative, 1, "invalid String Catalog: #{error.message}")
  CatalogResult.new(relative, 0, 0, 0)
end

def audit_module_source(path, issues)
  relative = path.relative_path_from(ROOT).to_s

  source = path.read
  scan_source = masking_preview_blocks(masking_comments(source))
  expected_bundle = relative.start_with?("Modules/") ? ".module" : ".main"
  accepted_bundles = if expected_bundle == ".module"
    ["bundle: .module", "bundle: LocString."]
  else
    ["bundle: .main"]
  end

  catalog_path = catalog_path_for_source(relative)
  if catalog_path&.exist?
    localized_call_names = %w[Text LocalizedStringResource NSLocalizedString]
    localized_call_names.each do |name|
      call_ranges(scan_source, name).each do |start_offset, _, arguments_start, arguments_end|
        arguments = source[arguments_start...arguments_end]
        key = first_literal_value(arguments)
        next unless key
        next if name == "Text" && arguments.lstrip.start_with?("verbatim:")
        next if active_catalog_keys(catalog_path).include?(key)

        issues << Issue.new(
          relative,
          line_number(source, start_offset),
          "localized key #{key.inspect} is missing from #{catalog_path.relative_path_from(ROOT)}"
        )
      end
    end

    %w[String AttributedString].each do |name|
      call_ranges(scan_source, name).each do |start_offset, _, arguments_start, arguments_end|
        arguments = source[arguments_start...arguments_end]
        next unless arguments.lstrip.start_with?("localized:")

        key = first_literal_value(arguments.lstrip.sub(/\Alocalized:\s*/, ""))
        next unless key
        next if active_catalog_keys(catalog_path).include?(key)

        issues << Issue.new(
          relative,
          line_number(source, start_offset),
          "localized key #{key.inspect} is missing from #{catalog_path.relative_path_from(ROOT)}"
        )
      end
    end
  end

  call_ranges(scan_source, "Text").each do |start_offset, _, arguments_start, arguments_end|
    arguments = source[arguments_start...arguments_end]
    next unless first_argument_is_literal?(arguments)
    next if accepted_bundles.any? { |bundle| arguments.include?(bundle) }

    issues << Issue.new(relative, line_number(source, start_offset), "Text literal must use bundle: #{expected_bundle} or Text(verbatim:)")
  end

  SWIFTUI_LITERAL_CALLS.each do |name|
    call_ranges(scan_source, name).each do |start_offset, _, arguments_start, arguments_end|
      arguments = source[arguments_start...arguments_end]
      next unless first_argument_is_literal?(arguments)

      issues << Issue.new(
        relative,
        line_number(source, start_offset),
        "#{name} literal uses the caller bundle; provide a Text label with bundle: #{expected_bundle}"
      )
    end
  end

  SWIFTUI_LITERAL_MODIFIERS.each do |name|
    call_ranges(scan_source, ".#{name}").each do |start_offset, _, arguments_start, arguments_end|
      arguments = source[arguments_start...arguments_end]
      next unless first_argument_is_literal?(arguments)

      issues << Issue.new(
        relative,
        line_number(source, start_offset),
        ".#{name} literal uses the caller bundle; provide localized Text/String with bundle: #{expected_bundle}"
      )
    end
  end

  %w[String AttributedString].each do |name|
    call_ranges(scan_source, name).each do |start_offset, _, arguments_start, arguments_end|
      arguments = source[arguments_start...arguments_end]
      next unless arguments.lstrip.match?(/\Alocalized:\s*"/)
      next if accepted_bundles.any? { |bundle| arguments.include?(bundle) }

      issues << Issue.new(relative, line_number(source, start_offset), "#{name}(localized:) must use bundle: #{expected_bundle}")
    end
  end

  call_ranges(scan_source, "NSLocalizedString").each do |start_offset, _, arguments_start, arguments_end|
    arguments = source[arguments_start...arguments_end]
    next if accepted_bundles.any? { |bundle| arguments.include?(bundle) } || arguments.include?("bundle: bundleForLocalizedStrings")

    issues << Issue.new(relative, line_number(source, start_offset), "NSLocalizedString must use the module bundle")
  end

  call_ranges(scan_source, "LocalizedStringResource").each do |start_offset, _, arguments_start, arguments_end|
    arguments = source[arguments_start...arguments_end]
    next if arguments.include?("bundle: #{expected_bundle}")
    # App Intents metadata only accepts direct literals. Xcode's metadata
    # exporter fails when `bundle` is supplied for these resources.
    next if relative.match?(%r{/(?:App)?Intent/})

    issues << Issue.new(relative, line_number(source, start_offset), "LocalizedStringResource must use bundle: #{expected_bundle}")
  end
end

def run_localization_verifier(arguments)
  issues = []
  audit_catalogs = !arguments.include?("--source-only")
  audit_sources = !arguments.include?("--catalog-only")

  catalog_paths = if audit_catalogs
    Dir.glob(ROOT.join("{Modules,Sources,Resources}/**/*.xcstrings")).map { |path| Pathname(path) }.sort
  else
    []
  end
  catalog_results = catalog_paths.map { |path| audit_catalog(path, issues) }

  production_sources = if audit_sources
    Dir.glob(ROOT.join("{Modules,Sources}/**/*.swift")).map { |path| Pathname(path) }.sort
  else
    []
  end
  production_sources.each { |path| audit_module_source(path, issues) }

  catalog_results.each do |result|
    puts format(
      "%-70s active %4d  German %4d  stale %4d",
      result.path,
      result.active,
      result.german,
      result.stale
    )
  end

  if issues.empty?
    puts "Localization verification passed: #{catalog_results.sum(&:active)} active keys and explicit resource bundles."
    return 0
  end

  warn "\nLocalization verification failed with #{issues.count} issue(s):"
  issues.each { |issue| warn "#{issue.path}:#{issue.line}: #{issue.message}" }
  1
end

exit run_localization_verifier(ARGV) if __FILE__ == $PROGRAM_NAME
