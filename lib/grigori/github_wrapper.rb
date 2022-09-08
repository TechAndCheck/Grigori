require "sqlite3"
require "github_api"

class GithubWrapper
  @@github = Github.new
  @@db = SQLite3::Database.new "./test.db"

  def self.get_open_prs
    prs = @@github.pull_requests.list("techandcheck", "hypatia").body
    prs.select { |pr| pr["state"] == "open" && pr["draft"] == false }
  end

  def self.get_branch_for_pr(pr)
    pr["head"]["ref"]
  end

  def self.get_latest_commit_for_branch(branch_name)
    branch = @@github.repos.branches.get "techandcheck", "hypatia", branch_name
    branch["commit"]
  end

  def self.save_last_commit(branch, commit)
    @@db.execute "insert into status values ( ?, ? )", branch, commit["sha"]
  end

  def self.get_last_commit(branch)
    last_commit = @@db.execute("select latest_commit from status where branch = ? limit 1", branch)
    return last_commit.first.first unless last_commit.first.nil?
  end
end

