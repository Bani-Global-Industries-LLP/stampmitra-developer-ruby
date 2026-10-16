# Contributing

Thanks for helping improve the StampMitra Ruby SDK.

## Setup

```bash
bundle install
bundle exec rake                   # unit tests + RuboCop + spec coverage + generated-model check
bundle exec yard stats --list-undoc  # public API must stay 100% documented
ruby scripts/check-readme-snippets   # compiles and RUNS every code block in README.md
```

No `Gemfile.lock` is committed: this is a library and CI should keep testing against the newest tooling that satisfies the
`Gemfile` (the tools that gate CI are pinned to exact versions; Dependabot bumps them).

## Conformance suite

`test/conformance` is a black-box run (all 31 operations, every documented error fixture, error mapping, retries, idempotency,
timeouts, dropped connections, pagination, shared vectors) against the spec repository's mock server. It needs Node.js and a checkout
of the spec repository, whose **default branch (`main`) must exist**:

```bash
git clone https://github.com/Bani-Global-Industries-LLP/stampmitra-developer-openapi ../stampmitra-developer-openapi
STAMPMITRA_SPEC_DIR=../stampmitra-developer-openapi CONFORMANCE_REQUIRED=1 bundle exec rake test:conformance
# or start the mock yourself: node ../stampmitra-developer-openapi/scripts/mock-server.mjs --port 4010 & MOCK_SERVER_URL=http://127.0.0.1:4010 ...
```

Without a mock server the suite is skipped locally; `CONFORMANCE_REQUIRED=1` (set in CI) makes that a failure. CI checks the spec repository
out into `.openapi` and sets `STAMPMITRA_SPEC_DIR` itself. The default is the sibling directory `../stampmitra-developer-openapi`.
`scripts/run-examples` (examples against the mock, plus the Sinatra and Rack receivers as real servers) needs
`bundle install --gemfile examples/Gemfile`.

`test/fixtures/*.json` are copies of the shared fixtures in the spec repository: refresh them when it changes.

## Keeping the SDK in sync with the API

- `spec/openapi.json` is a snapshot of the public spec. When the API changes, refresh it, run `ruby scripts/generate-models` (rewrites
  `lib/stampmitra/models.rb`) and add the new resource methods; `rake coverage` fails until every `METHOD + path` has an SDK method.
- Keep Ruby 3.0 compatibility: no `Data.define`, no hash-shorthand `f(x:)`, no `it`, no anonymous block/rest forwarding (RuboCop's `TargetRubyVersion: 3.0` rejects 3.1+ syntax).

## Guidelines

- Every public method and class needs YARD documentation.
- Tests never use the network except through the loopback mock; never log or commit real keys or personal data.
- Update `CHANGELOG.md` under *Unreleased*.
- By contributing you agree your work is licensed under the MIT license.

Security issues: see [SECURITY.md](SECURITY.md), do not open a public issue.
