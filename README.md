# GitHub Organization Statistics Collector

A Ruby script that collects comprehensive statistics and information about all repositories within a GitHub organization. The script handles both public and private repositories, providing detailed information about each repository, its branches, and contributors.

## Features

- **Complete Data Collection**
  - Fetches all repositories (both public and private)
  - Collects branch information with protection status
  - Gathers contributor statistics
  - Includes repository topics, size, and issues count
  - Handles pagination automatically

- **Multiple Export Formats**
  - JSON (detailed, complete dataset)
  - CSV (summary of key metrics)
  - HTML (formatted report with all information)

- **Robust Error Handling**
  - Automatic retry mechanism with exponential backoff
  - Rate limit awareness and handling
  - Detailed progress reporting
  - Data verification checks

## Prerequisites

- Ruby 2.6 or higher
- GitHub Personal Access Token with appropriate permissions:
  - `repo` - Full control of private repositories
  - `read:org` - Read organization information
  - `read:user` - Read user information
  - `read:discussion` - Read team discussions

## Installation

1. Clone this repository:
```bash
git clone https://github.com/yourusername/github-org-stats.git
cd github-org-stats
```

2. Install required gems:
```bash
gem install octokit erb optparse
```

## Usage

Run the script with the following command:

```bash
ruby github_stats.rb -t <github-token> -o <organization-name> -f <format>
```

### Arguments

- `-t, --token TOKEN`: Your GitHub Personal Access Token
- `-o, --org ORGANIZATION`: Name of the GitHub organization to analyze
- `-f, --format FORMAT`: Output format (json, csv, or html)

### Example

```bash
ruby github_stats.rb -t ghp_xxxxxxxxxxxx -o microsoft -f html
```

## Output Formats

### JSON
Provides the most detailed output, including:
- Complete organization information
- Detailed repository data
- Branch information with protection status
- Contributor statistics
- Repository topics and metadata

### CSV
Creates a summary spreadsheet with key metrics:
- Repository names and visibility
- Language statistics
- Star and fork counts
- Branch and contributor counts
- Repository size and issues
- Creation and update dates

### HTML
Generates a formatted report featuring:
- Organization summary
- Repository details in collapsible sections
- Branch protection status
- Top contributors
- Visual representation of repository statistics

## Sample Output Structure

### JSON Format
```json
{
  "organization": {
    "name": "Example Org",
    "description": "Organization description",
    "public_repos": 10,
    "total_private_repos": 5,
    "created_at": "2020-01-01T00:00:00Z"
  },
  "repositories": [
    {
      "name": "example-repo",
      "description": "Repository description",
      "private": false,
      "language": "Ruby",
      "stars": 100,
      "forks": 20,
      "branches": [...],
      "contributors": [...],
      "topics": [...],
      "default_branch": "main",
      "size": 1024,
      "open_issues_count": 5
    }
  ]
}
```

## Error Handling

The script includes several error handling mechanisms:

- **Rate Limit Handling**: Automatically waits when approaching GitHub API rate limits
- **Retry Mechanism**: Retries failed API calls with exponential backoff
- **Data Verification**: Ensures all repositories are collected
- **Progress Reporting**: Shows detailed progress during data collection

## Limitations

- API rate limits may affect collection time for large organizations
- Some data might be unavailable for private repositories depending on token permissions
- Contributor statistics might be disabled for some private repositories

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [Octokit](https://github.com/octokit/octokit.rb) - GitHub API client for Ruby
- GitHub API Documentation

## Support

For support, please open an issue in the GitHub repository or contact the maintainers.
