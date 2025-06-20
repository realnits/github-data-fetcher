import requests
import csv
import os
from time import sleep
import argparse
from datetime import datetime
import gc
import logging

# Set up logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[logging.StreamHandler()]
)
logger = logging.getLogger(__name__)

def get_github_repo_languages(org_name, token=None, output_file=None, batch_size=10):
    """
    Extract programming languages used in repositories of a GitHub organization.
    
    Args:
        org_name (str): GitHub organization name
        token (str, optional): GitHub personal access token for authentication
        output_file (str, optional): Name of the output CSV file
        batch_size (int): Number of repositories to process at once
    """
    if not output_file:
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        output_file = f"{org_name}_repo_languages_{timestamp}.csv"
    
    # API endpoint for organization repositories
    base_url = "https://api.github.com"
    repos_url = f"{base_url}/orgs/{org_name}/repos"
    
    # Headers for authentication and to reduce response size
    headers = {
        "Accept": "application/vnd.github.v3+json"
    }
    if token:
        headers["Authorization"] = f"token {token}"
    
    # Get all repositories (with pagination handling)
    all_repos = []
    page = 1
    per_page = 30  # Smaller page size to reduce memory usage
    
    logger.info(f"Fetching repositories for organization: {org_name}")
    
    # First, just collect repository metadata (not languages yet)
    try:
        while True:
            params = {"page": page, "per_page": per_page}
            logger.info(f"Fetching page {page} of repositories")
            
            try:
                response = requests.get(repos_url, headers=headers, params=params, timeout=30)
                response.raise_for_status()
            except requests.exceptions.RequestException as e:
                logger.error(f"Error fetching repositories: {e}")
                if hasattr(e.response, 'status_code') and e.response.status_code == 404:
                    logger.error(f"Organization '{org_name}' not found.")
                    return
                
                # If we hit rate limits, wait and retry
                if hasattr(e.response, 'status_code') and e.response.status_code == 403:
                    reset_time = int(e.response.headers.get('X-RateLimit-Reset', 0))
                    current_time = int(datetime.now().timestamp())
                    sleep_time = max(reset_time - current_time + 1, 60)
                    logger.info(f"Rate limit reached. Sleeping for {sleep_time} seconds.")
                    sleep(sleep_time)
                    continue
                
                # For memory errors, wait longer and retry
                if "Cannot allocate memory" in str(e):
                    logger.info("Memory allocation error. Sleeping for 60 seconds to free resources.")
                    gc.collect()  # Force garbage collection
                    sleep(60)
                    continue
                    
                raise
            
            repos_page = response.json()
            if not repos_page:
                break
                
            # Only store necessary data to save memory
            for repo in repos_page:
                all_repos.append({
                    "name": repo["name"],
                    "languages_url": repo["languages_url"],
                    "html_url": repo["html_url"],
                    "description": repo["description"] or "",
                    "created_at": repo["created_at"],
                    "updated_at": repo["updated_at"],
                    "stargazers_count": repo["stargazers_count"],
                    "forks_count": repo["forks_count"],
                    "private": repo["private"]
                })
            
            logger.info(f"Fetched {len(repos_page)} repositories")
            page += 1
            
            # Check rate limits
            if response.headers.get('X-RateLimit-Remaining') == '0':
                reset_time = int(response.headers.get('X-RateLimit-Reset', 0))
                current_time = int(datetime.now().timestamp())
                sleep_time = max(reset_time - current_time + 1, 10)
                logger.info(f"Rate limit reached. Sleeping for {sleep_time} seconds.")
                sleep(sleep_time)
            else:
                # Small delay between requests
                sleep(1)
            
            # Force garbage collection after each page
            gc.collect()
    
    except Exception as e:
        logger.error(f"Error fetching repositories: {e}")
        return
    
    total_repos = len(all_repos)
    logger.info(f"Found {total_repos} repositories in total.")
    
    # Gather languages for all repositories in batches first
    # The CSV is written in a later pass once the language list is complete
    all_languages = set()
    
    # First pass: collect all languages across repositories
    logger.info("First pass: collecting all languages")
    for i in range(0, total_repos, batch_size):
        batch = all_repos[i:i+batch_size]
        logger.info(f"Processing batch {i//batch_size + 1}/{(total_repos-1)//batch_size + 1} for language discovery")
        
        for repo in batch:
            try:
                lang_response = requests.get(repo["languages_url"], headers=headers, timeout=30)
                lang_response.raise_for_status()
                languages = lang_response.json()
                all_languages.update(languages.keys())
                
                # Small delay between requests
                sleep(0.5)
            except requests.exceptions.RequestException as e:
                logger.warning(f"Error fetching languages for {repo['name']}: {e}")
                # For memory errors, wait longer and retry
                if "Cannot allocate memory" in str(e):
                    logger.info("Memory allocation error. Sleeping for 30 seconds to free resources.")
                    gc.collect()  # Force garbage collection
                    sleep(30)
                continue
        
        # Force garbage collection after each batch
        gc.collect()
    
    # Sort languages alphabetically
    all_languages = sorted(all_languages)
    
    # Prepare CSV headers
    headers_csv = [
        "Repository", "URL", "Description", "Primary Language", 
        "Created At", "Updated At", "Stars", "Forks", "Private"
    ]
    
    # Add language columns
    for lang in all_languages:
        headers_csv.append(f"{lang} (%)")
    
    logger.info(f"Writing data to {output_file}")
    
    # Open CSV file for writing
    with open(output_file, "w", newline="", encoding="utf-8") as csvfile:
        writer = csv.writer(csvfile)
        writer.writerow(headers_csv)
        
        # Second pass: process repositories in batches
        for i in range(0, total_repos, batch_size):
            batch = all_repos[i:i+batch_size]
            logger.info(f"Processing batch {i//batch_size + 1}/{(total_repos-1)//batch_size + 1} for CSV writing")
            
            batch_data = []
            for repo in batch:
                try:
                    lang_response = requests.get(repo["languages_url"], headers=headers, timeout=30)
                    lang_response.raise_for_status()
                    languages = lang_response.json()
                    
                    # Calculate percentages
                    total_bytes = sum(languages.values())
                    languages_with_percentages = {}
                    for lang, bytes_count in languages.items():
                        percentage = round(bytes_count / total_bytes * 100, 2) if total_bytes > 0 else 0
                        languages_with_percentages[lang] = percentage
                    
                    # Find primary language (highest percentage)
                    primary_language = max(languages.items(), key=lambda x: x[1])[0] if languages else "None"
                    
                    # Create row data
                    row = [
                        repo["name"],
                        repo["html_url"],
                        repo["description"],
                        primary_language,
                        repo["created_at"],
                        repo["updated_at"],
                        repo["stargazers_count"],
                        repo["forks_count"],
                        "Yes" if repo["private"] else "No"
                    ]
                    
                    # Add language percentages
                    for lang in all_languages:
                        percentage = languages_with_percentages.get(lang, 0)
                        row.append(percentage)
                    
                    writer.writerow(row)
                    
                    # Small delay between requests
                    sleep(0.5)
                except requests.exceptions.RequestException as e:
                    logger.warning(f"Error fetching languages for {repo['name']}: {e}")
                    # For memory errors, wait longer and retry
                    if "Cannot allocate memory" in str(e):
                        logger.info("Memory allocation error. Sleeping for 30 seconds to free resources.")
                        gc.collect()  # Force garbage collection
                        sleep(30)
                    continue
            
            # Force garbage collection after each batch
            gc.collect()
            csvfile.flush()  # Flush data to disk after each batch
    
    logger.info(f"Data exported successfully to {output_file}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Extract programming languages from GitHub organization repositories")
    parser.add_argument("org_name", help="GitHub organization name")
    parser.add_argument("--token", "-t", help="GitHub personal access token")
    parser.add_argument("--output", "-o", help="Output CSV file name")
    parser.add_argument("--batch-size", "-b", type=int, default=10, help="Number of repositories to process at once")
    
    args = parser.parse_args()
    
    # Get token from environment variable if not provided
    if not args.token and "GITHUB_TOKEN" in os.environ:
        args.token = os.environ["GITHUB_TOKEN"]
    
    get_github_repo_languages(args.org_name, args.token, args.output, args.batch_size)
