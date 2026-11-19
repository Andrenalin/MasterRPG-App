#!/usr/bin/env ruby
# frozen_string_literal: true

# Generates Swift Testing + SnapshotTesting cases from the repository's direct
# same-file #Preview bodies. The generated tests deliberately live in source
# control: review them like any other test, and regenerate after changing a
# preview fixture. Pass one or more module names to regenerate only those
# outputs, for example: `ruby Scripts/generate_snapshot_tests.rb DiceRPG`.

require "pathname"

ROOT = Pathname(__dir__).parent.freeze
MODULES = {
  "AdventureRPG" => "AdventureRPGSnapshotTests",
  "AudioRPG" => "AudioRPGSnapshotTests",
  "CharacterRPG" => "CharacterRPGSnapshotTests",
  "CoreRPG" => "CoreRPGSnapshotTests",
  "DiceRPG" => "DiceRPGSnapshotTests",
  "GameRPG" => "GameRPGSnapshotTests",
  "GeneratorRPG" => "GeneratorRPGSnapshotTests",
  "MapRPG" => "MapRPGSnapshotTests",
  "PdfRPG" => "PdfRPGSnapshotTests",
  "PhotoRPG" => "PhotoRPGSnapshotTests",
  "RolePlayGameKit" => "GameRPGSnapshotTests",
  "SpaceRPG" => "SpaceRPGSnapshotTests",
  "TableRPG" => "TableRPGSnapshotTests",
  "WeatherRPG" => "WeatherRPGSnapshotTests"
}.freeze

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

