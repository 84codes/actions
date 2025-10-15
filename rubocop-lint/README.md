# RuboCop Lint

A lightweight composite action for running RuboCop with reviewdog. Use this when Ruby is already set up in your workflow.

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
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
```

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `github-token` | Token for reviewdog | **Yes** | - |
| `level` | Report level | No | `error` |
| `fail-level` | Fail level | No | `error` |
| `reporter` | Reporter type | No | Auto |

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
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
```

## Benefits

- ✅ Reuses existing Ruby setup
- ✅ No duplicate checkout or installation
- ✅ Simple configuration
- ✅ Consistent linting across projects
