require "thor"
require "sqlite3"
require "dotenv"

require_relative "lib/grigori"

class Grigori < Thor
  DATABASE_FILE = "./test.rb"

  @github = Github.new
  Dotenv.load

  desc "init", "Set up everything for the first use"
  def init
    db = SQLite3::Database.new DATABASE_FILE

    # Create a table
    db.execute <<-SQL
      create table status (
        branch varchar(30),
        latest_commit varchar(30)
      );
    SQL

    db.execute <<-SQL
      create table vms (
        id varchar(30),
        current_status varchar(30)
      );
    SQL
  rescue SQLite3::SQLException
    puts "Error: Invalid SQL."
    puts "This probably means you've run `init` before and it's unnecessary to run again."
  end

  desc "start", "Start it up"
  def start
    GithubWatcherJob.perform_async
    ListeningServer.new
  end

  desc "get PR", "say hello to [PR]"
  def get(pr)
    pr = pr.to_i
    puts "Fetching #{pr} from Github"
    prs = GithubWrapper.get_open_prs()

    # Search for PR
    index = prs.index do |found_pr|
      found_pr["number"] == pr
    end

    raise "PR not found" if index.nil?
    pr = prs[index]

    branch_name = GithubWrapper.get_branch_for_pr(pr)
    commit = GithubWrapper.get_latest_commit_for_branch(branch_name)

    if GithubWrapper.get_last_commit(branch_name) != commit["sha"]
      VMManager.clone_vm(pr, commit["sha"])
      ListeningServer.new
      # Here we start the whole launch vm shit

      # save if done
      # GithubWrapper.save_last_commit(branch_name, commit)
    end

    # NOTHING, we'll fail fine
  end

  desc "reset", "Reset everything, shut down all running vms, etc."
  def reset
    # Shut down all the Vm's running
    listing = `prlctl list`
    captures = listing.lines.map do |line|
      matches = line.match(/{[0-9a-z-]+} +[a-z]+ +- +(.+)/)
      matches.captures unless matches.nil?
    end.flatten.compact

    vms = captures.map do |capture|
      VMManager::VM.new(capture, capture, true)
    end
    vms.each { |vm| vm.shutdown_vm && vm.delete_vm }

    # Delete the database file
    File.delete(DATABASE_FILE) if File.exist?(DATABASE_FILE)

    # Reinitialize everything
    init
  end
end

Grigori.start(ARGV)

# Check the most recently PR - done
# Get the most recently commit - done
# If it's been committed since the last time we check, run the tests - done
# Actually search for the pr we're looking for, but meh, that's last - done

# Set up tiny localhost only web server - done
# Clone clean VM - done
# Set ENV variables (somehow?) with latest commit ID and PR name - done
# Launch clean VM - done
# Wait until VM returns - done
# Send notification if failed - done
# Kill the clean VM - done
