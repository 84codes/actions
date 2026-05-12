# site-preview/cleanup

Tear down a PR preview created by [`site-preview`](..). Deletes the per-PR S3 bucket, deletes the matching GitHub deployment environment, and comments on the PR.

Idempotent: safe to re-run, and the bucket-not-found / env-not-found cases are treated as success.

Assumes AWS credentials are already configured.

## Token requirement

`DELETE /repos/{owner}/{repo}/environments/{name}` requires **`administration: write`** scope on the repository. The default `GITHUB_TOKEN` does NOT have that scope — calls return HTTP 403, no matter what `permissions:` you set in the workflow.

Pass a PAT or GitHub App token (e.g. `secrets.ORG_GITHUB_TOKEN_FOR_CI`) as `github-token` instead. The action surfaces non-404 errors so misconfigured tokens fail loudly rather than silently letting environments pile up.

## Inputs

| Name | Required | Description |
| --- | --- | --- |
| `pr-number` | yes | PR number whose preview should be torn down |
| `domain` | yes | Domain suffix; the bucket `pr-<pr-number>.<domain>` is deleted |
| `github-token` | yes | Token with `administration: write` and `pull-requests: write`. Default `GITHUB_TOKEN` does NOT work. |

## Outputs

| Name | Description |
| --- | --- |
| `status` | `deleted`, `not_found`, or `failed` |

## Usage

```yaml
jobs:
  cleanup-preview:
    if: github.event_name == 'pull_request'
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read
    steps:
      - uses: aws-actions/configure-aws-credentials@v6
        with:
          role-to-assume: arn:aws:iam::<acct>:role/<role>
          aws-region: us-east-1

      - uses: 84codes/actions/site-preview/cleanup@main
        with:
          pr-number: ${{ github.event.pull_request.number }}
          domain: example.dev
          github-token: ${{ secrets.ORG_GITHUB_TOKEN_FOR_CI }}
```
