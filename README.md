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
  ci:
    uses: 84codes/actions/.github/workflows/ruby-ci.yml@main
    secrets:
      github-token: ${{ secrets.ORG_GITHUB_TOKEN_FOR_CI }}
      pkg-github-com: ${{ secrets.PACKAGES_PAT }}
```

Enable code coverage check using https://github.com/reviewdog/action-setup

```yaml
name: CI

on:
  push:
  pull_request:
  workflow_dispatch:

jobs:
  ci:
    uses: 84codes/actions/.github/workflows/ruby-ci.yml@main
    with:
      reviewdog: true
    secrets:
      repo-github-token: ${{ secrets.GITHUB_TOKEN }}
```

#### Heroku deploy

`heroku-app` is optional, uses the repo name by default.

```yaml
name: Deploy to Heroku

on:
  workflow_run:
    workflows: [CI]
    types: [completed]

jobs:
  heroku:
    uses: 84codes/actions/.github/workflows/heroku.yml@main
    with:
      heroku-app: myapp
    secrets:
      heroku-key: ${{ secrets.HEROKU_API_KEY }}
```
