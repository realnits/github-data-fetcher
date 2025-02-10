#!/usr/bin/env ruby

require 'octokit'
require 'optparse'
require 'json'
require 'csv'
require 'erb'

class GitHubOrgStats
  MAX_RETRIES = 3
  PER_PAGE = 100  # Maximum allowed by GitHub API

  def initialize(token, org)
    @client = Octokit::Client.new(
      access_token: token,
      auto_paginate: false  # We'll handle pagination manually for better control
    )
    @org = org
    @data = {}
    
    # Configure client
    @client.connection_options[:request] = {
      open_timeout: 30,
      timeout: 30
    }
  end

  def collect_data
    puts "Collecting data for #{@org}..."
    check_rate_limit
    
    begin
      # Get organization details with retry
      org_info = with_retry { @client.organization(@org) }
      @data[:organization] = {
        name: org_info.name,
        description: org_info.description,
        public_repos: org_info.public_repos,
        total_private_repos: org_info.total_private_repos,
        created_at: org_info.created_at
      }

      # Initialize repositories array
      @data[:repositories] = []
      
      # Fetch all repositories with pagination
      page = 1
      total_repos = []
      
      loop do
        check_rate_limit
        puts "Fetching repositories page #{page}..."
        
        repos_page = with_retry do
          @client.organization_repositories(
            @org,
            type: 'all',
            per_page: PER_PAGE,
            page: page
          )
        end
        
        break if repos_page.empty?
        total_repos.concat(repos_page)
        page += 1
      end

      puts "\nFound #{total_repos.count} repositories"
      
      # Process each repository
      total_repos.each_with_index do |repo, index|
        puts "\nProcessing repository #{index + 1}/#{total_repos.count}: #{repo.name}"
        repo_data = collect_repository_data(repo)
        @data[:repositories] << repo_data
      end

      # Verify repository count
      expected_total = org_info.public_repos + org_info.total_private_repos
      actual_total = @data[:repositories].count
      
      if actual_total != expected_total
        puts "\nWARNING: Repository count mismatch!"
        puts "Expected: #{expected_total}, Actual: #{actual_total}"
        puts "This might indicate some repositories were missed or access issues."
      else
        puts "\nSuccessfully collected data for all #{actual_total} repositories!"
      end

    rescue Octokit::Error => e
      puts "Error accessing GitHub API: #{e.message}"
      raise
    end
  end

  private

  def collect_repository_data(repo)
    repo_data = {
      name: repo.name,
      full_name: repo.full_name,
      description: repo.description,
      private: repo.private,
      language: repo.language,
      stars: repo.stargazers_count,
      forks: repo.forks_count,
      created_at: repo.created_at,
      updated_at: repo.updated_at,
      branches: [],
      contributors: [],
      topics: repo.topics || [],
      default_branch: repo.default_branch,
      size: repo.size,
      open_issues_count: repo.open_issues_count
    }

    # Get branches with pagination
    collect_branches(repo, repo_data)

    # Get contributors with pagination
    collect_contributors(repo, repo_data)

    repo_data
  end

  def collect_branches(repo, repo_data)
    page = 1
    loop do
      check_rate_limit
      branches_page = with_retry do
        @client.branches(
          repo.full_name,
          per_page: PER_PAGE,
          page: page
        )
      end
      
      break if branches_page.empty?
      
      branches_page.each do |branch|
        repo_data[:branches] << {
          name: branch.name,
          sha: branch.commit.sha,
          protected: branch.protected || false
        }
      end
      
      page += 1
    end
    puts "  √ Collected #{repo_data[:branches].count} branches"
  end

  def collect_contributors(repo, repo_data)
    return if repo.private  # Skip for private repos if contributors endpoint is disabled
    
    page = 1
    loop do
      check_rate_limit
      begin
        contributors_page = with_retry do
          @client.contributors(
            repo.full_name,
            per_page: PER_PAGE,
            page: page
          )
        end
        
        break if contributors_page.empty?
        
        contributors_page.each do |contributor|
          repo_data[:contributors] << {
            login: contributor.login,
            contributions: contributor.contributions,
            type: contributor.type
          }
        end
        
        page += 1
      rescue Octokit::Error => e
        puts "  ! Warning: Could not fetch contributors: #{e.message}"
        break
      end
    end
    puts "  √ Collected #{repo_data[:contributors].count} contributors"
  end

  def check_rate_limit
    rate_limit = @client.rate_limit
    remaining = rate_limit.remaining
    
    if remaining < 100
      reset_time = Time.at(rate_limit.resets_at)
      wait_time = reset_time - Time.now
      
      if wait_time > 0
        puts "\nRate limit low (#{remaining} remaining). Waiting #{wait_time.to_i} seconds for reset..."
        sleep(wait_time + 1)
      end
    end
  end

  def with_retry
    retries = 0
    begin
      yield
    rescue Octokit::Error => e
      retries += 1
      if retries <= MAX_RETRIES
        puts "  ! Error: #{e.message}. Retrying (#{retries}/#{MAX_RETRIES})..."
        sleep(2 ** retries)  # Exponential backoff
        retry
      else
        raise
      end
    end
  end

  public

  def export_json(filename)
    File.write(filename, JSON.pretty_generate(@data))
    puts "JSON data exported to #{filename}"
  end

  def export_csv(filename)
    CSV.open(filename, "wb") do |csv|
      # Header row
      csv << [
        "Repository",
        "Private",
        "Language",
        "Stars",
        "Forks",
        "Branch Count",
        "Contributor Count",
        "Size (KB)",
        "Open Issues",
        "Topics",
        "Default Branch",
        "Created At",
        "Updated At"
      ]
      
      # Data rows
      @data[:repositories].each do |repo|
        csv << [
          repo[:name],
          repo[:private],
          repo[:language],
          repo[:stars],
          repo[:forks],
          repo[:branches].count,
          repo[:contributors].count,
          repo[:size],
          repo[:open_issues_count],
          repo[:topics].join(";"),
          repo[:default_branch],
          repo[:created_at],
          repo[:updated_at]
        ]
      end
    end
    puts "CSV data exported to #{filename}"
  end

  def export_html(filename)
    template = <<-HTML
      <!DOCTYPE html>
      <html>
        <head>
          <title>GitHub Organization Stats - <%= @data[:organization][:name] %></title>
          <style>
            body { font-family: Arial, sans-serif; margin: 20px; }
            table { border-collapse: collapse; width: 100%; margin-bottom: 20px; }
            th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
            th { background-color: #f4f4f4; }
            .repo-header { background-color: #e0e0e0; }
            .summary { background-color: #f8f8f8; padding: 15px; margin-bottom: 20px; }
            .topics { display: flex; flex-wrap: wrap; gap: 5px; }
            .topic { background-color: #e1e4e8; padding: 2px 6px; border-radius: 3px; font-size: 12px; }
          </style>
        </head>
        <body>
          <h1>GitHub Organization: <%= @data[:organization][:name] %></h1>
          
          <div class="summary">
            <h2>Organization Summary</h2>
            <p>Description: <%= @data[:organization][:description] %></p>
            <p>Public Repos: <%= @data[:organization][:public_repos] %></p>
            <p>Private Repos: <%= @data[:organization][:total_private_repos] %></p>
            <p>Total Repos: <%= @data[:repositories].count %></p>
            <p>Created: <%= @data[:organization][:created_at] %></p>
          </div>
          
          <h2>Repositories</h2>
          <% @data[:repositories].each do |repo| %>
            <table>
              <tr class="repo-header">
                <th colspan="2"><%= repo[:name] %> (<%= repo[:private] ? 'Private' : 'Public' %>)</th>
              </tr>
              <tr>
                <td>Description</td>
                <td><%= repo[:description] %></td>
              </tr>
              <tr>
                <td>Language</td>
                <td><%= repo[:language] %></td>
              </tr>
              <tr>
                <td>Topics</td>
                <td>
                  <div class="topics">
                    <% repo[:topics].each do |topic| %>
                      <span class="topic"><%= topic %></span>
                    <% end %>
                  </div>
                </td>
              </tr>
              <tr>
                <td>Statistics</td>
                <td>
                  Stars: <%= repo[:stars] %><br>
                  Forks: <%= repo[:forks] %><br>
                  Size: <%= repo[:size] %> KB<br>
                  Open Issues: <%= repo[:open_issues_count] %>
                </td>
              </tr>
              <tr>
                <td>Branches (<%= repo[:branches].count %>)</td>
                <td>
                  <ul>
                    <% repo[:branches].each do |branch| %>
                      <li>
                        <%= branch[:name] %>
                        <%= " (Default)" if branch[:name] == repo[:default_branch] %>
                        <%= " (Protected)" if branch[:protected] %>
                      </li>
                    <% end %>
                  </ul>
                </td>
              </tr>
              <tr>
                <td>Top Contributors</td>
                <td>
                  <ul>
                    <% repo[:contributors].first(10).each do |contributor| %>
                      <li><%= contributor[:login] %> (<%= contributor[:contributions] %> commits)</li>
                    <% end %>
                  </ul>
                </td>
              </tr>
            </table>
          <% end %>
        </body>
      </html>
    HTML
    
    renderer = ERB.new(template)
    File.write(filename, renderer.result(binding))
    puts "HTML report exported to #{filename}"
  end
end

# Parse command line arguments
options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: github_stats.rb [options]"

  opts.on("-t", "--token TOKEN", "GitHub API token") do |token|
    options[:token] = token
  end

  opts.on("-o", "--org ORGANIZATION", "GitHub organization name") do |org|
    options[:org] = org
  end

  opts.on("-f", "--format FORMAT", "Output format (json, csv, html)") do |format|
    options[:format] = format
  end
end.parse!

# Validate required options
unless options[:token] && options[:org] && options[:format]
  puts "Error: Missing required arguments"
  puts "Usage: ruby github_stats.rb -t <token> -o <organization> -f <format>"
  exit 1
end

# Create stats object and collect data
stats = GitHubOrgStats.new(options[:token], options[:org])
stats.collect_data

# Export data in specified format
output_file = "github_stats_#{options[:org]}_#{Time.now.strftime('%Y%m%d_%H%M%S')}"
case options[:format].downcase
when "json"
  stats.export_json("#{output_file}.json")
when "csv"
  stats.export_csv("#{output_file}.csv")
when "html"
  stats.export_html("#{output_file}.html")
else
  puts "Unsupported format: #{options[:format]}"
  exit 1
end
