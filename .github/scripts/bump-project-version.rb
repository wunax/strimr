#!/usr/bin/env ruby
# frozen_string_literal: true

EXPECTED_CONFIGURATION_COUNT = 6
PROJECT_PATH = ARGV.fetch(1, "Strimr.xcodeproj/project.pbxproj")
VERSION_PATTERN = /(?<=MARKETING_VERSION = )[^;\s]+/
BUILD_PATTERN = /(?<=CURRENT_PROJECT_VERSION = )[^;\s]+/

def validated_value(contents, pattern, name, format)
    values = contents.scan(pattern)

    unless values.length == EXPECTED_CONFIGURATION_COUNT
        abort "Expected #{EXPECTED_CONFIGURATION_COUNT} #{name} entries, found #{values.length}."
    end

    unless values.uniq.length == 1
        abort "Expected all #{name} entries to match, found: #{values.uniq.join(', ')}."
    end

    value = values.first
    abort "Invalid #{name}: #{value}." unless value.match?(format)

    value
end

def write_output(name, value)
    puts "#{name}=#{value}"

    output_path = ENV["GITHUB_OUTPUT"]
    return if output_path.nil? || output_path.empty?

    File.open(output_path, "a") { |output| output.puts "#{name}=#{value}" }
end

mode = ARGV.fetch(0) do
    abort "Usage: #{$PROGRAM_NAME} <major|minor|patch|build> [project.pbxproj]"
end

contents = File.read(PROJECT_PATH)
current_version = validated_value(contents, VERSION_PATTERN, "marketing version", /\A\d+\.\d+\.\d+\z/)
current_build = validated_value(contents, BUILD_PATTERN, "build number", /\A\d+\z/)

if mode == "build"
    new_build = (Integer(current_build, 10) + 1).to_s
    contents = contents.gsub(BUILD_PATTERN, new_build)
    write_output("version", current_version)
    write_output("build", new_build)
elsif %w[major minor patch].include?(mode)
    version = current_version.split(".").map { |component| Integer(component, 10) }
    index = { "major" => 0, "minor" => 1, "patch" => 2 }.fetch(mode)
    version[index] += 1
    ((index + 1)..2).each { |component| version[component] = 0 }
    new_version = version.join(".")

    contents = contents.gsub(VERSION_PATTERN, new_version)
    contents = contents.gsub(BUILD_PATTERN, "1")
    write_output("version", new_version)
    write_output("build", "1")
else
    abort "Unsupported bump type: #{mode}. Expected major, minor, patch, or build."
end

File.write(PROJECT_PATH, contents)
