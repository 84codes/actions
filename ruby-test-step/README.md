# Ruby Test Step

A simple composite GitHub Action for running Ruby test commands.

## Features

- ✅ Run any Ruby/Rake command
- ✅ Automatic bundler support
- ✅ Reusable across multiple workflows

## Usage

### Basic Example

```yaml
steps:
  - uses: 84codes/actions/ruby-test-step@main
    with:
      run: bundle exec rake test
```

### Multiple Test Steps in a Job

```yaml
jobs:
  tests:
    runs-on: ubuntu-latest
    steps:
      - uses: 84codes/actions/ruby-ci-setup@main
        with:
          postgres: true
          github-token: ${{ secrets.GITHUB_TOKEN }}

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
| `run` | Command to run (e.g., `bundle exec rake test`) | No | `bundle exec rake test` |

## Example: Complete CI Setup

```yaml
name: CI

on: [push, pull_request]

jobs:
  tests:
    runs-on: ubuntu-latest
    steps:
      - uses: 84codes/actions/ruby-ci-setup@main
        with:
          postgres: true
          github-token: ${{ secrets.GITHUB_TOKEN }}

      - uses: 84codes/actions/ruby-test-step@main
        with:
          run: bundle exec rake test

      - uses: 84codes/actions/ruby-test-step@main
        with:
          run: bundle exec rake test:boot_web
```

## License

MIT
