# frozen_string_literal: true

source 'https://rubygems.org'

# The gem has no runtime dependencies (standard library only).
gemspec

# Development tooling. Gemfile.lock is deliberately NOT committed: this is a library, and CI should keep testing against
# the newest versions that satisfy these requirements. The tools that gate CI (RuboCop, YARD, bundler-audit) are pinned to
# exact versions so a new release cannot turn CI red on its own; Dependabot proposes the bumps weekly, grouped, and major
# versions of dev tooling are ignored (see .github/dependabot.yml). CI jobs install only the groups they need
# (BUNDLE_WITHOUT), so the test matrix never has to resolve the lint/docs/audit tools on old Rubies.
group :test do
  gem 'logger' # bundled gem since Ruby 3.5 (the tests build Logger instances; the library itself never requires it)
  gem 'minitest', '~> 6.0'
  gem 'rake', '~> 13.0'
end

group :lint do
  gem 'rubocop', '1.92.0'
  gem 'rubocop-minitest', '0.41.0'
  gem 'rubocop-rake', '0.7.1'
end

group :docs do
  gem 'yard', '0.9.45'
end

group :audit do
  gem 'bundler-audit', '0.9.3'
end
