# frozen_string_literal: true

require_relative 'lib/stampmitra/version'

Gem::Specification.new do |spec|
  spec.name = 'stampmitra'
  spec.version = StampMitra::VERSION
  spec.authors = ['StampMitra / Bani Global Industries LLP']

  spec.summary = 'Official Ruby client for the StampMitra Developer API (identity verification and e-Stamp Paper).'
  spec.description = 'Typed, retry-safe client for the StampMitra Developer API: PAN, GSTIN, vehicle RC, Voter ID, driving licence, ' \
                     'passport, CIN, Udyam and bank account verification, e-Stamp Paper, orders, payments, usage logs and ' \
                     'webhook signature verification. Standard library only, no runtime dependencies.'
  spec.homepage = 'https://developer.stampmitra.in/sdks/ruby'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.0'

  spec.metadata = {
    'homepage_uri' => spec.homepage,
    'source_code_uri' => 'https://github.com/Bani-Global-Industries-LLP/stampmitra-developer-ruby',
    'changelog_uri' => 'https://github.com/Bani-Global-Industries-LLP/stampmitra-developer-ruby/blob/main/CHANGELOG.md',
    'bug_tracker_uri' => 'https://github.com/Bani-Global-Industries-LLP/stampmitra-developer-ruby/issues',
    'documentation_uri' => 'https://developer.stampmitra.in/docs',
    'rubygems_mfa_required' => 'true'
  }

  # Explicit whitelist: no tests, specs, fixtures, scripts or CI files in the published gem.
  spec.files = Dir['lib/**/*.rb', 'LICENSE', 'README.md', 'CHANGELOG.md', 'SECURITY.md']
  spec.require_paths = ['lib']
end
