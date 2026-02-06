# PR Title Rules

PR Titles become the commit message upon merge and the commit message(s) become
the release notes upon publish. These release notes will be visible in GitHub,
but also on CurseForge, WoWInterface, and Wago.

To ensure that the release notes are clear and informative, PR titles must
follow the format:

`type: description`

The `description` should be brief, only one line, and begin with a lowercase letter.

Here are examples of valid PR titles using various `type`s:

- locale: update enUS translations
- feat: adds endeavor support
- fix: lua error when opening config
- revert: config changes were causing performance issues
- docs: update readme to align with new release process
- refactor: reorganized config code to be more modular
- build: updated build scripts to support new release process
- test: added unit tests for item parsing
- ci: new release process workflows
- chore: tweaked dependabot config
- style: formatted code with stylua
- perf: improve performance of item parsing
