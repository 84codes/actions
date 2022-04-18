# Reusable workflows for GitHub Actions

See the docs at https://docs.github.com/en/actions/learn-github-actions/reusing-workflows

Working at 84codes? _Please note that **`this repository is public!`**_

---

## Example workflows

#### Heroku deploy

```yaml
name: Deploy to Heroku

on:
  workflow_run:
    workflows: [CI]
    types: [completed]

jobs:
  heroku:
    uses: 84codes/actions/.github/workflows/heroku.yml@main
    secrets:
      heroku-key: ${{ secrets.HEROKU_TOKEN }}
```
