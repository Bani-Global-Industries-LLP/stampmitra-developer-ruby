# frozen_string_literal: true

require 'bundler/gem_tasks' # build, install, release (release is run by CI only, see RELEASING.md)
require 'rake/testtask'

Rake::TestTask.new(:test) do |t|
  t.libs << 'test' << 'lib'
  t.pattern = 'test/unit/**/*_test.rb'
  t.warning = true
end

namespace :test do
  desc 'Black-box conformance run against the spec repo mock server (needs MOCK_SERVER_URL, see CONTRIBUTING.md)'
  Rake::TestTask.new(:conformance) do |t|
    t.libs << 'test' << 'lib'
    t.pattern = 'test/conformance/**/*_test.rb'
    t.warning = true
  end
end

begin
  require 'rubocop/rake_task'
  RuboCop::RakeTask.new(:rubocop)
rescue LoadError
  desc 'RuboCop is not installed (bundle install --with lint)'
  task(:rubocop) { abort 'rubocop is not installed: run `bundle install` without BUNDLE_WITHOUT=lint' }
end

desc 'Fail when an operation in spec/openapi.json has no SDK method'
task :coverage do
  ruby 'scripts/check-spec-coverage'
end

desc 'Fail when lib/stampmitra/models.rb is stale relative to spec/openapi.json'
task :models do
  ruby 'scripts/generate-models', '--check'
end

desc 'Compile and run every Ruby block in README.md'
task :readme do
  ruby 'scripts/check-readme-snippets'
end

task default: %i[test rubocop coverage models]
