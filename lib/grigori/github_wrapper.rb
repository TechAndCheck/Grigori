require "sqlite3"
require "octokit"

class GithubWrapper
  Dotenv.load # Not sure why I have to do this so many times, but I do
  @@github = Octokit::Client.new(access_token: "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")
  @@db = SQLite3::Database.new "./test.db"

  def self.get_open_prs
    prs = @@github.pull_requests("TechAndCheck/hypatia")
    prs.select { |pr| pr.state == "open" && pr.draft == false }
  end

  def self.get_branch_for_pr(pr)
    pr.head.ref
  end

  def self.get_branch(branch_name)
    @@github.branch("TechAndCheck/hypatia", branch_name)
  end

  def self.get_latest_commit_for_branch(branch_name)
    self.get_branch(branch_name).commit
  end

  def self.save_last_commit(branch, commit)
    # Check if we have a listing for this branch yet
    if get_last_commit(branch).nil?
      @@db.execute "insert into status ('latest_commit', 'branch') values  ( ?, ?)", commit, branch
    else
      @@db.execute "update status set latest_commit = ? where branch = ? ", commit, branch
    end
  end

  def self.get_last_commit(branch)
    last_commit = @@db.execute("select latest_commit from status where branch = ? limit 1", branch)
    return last_commit.first.first unless last_commit.first.nil?
  end
end
