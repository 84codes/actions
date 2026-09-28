# site-preview

Deploy a built static site to an S3-backed CloudFront preview at `https://pr-<N>.<domain>`. Used by the lavinmq, cloudamqp, and 84codes website repos so the preview pipeline stays in one place.

Assumes AWS credentials are already configured (via `aws-actions/configure-aws-credentials`) and that `<site-dir>` (default `_site`) contains the built site.

## What it does

1. Ensures the per-PR S3 bucket exists (creates it with public-read, website-config, `VantaNonProd` tag, and a 30-day lifecycle rule on first run).
2. Hashes built files and reads the previous deployment manifest and current S3 object listing.
3. Uploads changed, missing, or aging files and redirects through one shared Ruby AWS SDK client, with up to eight workers and retries for transient failures. Redirects take precedence over built files with the same key and return a 301 from the S3 website endpoint.
4. Removes obsolete objects and saves the deployment manifest.
5. Detects whether `csp-policy.json` changed in the PR (via `gh pr view --json files`). If it did, attaches the named CloudFront response-headers policy to the preview distribution (creating it if missing).
6. Invalidates the preview distribution.
7. Posts (or updates) a comment on the PR with the preview URL.

### Incremental uploads

The first deployment uploads all files and redirects. Later deployments compare file SHA256 hashes and redirect targets against `_site-preview/manifest.json` in the bucket. Fresh build timestamps do not trigger uploads. Objects must also exist in S3 with their recorded ETag to be skipped.

Objects last uploaded at least 20 days ago are refreshed on the next deployment, before the bucket's 30-day expiration rule can remove them. Inactive previews still expire. Missing objects are always restored.

Before uploading changes, the action checkpoints a manifest containing only unchanged objects. It records uploaded objects after all uploads and deletions succeed. Failed deployments therefore retry affected keys, including metadata changes with identical object bytes. S3 updates are not atomic; callers must serialize deployments to the same preview bucket using workflow `concurrency`.

The built directory must contain `index.html`, regular files, and no symlinks. `_site-preview/manifest.json` is reserved and cannot appear in the build or redirects. A missing redirects file or empty mapping means no redirects; previously deployed redirects are removed unless replaced by a built file.

## Inputs

| Name | Required | Description |
| --- | --- | --- |
| `pr-number` | yes | Used to derive `pr-<N>.<domain>` |
| `commit-sha` | yes | Shown in the PR comment |
| `domain` | yes | Domain suffix, e.g. `lavinmq.dev` |
| `cloudfront-distribution-id` | yes | Preview distribution to invalidate and attach CSP to |
| `csp-policy-name` | yes | Response-headers policy name (created if missing) |
| `github-token` | yes | `GITHUB_TOKEN` with `pull-requests: write` |
| `site-dir` | no | Built site directory (default `_site`) |
| `csp-policy-file` | no | Path to CSP JSON in the caller repo (default `csp-policy.json`) |
| `redirects-file` | no | Path to redirects JSON in the caller repo (default `redirects.json`). Missing file means no redirects. |
| `comment-marker` | no | Substring used to find/update existing preview comment (default `Preview deployment`) |

## Usage

```yaml
jobs:
  deploy-preview:
    runs-on: ubuntu-latest
    environment:
      name: pr-${{ github.event.pull_request.number }}
      url: https://pr-${{ github.event.pull_request.number }}.example.dev
    permissions:
      id-token: write
      contents: read
      pull-requests: write
      deployments: write
    steps:
      - uses: actions/checkout@v7
        with:
          persist-credentials: false

      # ... build steps that produce _site/ ...

      - uses: aws-actions/configure-aws-credentials@v6
        with:
          role-to-assume: arn:aws:iam::<acct>:role/<role>
          aws-region: us-east-1

      - uses: 84codes/actions/site-preview@main
        with:
          pr-number: ${{ github.event.pull_request.number }}
          commit-sha: ${{ github.event.pull_request.head.sha }}
          domain: example.dev
          cloudfront-distribution-id: EXAMPLEDIST12345
          csp-policy-name: example-preview-csp-policy
          github-token: ${{ secrets.GITHUB_TOKEN }}
```

The caller workflow handles triggers, permissions, AWS auth, and the site build. This action handles the bits that are identical across the three site repos.

## Tests

From the repository root:

```sh
BUNDLE_GEMFILE=site-preview/Gemfile bundle install
BUNDLE_GEMFILE=site-preview/Gemfile bundle exec ruby -Isite-preview/test -e 'Dir["site-preview/test/**/*_test.rb"].sort.each { |path| require_relative path }'
bundle exec rubocop
```

Minitest exercises SDK request arguments, content changes, unchanged builds, lifecycle refreshes, deletions, concurrency, and recovery from failed deployments without making AWS requests. Tests and Ruby linting also run in CI.

## Related actions

- [`site-preview/cleanup`](./cleanup) — tear down a preview when its PR closes (delete bucket, delete GitHub environment, comment on the PR).
- [`site-preview/prune-orphaned`](./prune-orphaned) — scheduled safety net for previews that escaped normal cleanup.
