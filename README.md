# Reusable GitHub Actions for 84codes

Composite actions for common CI/CD tasks at 84codes.

Working at 84codes? _Please note that **`this repository is public!`**_

---

## Available Actions

### Ruby CI Setup (`ruby-ci-setup`)

Sets up everything needed for Ruby CI: PostgreSQL, LavinMQ, and Ruby environment.

```yaml
- uses: 84codes/actions/ruby-ci-setup@main
  with:
    postgres: true
    lavinmq: true
    github-token: ${{ secrets.GITHUB_TOKEN }}
```

[Read more →](./ruby-ci-setup/README.md)

### Ruby Test Step (`ruby-test-step`)

Run Ruby test commands in your workflow.

```yaml
- uses: 84codes/actions/ruby-test-step@main
  with:
    run: bundle exec rake test
```

[Read more →](./ruby-test-step/README.md)

### RuboCop Lint (`rubocop-lint`)

Run RuboCop linting with reviewdog (assumes Ruby is already set up).

```yaml
- uses: 84codes/actions/rubocop-lint@main
  with:
    github-token: ${{ secrets.GITHUB_TOKEN }}
```

[Read more →](./rubocop-lint/README.md)

---

## Example: Complete Ruby CI Workflow

```yaml
name: CI

on: [push, pull_request]

jobs:
  tests:
    runs-on: ubuntu-latest
    steps:
      # Setup Ruby environment with PostgreSQL
      - uses: 84codes/actions/ruby-ci-setup@main
        with:
          postgres: true
          github-token: ${{ secrets.GITHUB_TOKEN }}

      # Run tests
      - uses: 84codes/actions/ruby-test-step@main
        with:
          run: bundle exec rake test

      # Run linting
      - uses: 84codes/actions/rubocop-lint@main
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
```
