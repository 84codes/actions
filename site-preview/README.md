# site-preview

Deploy a built static site to an S3-backed CloudFront preview at `https://pr-<N>.<domain>`. Used by the lavinmq, cloudamqp, and 84codes website repos so the preview pipeline stays in one place.

Assumes AWS credentials are already configured (via `aws-actions/configure-aws-credentials`) and that `<site-dir>` (default `_site`) contains the built site.

## What it does

1. Ensures the per-PR S3 bucket exists (creates it with public-read, website-config, `VantaNonProd` tag, and a 30-day lifecycle rule on first run).
2. Hashes built files and reads the previous deployment manifest and current S3 object listing.
3. Uploads changed, missing, or aging files and redirects through one shared Ruby AWS SDK client, with up to eight workers and retries for transient failures. Redirects take precedence over built files with the same key and return a 301 from the S3 website endpoint.
4. Removes obsolete objects and saves the deployment manifest.
5. Detects whether `csp-policy.json` differs from the PR's base branch by comparing the file contents, which works for PRs of any size. If it does, attaches the named CloudFront response-headers policy to the preview distribution (creating it if missing).
6. Invalidates the preview distribution.
7. Posts (or updates) a comment on the PR with the preview URL.

With `upload-command`, the caller's command replaces steps 2–4 and 6; see [Upload command](#upload-command).

### Incremental uploads

The first deployment uploads all files and redirects. Later deployments compare file SHA256 hashes and redirect targets against `_site-preview/manifest.json` in the bucket. Fresh build timestamps do not trigger uploads. Objects must also exist in S3 with their recorded ETag to be skipped.

Objects last uploaded at least 20 days ago are refreshed on the next deployment, before the bucket's 30-day expiration rule can remove them. Inactive previews still expire. Missing objects are always restored.

Before uploading changes, the action checkpoints a manifest containing only unchanged objects. It records uploaded objects after all uploads and deletions succeed. Failed deployments therefore retry affected keys, including metadata changes with identical object bytes. S3 updates are not atomic; callers must serialize deployments to the same preview bucket using workflow `concurrency`.

The built directory must contain `index.html`, regular files, and no symlinks. `_site-preview/manifest.json` is reserved and cannot appear in the build or redirects. A missing redirects file or empty mapping means no redirects; previously deployed redirects are removed unless replaced by a built file.

### Upload command

A site that deploys to production with its own uploader can pass it as `upload-command`, so previews exercise the same cache headers, upload order and invalidation before production does. Once the bucket exists, the action runs the command with bash in the caller's workspace, using the caller's tools rather than the action's gems, with these environment variables:

| Variable | Value |
| --- | --- |
| `BUCKET` | `pr-<N>.<domain>` |
| `SITE_DIR` | `site-dir` input |
| `REDIRECTS_FILE` | `redirects-file` input |
| `DISTRIBUTION_ID` | `cloudfront-distribution-id` input |

Reference them as shell variables, for example `upload-command: bundle exec ruby exe/deploy-site "$BUCKET" "$DISTRIBUTION_ID"`.

The command must upload the site and redirects, delete obsolete objects and invalidate the paths it changed. The action does not invalidate anything after it, so stale content shows up in the preview as it would in production. The bucket expires every object 30 days after it was written, so the command must also re-upload unchanged objects before then, or open previews lose them. A failed command fails the deployment before the CSP update and the PR comment. The CSP update needs no invalidation: CloudFront adds response headers policy headers to cached responses too.

Existing preview buckets keep the built-in uploader's `_site-preview/manifest.json`, which the command may delete as obsolete. Without it, the built-in uploader treats its next deployment as the first one.

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
| `upload-command` | no | Command that uploads and invalidates instead of the built-in uploader; see [Upload command](#upload-command). Empty (default) uses the built-in uploader. |

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

Minitest exercises SDK request arguments, content changes, unchanged builds, lifecycle refreshes, deletions, concurrency, and recovery from failed deployments without making AWS requests. The CSP change check runs against a stubbed `gh`. Tests and Ruby linting also run in CI.

## Related actions

- [`site-preview/cleanup`](./cleanup) — tear down a preview when its PR closes (delete bucket, delete GitHub environment, comment on the PR).
- [`site-preview/prune-orphaned`](./prune-orphaned) — scheduled safety net for previews that escaped normal cleanup.
