require "github_api"
require "debug"

require "thor"
require "sqlite3"

class Grigori < Thor
  @github = Github.new

  desc "init", "Set up everything for the first use"
  def init
    db = SQLite3::Database.new "test.db"

    # Create a table
    db.execute <<-SQL
      create table status (
        latest_commit varchar(30)
      );
    SQL
  rescue SQLite3::SQLException
    puts "Error: Invalid SQL."
    puts "This probably means you've run `init` before and it's unnecessary to run again."
  end

  desc "get PR", "say hello to [PR]"
  def get(pr)
    puts "Fetching #{pr} from Github"
    prs = GithubWrapper.get_open_prs()
    branch_name = GithubWrapper.get_branch_for_pr(prs.first)
    commit = GithubWrapper.get_latest_commit_for_branch(branch_name)
    GithubWrapper.save_last_commit(commit)

    if GithubWrapper.get_last_commit != commit["sha"]
      # Here we start the whole launch vm shit
    end

    # NOTHING, we'll fail fine
  end
end

class GithubWrapper
  @@github = Github.new

  def self.get_open_prs
    @@github.pull_requests.list("techandcheck", "hypatia").body
  end

  def self.get_branch_for_pr(pr)
    pr["head"]["ref"]
  end

  def self.get_latest_commit_for_branch(branch_name)
    branch = @@github.repos.branches.get "techandcheck", "hypatia", branch_name
    branch["commit"]
  end

  def self.save_last_commit(commit)
    db = SQLite3::Database.new "test.db"
    db.execute "insert into status values ( ? )", commit["sha"]
  end

  def self.get_last_commit
    db = SQLite3::Database.new "test.db"
    db.execute("select latest_commit from status limit 1").first
  end
end

Grigori.start(ARGV)

# Check the most recently PR - done
# Get the most recently commit - done
# If it's been committed since the last time we check, run the tests - done
# Actually search for the pr we're looking for, but meh, that's last

# Set up tiny localhost only web server
# Clone clean VM
# Set ENV variables (somehow?) with latest commit ID and PR name
# Launch clean VM
# Wait until VM returns
# Send notification if failed
# Kill the clean VM