def preview_body(block)
  opening = block.index("{")
  closing = block.rindex("}")
  return nil unless opening && closing && closing > opening

  lines = block[(opening + 1)...closing].lines
  nonblank = lines.reject { |line| line.strip.empty? }
  indentation = nonblank.map { |line| line[/^\s*/].length }.min || 0
  lines.map { |line| line.sub(/^\s{0,#{indentation}}/, "") }.join.strip
end

def direct_preview_for(name, source)
  preview_blocks(source).find do |block|
    block.match?(/\b#{Regexp.escape(name)}\s*(?:<[^>]+>)?\s*(?:\(|\{)/)
  end
end

def i_os_simulator_source?(source, declaration_offset)
  active = true
  stack = []

  source[0...declaration_offset].each_line do |line|
    stripped = line.strip
    case stripped
    when /^#if\s+(.+)$/
      condition = simulator_condition(Regexp.last_match(1))
      stack << { parent: active, taken: condition }
      active &&= condition
    when /^#elseif\s+(.+)$/
      next if stack.empty?

      frame = stack.last
      condition = !frame[:taken] && simulator_condition(Regexp.last_match(1))
      frame[:taken] ||= condition
      active = frame[:parent] && condition
    when "#else"
      next if stack.empty?

      frame = stack.last
      condition = !frame[:taken]
      frame[:taken] = true
      active = frame[:parent] && condition
    when "#endif"
      frame = stack.pop
      active = frame ? frame[:parent] : true
    end
  end

  active
end

def simulator_condition(expression)
  value = expression.dup
  replacements = {
    /os\(iOS\)/ => "true",
    /os\(macOS\)/ => "false",
    /os\(tvOS\)/ => "false",
    /os\(visionOS\)/ => "false",
    /os\(watchOS\)/ => "false",
    /targetEnvironment\(simulator\)/ => "true",
    /targetEnvironment\(macCatalyst\)/ => "false",
    /DEBUG/ => "true",
    /WIDGET_EXTENSION/ => "false",
    /canImport\([^\)]+\)/ => "true",
    /available\([^\)]+\)/ => "true"
  }
  replacements.each { |pattern, replacement| value.gsub!(pattern, replacement) }
  value.gsub!(/\btrue\b/, " true ")
  value.gsub!(/\bfalse\b/, " false ")
  return true unless value.match?(/\A[\s!&|()truefals]+\z/)

  tokens = value.scan(/true|false|&&|\|\||!|\(|\)/)
  ruby_expression = tokens.join(" ").gsub("&&", " and ").gsub("||", " or ").gsub("!", " not ")
  !!eval(ruby_expression) # rubocop:disable Security/Eval
rescue SyntaxError
  true
end

def active_imports(source)
  imports = []
  active = true
  stack = []

  source.each_line do |line|
    stripped = line.strip
    case stripped
    when /^#if\s+(.+)$/
      condition = simulator_condition(Regexp.last_match(1))
      stack << { parent: active, taken: condition }
      active &&= condition
    when /^#elseif\s+(.+)$/
      next if stack.empty?

      frame = stack.last
      condition = !frame[:taken] && simulator_condition(Regexp.last_match(1))
      frame[:taken] ||= condition
      active = frame[:parent] && condition
    when "#else"
      next if stack.empty?

      frame = stack.last
      condition = !frame[:taken]
      frame[:taken] = true
      active = frame[:parent] && condition
    when "#endif"
      frame = stack.pop
      active = frame ? frame[:parent] : true
    else
      if active && (match = stripped.match(/^(?:@preconcurrency\s+)?import\s+([A-Za-z_]\w*)$/))
        imports << match[1]
      end
    end
  end

  imports
end

def role_play_preview_body(body)
  body = body.lines.reject do |line|
    line.match?(/^\s*let\s+appModel\s*=\s*AppModel(?:\(\)|\.preview(?:WithoutDatabase)?)\s*$/)
  end.join
  body.gsub!(/\bAppModel\.previewWithoutDatabase\b|\bAppModel\.preview\b|\bAppModel\(\)/, "appModel")
  body.gsub!(/\bappModel:\s*\.preview\b/, "appModel: appModel")
  body.gsub!(/\bstore:\s*\.preview\b/, "store: appModel")
  body
end

def generated_test(module_name, cases, imports)
  extra_imports = (imports - [module_name, "Foundation", "SwiftData", "SwiftUI", "Testing"]).uniq.sort
  import_lines = extra_imports.map { |name| "import #{name}" }.join("\n")
  import_lines << "\n" unless import_lines.empty?
  suite_name = "#{module_name}GeneratedPreviewSnapshotTests"
  mock_root_modifier = case module_name
                       when "GameRPG"
                         "MockRootViewModifier(root: .previewFixture())"
                       when "MapRPG", "PdfRPG", "PhotoRPG", "SpaceRPG", "TableRPG", "WeatherRPG"
                         "MockRootViewModifier(modelContext: container.mainContext)"
                       else
                         "MockRootViewModifier()"
                       end

  tests = cases.map do |entry|
    method_name = "snapshot#{entry[:name]}"
    preview_body = module_name == "RolePlayGameKit" ? role_play_preview_body(entry[:body]) : entry[:body]
    body = preview_body.lines.map { |line| "            #{line.rstrip}" }.join("\n")
    closure = module_name == "RolePlayGameKit" ? "{ appModel in" : "{"
    <<~SWIFT.rstrip
        // snapshot-root: #{module_name}::#{entry[:name]}
        @Test("#{entry[:name]}")
        func #{method_name}() async throws {
            try await assertPreviewSnapshot("#{entry[:name]}") #{closure}
    #{body}
            }
        }
    SWIFT
  end.join("\n\n")

  fixture_support = if module_name == "RolePlayGameKit"
                      <<~SWIFT
                          private func assertPreviewSnapshot<Content: View>(
                              _ name: String,
                              @ViewBuilder content: (AppModel) -> Content
                          ) async throws {
                              let appModel = #{suite_name}FixtureCache.appModel(named: name)
                              assertRepositorySnapshot(
                                  of: content(appModel)
                                      .environmentSetUp(appModel)
                                      .environment(AppFocusModel())
                                      .environment(SearchBarVisibleModel())
                                      .cloudKitAccountChecksEnabled(false)
                                      .itemStateRestorationEnabled(false)
                                      .rolePlayDatabaseInitializationEnabled(false)
                                      .meshAnimationEnabled(false)
                                      .deterministicSnapshotEnvironment()
                                      .transaction { transaction in
                                          transaction.animation = nil
                                          transaction.disablesAnimations = true
                                      }
                                      .frame(maxWidth: .infinity, maxHeight: .infinity)
                                      .background(.background),
                                  as: .image(
                                      precision: 0.98,
                                      perceptualPrecision: 0.98,
                                      layout: .fixed(width: 390, height: 844)
                                  ),
                                  named: name
                              )
                          }

                      @MainActor
                      private enum #{suite_name}FixtureCache {
                          private static var appModels: [String: AppModel] = [:]

                          static func appModel(named name: String) -> AppModel {
                              if let appModel = appModels[name] {
                                  return appModel
                              }
                              let appModel = AppModel.previewWithoutDatabase
                              appModels[name] = appModel
                              return appModel
                          }
                      }
                      SWIFT
                    elsif module_name == "CoreRPG"
                      <<~SWIFT
                          private func assertPreviewSnapshot<Content: View>(
                              _ name: String,
                              @ViewBuilder content: () -> Content
                          ) async throws {
                              let appGameStateModel = AppGameStateModel()
                              assertRepositorySnapshot(
                                  of: content()
                                      .environment(appGameStateModel)
                                      .environment(AppNavigationModel(appGameStateModel: appGameStateModel))
                                      .environment(AppSettingsModel.previewFixture())
                                      .environment(AppWindowSizeModel())
                                      .environment(AppFocusModel())
                                      .environment(SearchBarVisibleModel())
                                      .environment(ScenesManager())
                                      .environment(OptionKeyDownModel())
                                      .environment(GroupItemSelectionModel())
                                      .environment(ItemRootController.previewFixture())
                                      .cloudKitAccountChecksEnabled(false)
                                      .itemStateRestorationEnabled(false)
                                      .meshAnimationEnabled(false)
                                      .deterministicSnapshotEnvironment()
                                      .transaction { transaction in
                                          transaction.animation = nil
                                          transaction.disablesAnimations = true
                                      }
                                      .frame(maxWidth: .infinity, maxHeight: .infinity)
                                      .background(.background),
                                  as: .image(
                                      precision: 0.98,
                                      perceptualPrecision: 0.98,
                                      layout: .fixed(width: 390, height: 844)
                                  ),
                                  named: name
                              )
                          }
                      SWIFT
                    elsif module_name == "DiceRPG"
                      <<~SWIFT
                          private func assertPreviewSnapshot<Content: View>(
                              _ name: String,
                              @ViewBuilder content: () -> Content
                          ) async throws {
                              let root = DiceRootModel.previewFixture()
                              let container = try await #{suite_name}FixtureCache.modelContainer()
                              assertRepositorySnapshot(
                                  of: content()
                                      .modifier(MockRootViewModifier(root: root))
                                      .environment(AppFocusModel())
                                      .environment(SearchBarVisibleModel())
                                      .modelContainer(container)
                                      .deterministicSnapshotEnvironment()
                                      .transaction { transaction in
                                          transaction.animation = nil
                                          transaction.disablesAnimations = true
                                      }
                                      .frame(maxWidth: .infinity, maxHeight: .infinity)
                                      .background(.background),
                                  as: .image(
                                      perceptualPrecision: 0.98,
                                      layout: .fixed(width: 390, height: 844)
                                  ),
                                  named: name
                              )
                          }

                      @MainActor
                      private enum #{suite_name}FixtureCache {
                          private static var cachedContainer: ModelContainer?

                          static func modelContainer() async throws -> ModelContainer {
                              if let cachedContainer {
                                  return cachedContainer
                              }
                              let container = try await MockData.makeSharedContext()
                              cachedContainer = container
                              return container
                          }
                      }
                      SWIFT
                    elsif module_name == "PhotoRPG"
                      <<~SWIFT
                          private func assertPreviewSnapshot<Content: View>(
                              _ name: String,
                              @ViewBuilder content: () -> Content
                          ) async throws {
                              let root = PhotoRootModel.previewFixture()
                              let container = try await #{suite_name}FixtureCache.modelContainer()
                              assertRepositorySnapshot(
                                  of: content()
                                      .modifier(MockRootViewModifier(modelContext: container.mainContext, root: root))
                                      .environment(AppFocusModel())
                                      .environment(SearchBarVisibleModel())
                                      .modelContainer(container)
                                      .deterministicSnapshotEnvironment()
                                      .transaction { transaction in
                                          transaction.animation = nil
                                          transaction.disablesAnimations = true
                                      }
                                      .frame(maxWidth: .infinity, maxHeight: .infinity)
                                      .background(.background),
                                  as: .image(
                                      perceptualPrecision: 0.98,
                                      layout: .fixed(width: 390, height: 844)
                                  ),
                                  named: name
                              )
                          }

                      @MainActor
                      private enum #{suite_name}FixtureCache {
                          private static var cachedContainer: ModelContainer?

                          static func modelContainer() async throws -> ModelContainer {
                              if let cachedContainer {
                                  return cachedContainer
                              }
                              let container = try await MockData.makeSharedContext()
                              cachedContainer = container
                              return container
                          }
                      }
                      SWIFT
                    else
                      <<~SWIFT
                          private func assertPreviewSnapshot<Content: View>(
                              _ name: String,
                              @ViewBuilder content: () -> Content
                          ) async throws {
                              let container = try await #{suite_name}FixtureCache.modelContainer()
                              assertRepositorySnapshot(
                                  of: content()
                                      .modifier(#{mock_root_modifier})
                                      .environment(AppFocusModel())
                                      .environment(SearchBarVisibleModel())
                                      .modelContainer(container)
                                      .deterministicSnapshotEnvironment()
                                      .transaction { transaction in
                                          transaction.animation = nil
                                          transaction.disablesAnimations = true
                                      }
                                      .frame(maxWidth: .infinity, maxHeight: .infinity)
                                      .background(.background),
                                  as: .image(
                                      perceptualPrecision: 0.98,
                                      layout: .fixed(width: 390, height: 844)
                                  ),
                                  named: name
                              )
                          }
                      }

                      @MainActor
                      private enum #{suite_name}FixtureCache {
                          private static var cachedContainer: ModelContainer?

                          static func modelContainer() async throws -> ModelContainer {
                              if let cachedContainer {
                                  return cachedContainer
                              }
                              let container = try await MockData.makeSharedContext()
                              cachedContainer = container
                              return container
                          }
                      SWIFT
                    end

  <<~SWIFT
    // Generated by Scripts/generate_snapshot_tests.rb. Do not edit by hand.

    import Foundation
    import SnapshotTesting
    import SwiftData
    import SwiftUI
    import Testing
    #{import_lines}@testable import #{module_name}

    @MainActor
    @Suite(.serialized, .snapshots, .tags(.snapshot))
    struct #{suite_name} {
    #{tests}

    #{fixture_support.rstrip}
    }
  SWIFT
