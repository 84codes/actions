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

### Site Preview Deploy (`site-preview`)

Deploy a built static site to an S3-backed CloudFront preview at `https://pr-<N>.<domain>`. Used by the lavinmq, cloudamqp, and 84codes website repos.

```yaml
- uses: 84codes/actions/site-preview@main
  with:
    pr-number: ${{ github.event.pull_request.number }}
    commit-sha: ${{ github.event.pull_request.head.sha }}
    domain: example.dev
    cloudfront-distribution-id: EXAMPLEDIST12345
    csp-policy-name: example-preview-csp-policy
    github-token: ${{ secrets.GITHUB_TOKEN }}
```

[Read more →](./site-preview/README.md)

### Site Preview Cleanup (`site-preview/cleanup`)

Tear down a PR preview: delete the S3 bucket, deactivate the GitHub deployment, comment on the PR.

```yaml
- uses: 84codes/actions/site-preview/cleanup@main
  with:
    pr-number: ${{ github.event.pull_request.number }}
    domain: example.dev
    github-token: ${{ secrets.GITHUB_TOKEN }}
```

[Read more →](./site-preview/cleanup/README.md)

### Site Preview Prune Orphaned (`site-preview/prune-orphaned`)

Periodic safety net: delete preview buckets older than the cutoff so closed-without-cleanup previews don't accumulate.

```yaml
- uses: 84codes/actions/site-preview/prune-orphaned@main
  with:
    domain: example.dev
```

[Read more →](./site-preview/prune-orphaned/README.md)

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
