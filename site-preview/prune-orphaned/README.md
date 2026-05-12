# site-preview/prune-orphaned

Periodic safety net: delete S3 buckets matching `pr-*.<domain>` whose `CreationDate` is older than `max-age-days` (default 30). The per-bucket lifecycle rule from [`site-preview`](..) empties old buckets after 30 days, but the bucket itself isn't deleted by lifecycle — this action handles that.

Assumes AWS credentials are already configured.

## Inputs

| Name | Required | Description |
| --- | --- | --- |
| `domain` | yes | Domain suffix, e.g. `lavinmq.dev`. Only `pr-*.<domain>` buckets are touched. |
| `max-age-days` | no | Cutoff in days (default `30`) |

## Usage

```yaml
on:
  schedule:
    - cron: '0 3 * * 0'  # weekly Sunday 03:00 UTC

jobs:
  prune:
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read
    steps:
      - uses: aws-actions/configure-aws-credentials@v6
        with:
          role-to-assume: arn:aws:iam::<acct>:role/<role>
          aws-region: us-east-1

      - uses: 84codes/actions/site-preview/prune-orphaned@main
        with:
          domain: example.dev
```
