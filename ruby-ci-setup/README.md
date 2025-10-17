# Ruby CI Setup

A composite GitHub Action that sets up everything needed for Ruby CI: PostgreSQL, LavinMQ, and Ruby environment.

## Features

- ✅ Optional PostgreSQL with extensions (pgcrypto, hstore, uuid-ossp)
- ✅ Optional LavinMQ setup
- ✅ Ruby environment with bundler caching
- ✅ Support for private gem dependencies
- ✅ Reusable across all your Ruby projects

## Usage

### Basic Example (Ruby only)

```yaml
steps:
  - uses: 84codes/actions/ruby-ci-setup@main
    with:
      github-token: ${{ secrets.GITHUB_TOKEN }}
```

### With PostgreSQL

```yaml
steps:
  - uses: 84codes/actions/ruby-ci-setup@main
    with:
      postgres: true
      github-token: ${{ secrets.GITHUB_TOKEN }}
```

### With PostgreSQL + LavinMQ

```yaml
steps:
  - uses: 84codes/actions/ruby-ci-setup@main
    with:
      postgres: true
      lavinmq: true
      github-token: ${{ secrets.GITHUB_TOKEN }}
```

### Complete CI Workflow

Combine with `ruby-test-step` for individual test steps:

```yaml
name: CI

on: [push, pull_request]

jobs:
  tests:
    runs-on: ubuntu-latest
    steps:
      # One-time setup
      - uses: 84codes/actions/ruby-ci-setup@main
        with:
          postgres: true
          lavinmq: true
          github-token: ${{ secrets.GITHUB_TOKEN }}

      # Multiple test steps - each shows separately in UI
      - uses: 84codes/actions/ruby-test-step@main
        with:
          run: bundle exec rake test

      - uses: 84codes/actions/ruby-test-step@main
        with:
          run: bundle exec rake test:boot_web

      - uses: 84codes/actions/ruby-test-step@main
        with:
          run: bundle exec rspec spec/integration
```

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `ruby-version` | Ruby version to use | No | `.ruby-version` |
| `bundler-cache` | Enable bundler caching | No | `true` |
| `cache-version` | Cache version for busting | No | `0` |
| `bundle-frozen` | BUNDLE_FROZEN env var | No | `true` |
| `github-token` | Token for private gems | No | - |
| `pkg-github-com` | Token for pkg.github.com | No | - |
| `pkg-github-com-user` | Username for pkg.github.com | No | `machine-user-84` |
| `postgres` | Start PostgreSQL | No | `false` |
| `lavinmq` | Setup LavinMQ | No | `false` |

## Benefits

### ✅ Reusable Setup

- One action handles all infrastructure setup
- Use across all Ruby projects
- Consistent configuration

### ✅ Combined with `ruby-test-step`

- Setup once, run multiple test steps
- Each test step shows separately in GitHub UI
- Efficient resource usage

### ✅ Flexible

- Enable only what you need
- PostgreSQL + LavinMQ optional
- Works with public and private gems

## Example: Multiple Projects

### Simple API Project

```yaml
- uses: 84codes/actions/ruby-ci-setup@main
  with:
    postgres: true
```

### Complex App with Message Queue

```yaml
- uses: 84codes/actions/ruby-ci-setup@main
  with:
    postgres: true
    lavinmq: true
```

### Library (no database)

```yaml
- uses: 84codes/actions/ruby-ci-setup@main
  with:
    github-token: ${{ secrets.GITHUB_TOKEN }}
```
