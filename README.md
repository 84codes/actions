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
    with:
      ruby-lint: true # needs both "github-token" and "repo-github-token" secrets
    secrets:
      repo-github-token: ${{ secrets.GITHUB_TOKEN }} # if project uses ruby-lint or reviewdog
      github-token: ${{ secrets.ORG_GITHUB_TOKEN_FOR_CI }} # if project uses private GitHub repos dependencies
      pkg-github-com: ${{ secrets.PACKAGES_PAT }} # if project uses private GitHub Packages
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
