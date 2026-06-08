# RuboCop Lint

A lightweight composite action for running RuboCop. Use this when Ruby is already set up in your workflow.

## Usage

This action assumes Ruby and dependencies are already installed. Perfect for adding linting to an existing job:

```yaml
jobs:
  ci:
    runs-on: ubuntu-latest
    steps:
      # Setup Ruby (via ruby-ci-setup or manually)
      - uses: 84codes/actions/ruby-ci-setup@main
        with:
          postgres: true

      # Run your tests
      - run: bundle exec rake test

      # Add linting
      - uses: 84codes/actions/rubocop-lint@main
```

## Inputs

None. RuboCop reads its configuration from your project's `.rubocop.yml`.

Offenses are reported as inline GitHub annotations via RuboCop's built-in `github` formatter, so no token or third-party action is required.

## When to Use

**Use `rubocop-lint`** when:
- ✅ Ruby is already set up in your job
- ✅ You want to add linting to an existing test job
- ✅ You want minimal overhead

## Example: Combined Tests and Lint

```yaml
jobs:
  ci:
    runs-on: ubuntu-latest
    steps:
      - uses: 84codes/actions/ruby-ci-setup@main
        with:
          postgres: true
          github-token: ${{ secrets.GITHUB_TOKEN }}

      - uses: 84codes/actions/ruby-test-step@main
        with:
          run: bundle exec rake test

      - uses: 84codes/actions/rubocop-lint@main
```

## Benefits

- ✅ Reuses existing Ruby setup
- ✅ No duplicate checkout or installation
- ✅ Simple configuration
- ✅ Consistent linting across projects
