# Reusable workflows for GitHub Actions

See the docs at https://docs.github.com/en/actions/learn-github-actions/reusing-workflows

Working at 84codes? _Please note that **`this repository is public!`**_

---

## Example workflows

#### Ruby CI

```yaml
name: CI

on:
  push:
  pull_request:
  workflow_dispatch:

jobs:
  test:
    uses: 84codes/actions/.github/workflows/ruby-ci.yml@main
    secrets:
      github-token: ${{ secrets.ORG_GITHUB_TOKEN_FOR_CI }}
      pkg-github-com: ${{ secrets.PACKAGES_PAT }}
```

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
      heroku-key: ${{ secrets.HEROKU_API_KEY }}
```
