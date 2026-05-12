# site-preview

Deploy a built static site to an S3-backed CloudFront preview at `https://pr-<N>.<domain>`. Used by the lavinmq, cloudamqp, and 84codes website repos so the preview pipeline stays in one place.

Assumes AWS credentials are already configured (via `aws-actions/configure-aws-credentials`) and that `<site-dir>` (default `_site`) contains the built site.

## What it does

1. Ensures the per-PR S3 bucket exists (creates it with public-read, website-config, `VantaNonProd` tag, and a 30-day lifecycle rule on first run).
2. `aws s3 sync`s `<site-dir>` into the bucket.
3. Detects whether `csp-policy.json` changed in the PR (via `gh pr view --json files`). If it did, attaches the named CloudFront response-headers policy to the preview distribution (creating it if missing).
4. Invalidates the preview distribution.
5. Posts (or updates) a comment on the PR with the preview URL.

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
      - uses: actions/checkout@v6
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

## Related actions

- [`site-preview/cleanup`](./cleanup) — tear down a preview when its PR closes (delete bucket, delete GitHub environment, comment on the PR).
- [`site-preview/prune-orphaned`](./prune-orphaned) — scheduled safety net for previews that escaped normal cleanup.
