# Releasing

Releases are cut by pushing a `vX.Y.Z` tag. The `Release` workflow always builds and tests the tag, and publishes to RubyGems
**only** when the repository variable `RUBYGEMS_PUBLISH` is `true`. Publishing uses
[RubyGems trusted publishing](https://guides.rubygems.org/trusted-publishing/) (OIDC): **no RubyGems API key or token is stored in
this repository, its secrets or the workflow.** Until the one-time setup below is done the workflow is inert apart from running tests.

## One-time setup (maintainer)

1. **Register a trusted publisher on rubygems.org.** The gem name `stampmitra` is not published yet, so use a *pending* trusted
   publisher (rubygems.org > your profile > *Trusted publishers* > *Pending trusted publishers*; verify the exact menu in the
   registry UI, as RubyGems evolves it). Enter:
   - gem name: `stampmitra`
   - repository owner: `Bani-Global-Industries-LLP`, repository name: `stampmitra-developer-ruby`
   - workflow filename: `release.yml`
   - environment: `rubygems` (the name used by the `publish` job; it is optional on RubyGems' side, but if you set it, it must match)

   A pending publisher reserves the right to publish the *first* release only after it is used; once the gem exists, manage the
   publisher from the gem's own page (*Trusted publishers*). If pending publishers are unavailable for your account, publish
   0.1.0 once by hand with a short-lived API key (MFA required) and then add the trusted publisher.
2. **Require MFA** on the RubyGems accounts of all owners (the gemspec sets `rubygems_mfa_required`; trusted publishing is exempt).
3. **GitHub:** create the `rubygems` environment (Settings > Environments), optionally with required reviewers so a human approves
   every publish, then set the repository variable `RUBYGEMS_PUBLISH` to `true` (Settings > Secrets and variables > Actions >
   Variables). Optionally protect the `v*` tag pattern (Settings > Rules).

## Per release

1. Move the *Unreleased* notes into a dated section in `CHANGELOG.md`.
2. Bump `StampMitra::VERSION` in `lib/stampmitra/version.rb` (the workflow fails if it does not match the tag).
3. Run `bundle exec rake`, `bundle exec yard stats --list-undoc` and (with the spec repo checked out) the conformance suite locally.
4. `git tag v0.1.0 && git push origin v0.1.0`.
5. The workflow verifies the tag, then (if `RUBYGEMS_PUBLISH=true`) `rubygems/release-gem@v1` builds the gem and pushes it with
   an OIDC-issued credential, with sigstore attestations, and the job creates the GitHub release.

Never run `rake release` from a laptop: it would need a long-lived RubyGems credential. `rake build` and `rake install:local` are fine.
A published version can only be yanked (`gem yank`), never replaced, so double-check before tagging.