end

requested_modules = ARGV.uniq
unknown_modules = requested_modules - MODULES.keys
abort "Unknown snapshot module(s): #{unknown_modules.join(', ')}" unless unknown_modules.empty?

modules_to_generate = if requested_modules.empty?
                        MODULES
                      else
                        MODULES.select { |module_name, _test_directory| requested_modules.include?(module_name) }
                      end

report = ["# Generated snapshot-test coverage", ""]

modules_to_generate.each do |module_name, test_directory|
  cases = []
  skips = []
  imports = []

  ROOT.glob("Modules/#{module_name}/**/*.swift").sort.each do |path|
    source = path.read
    declarations = view_declarations(source)
    next if declarations.empty?

    if declarations.length != 1
      skips << "#{path.relative_path_from(ROOT)} — contains #{declarations.length} View declarations"
      next
    end

    name = declarations.first
    declaration_offset = source.index(/struct\s+#{Regexp.escape(name)}\b/) || 0
    unless i_os_simulator_source?(source, declaration_offset)
      skips << "#{path.relative_path_from(ROOT)} — unavailable on an iOS Simulator"
      next
    end

    if source.match?(/^\s*(?:private|fileprivate)\s+struct\s+#{Regexp.escape(name)}\b/m)
      skips << "#{path.relative_path_from(ROOT)} — file-private View is not @testable-accessible"
      next
    end

    preview = direct_preview_for(name, source)
    unless preview
      skips << "#{path.relative_path_from(ROOT)} — no direct #Preview"
      next
    end

    body = preview_body(preview)
    if !body || body.empty?
      skips << "#{path.relative_path_from(ROOT)} — empty #Preview body"
      next
    end

    if body.include?("@Previewable")
      skips << "#{path.relative_path_from(ROOT)} — #Preview uses local dynamic state"
      next
    end

    # A test target can import multiple feature modules that expose identically
    # named views (for example CoreRPG and RolePlayGameKit both define
    # ColorSchemeView). Qualify the directly previewed root while leaving its
    # child-view expressions untouched.
    body = body.sub(/\b#{Regexp.escape(name)}\b/, "#{module_name}.#{name}")

    cases << { name: name, body: body, path: path }
    imports.concat(active_imports(source))
  end

  output = ROOT.join("Tests/#{test_directory}/#{module_name}GeneratedPreviewSnapshotTests.swift")
  output.write(generated_test(module_name, cases, imports))

  report << "## #{module_name}"
  report << ""
  report << "Generated: #{cases.length}; skipped: #{skips.length}."
  report << ""
  skips.each { |skip| report << "- #{skip}" }
  report << ""
end

if requested_modules.empty?
  ROOT.join("Docu/SNAPSHOT_GENERATION_REPORT.md").write(report.join("\n"))
end
puts "Generated snapshot tests for #{modules_to_generate.length} module(s)."
