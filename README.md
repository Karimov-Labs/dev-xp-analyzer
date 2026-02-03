# Dev XP Analyzer - GitHub Action

Automatically analyze code changes and track developer skills with the Dev XP platform. This action collects metadata about commits and pull requests and submits them for AI-powered skill analysis.

## Features

- 🔄 **Automatic detection** of push and pull request events
- 📊 **File change tracking** including additions, deletions, and renames
- 👥 **Multi-author support** for pull requests with multiple contributors
- 🔒 **Secure** API token authentication
- 🔐 **Username masking** - SHA-256 hashing for regulated environments
- ⚡ **Lightweight** - no heavy processing in your CI/CD pipeline

## Quick Start

### 1. Get your API Token

1. Log in to your [Dev XP Dashboard](https://devxp.net/app)
2. Navigate to **Settings** → **API Tokens**
3. Create a new token with `analyze` scope
4. Copy the token (you won't be able to see it again)

### 2. Add the Secret to Your Repository

1. Go to your repository **Settings** → **Secrets and variables** → **Actions**
2. Click **New repository secret**
3. Name: `DEVXP_API_TOKEN`
4. Value: Your API token from step 1

### 3. Create the Workflow

Create `.github/workflows/devxp.yml` in your repository:

```yaml
name: Dev XP Analysis

on:
  push:
    branches: [main, master]
  pull_request:
    types: [closed]
    branches: [main, master]

jobs:
  analyze:
    # Only run on merged PRs or direct pushes
    if: github.event_name == 'push' || github.event.pull_request.merged == true
    runs-on: ubuntu-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v4
        with:
          fetch-depth: 2  # Need at least 2 commits for diff

      - name: Analyze with Dev XP
        uses: Karimov-Labs/dev-xp/actions/dev-xp-agent@main
        with:
          api-token: ${{ secrets.DEVXP_API_TOKEN }}
```

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `api-token` | Dev XP API token for authentication | Yes | - |
| `api-endpoint` | Dev XP API endpoint URL | No | `https://api.devxp.net` |
| `event-type` | Event type: `push`, `pull_request`, or `auto` | No | `auto` |
| `include-file-content` | Include file diff content (increases accuracy) | No | `false` |
| `max-files` | Maximum files to include per event | No | `100` |
| `mask-usernames` | Hash usernames using SHA-256 for privacy | No | `false` |
| `masking-salt` | Salt for username hashing (use consistent value across org) | No | `''` |

## Outputs

| Output | Description |
|--------|-------------|
| `status` | Status of the analysis submission (`success`/`failed`) |
| `workflow-id` | Dev XP workflow ID for tracking |
| `message` | Response message from Dev XP API |

## Usage Examples

### Basic Setup (Push + Merged PRs)

```yaml
name: Dev XP Analysis

on:
  push:
    branches: [main]
  pull_request:
    types: [closed]
    branches: [main]

jobs:
  analyze:
    if: github.event_name == 'push' || github.event.pull_request.merged == true
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 2
      - uses: Karimov-Labs/dev-xp/actions/dev-xp-agent@main
        with:
          api-token: ${{ secrets.DEVXP_API_TOKEN }}
```

### Only Merged Pull Requests

```yaml
name: Dev XP PR Analysis

on:
  pull_request:
    types: [closed]
    branches: [main, develop]

jobs:
  analyze:
    if: github.event.pull_request.merged == true
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0  # Full history for PR diff
      - uses: Karimov-Labs/dev-xp/actions/dev-xp-agent@main
        with:
          api-token: ${{ secrets.DEVXP_API_TOKEN }}
          event-type: pull_request
```

### Only Direct Pushes to Main

```yaml
name: Dev XP Push Analysis

on:
  push:
    branches: [main]

jobs:
  analyze:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 2
      - uses: Karimov-Labs/dev-xp/actions/dev-xp-agent@main
        with:
          api-token: ${{ secrets.DEVXP_API_TOKEN }}
          event-type: push
```

### Privacy Mode (Regulated Environments)

For highly regulated environments (financial, healthcare, government) where developer identities must not be disclosed:

```yaml
name: Dev XP Analysis (Privacy Mode)

on:
  push:
    branches: [main]
  pull_request:
    types: [closed]
    branches: [main]

jobs:
  analyze:
    if: github.event_name == 'push' || github.event.pull_request.merged == true
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 2
      - uses: Karimov-Labs/dev-xp/actions/dev-xp-scanner@main
        with:
          api-token: ${{ secrets.DEVXP_API_TOKEN }}
          # Enable username masking - all usernames will be SHA-256 hashed
          mask-usernames: 'true'
          # Use a consistent salt across your organization for correlation
          # Store this as a secret to keep it confidential
          masking-salt: ${{ secrets.DEVXP_MASKING_SALT }}
```

**How username masking works:**
- All author names and emails are hashed using SHA-256 before leaving your environment
- The hash is truncated to 16 characters for readability (e.g., `john.doe@corp.com` → `a1b2c3d4e5f6g7h8`)
- Using a consistent salt allows you to correlate the same developer across repositories
- Dev XP never receives the original usernames when masking is enabled
- Skills are still accurately attributed to unique (hashed) developer IDs

### Using Outputs for Conditional Logic

```yaml
name: Dev XP with Outputs

on:
  push:
    branches: [main]

jobs:
  analyze:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 2

      - name: Analyze with Dev XP
        id: devxp
        uses: Karimov-Labs/dev-xp/actions/dev-xp-agent@main
        with:
          api-token: ${{ secrets.DEVXP_API_TOKEN }}

      - name: Check analysis status
        if: steps.devxp.outputs.status == 'success'
        run: |
          echo "✅ Analysis submitted successfully!"
          echo "Workflow ID: ${{ steps.devxp.outputs.workflow-id }}"
```

### Self-Hosted Dev XP Instance

```yaml
name: Dev XP (Self-Hosted)

on:
  push:
    branches: [main]

jobs:
  analyze:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 2
      - uses: Karimov-Labs/dev-xp/actions/dev-xp-agent@main
        with:
          api-token: ${{ secrets.DEVXP_API_TOKEN }}
          api-endpoint: https://devxp.your-company.com
```

## Data Collected

The action collects the following data for analysis:

### Push Events
- Commit SHA
- Author name and email
- Commit message
- Timestamp
- Changed files with addition/deletion counts

### Pull Request Events
- PR number and title
- PR author
- Merge timestamp
- All commits in the PR
- Changed files with addition/deletion counts

## Security

- **API tokens** are never logged or exposed
- Data is transmitted over **HTTPS**
- Only **metadata** is sent (no file contents by default)
- Tokens can be **revoked** at any time from the dashboard

### Username Masking (Privacy Mode)

For organizations with strict privacy requirements:

| Feature | Description |
|---------|-------------|
| **Algorithm** | SHA-256 cryptographic hash |
| **Output** | 16-character hex string |
| **Salting** | Optional organization-wide salt for correlation |
| **Scope** | Author names, emails, and sender usernames |
| **Timing** | Hashing occurs locally before data leaves your environment |

**When to use username masking:**
- Financial institutions with employee data protection requirements
- Healthcare organizations subject to HIPAA
- Government contractors with security clearances
- Any organization that cannot disclose staff identities to third parties

**Data flow with masking enabled:**
```
Your Repository → GitHub Action → SHA-256 Hash → Dev XP API
                                    ↑
                         (happens locally)
```

## Troubleshooting

### "Invalid API token" Error

1. Verify the token is correctly set in repository secrets
2. Check if the token is still active in your Dev XP dashboard
3. Ensure the token has the `analyze` scope

### "Authorization header is required" Error

Make sure you're passing the `api-token` input:

```yaml
- uses: Karimov-Labs/dev-xp/actions/dev-xp-agent@main
  with:
    api-token: ${{ secrets.DEVXP_API_TOKEN }}  # Don't forget this!
```

### No Files Detected

Ensure you're checking out with enough history:

```yaml
- uses: actions/checkout@v4
  with:
    fetch-depth: 2  # Minimum for push events
    # or fetch-depth: 0 for full history (PRs)
```

### Rate Limiting

If you're hitting rate limits, consider:
- Reducing `max-files` input
- Only running on merged PRs (not all pushes)
- Contacting support for higher limits

## Support

- 📧 Email: info@karimovlabs.com
- 📖 Docs: [docs.devxp.net](https://docs.devxp.net)
- 🐛 Issues: [GitHub Issues](https://github.com/Karimov-Labs/dev-xp-analyzer/issues)

## License

Apache License - see [LICENSE](/LICENSE) for details.
