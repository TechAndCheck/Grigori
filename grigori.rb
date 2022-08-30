require "github_api"
require "debug"

require "thor"
require "sqlite3"
require "securerandom"
require "shellwords"
require "fileutils"

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

  desc "boot", "Boot up a vm clone, this is for testing right now"
  def boot
    VMManager.clone_vm
  end
end

class VMManager
  BASE_VM_NAME = "Ubuntu 22.04 ARM64"

  def self.clone_vm
    vm = VM.new(BASE_VM_NAME)
    vm.start_vm
    vm.setup_vm_environment("something-like-a-pr")
    vm.shutdown_vm
    vm.delete_vm
  end

  class VM
    @vm_name = nil

    def initialize(base_vm_name, new_name = nil)
      @vm_name = new_name.nil? ? "#{base_vm_name}_#{SecureRandom.uuid}_#{DateTime.now.strftime("%Y%m%dT%H%M")}" : new_name
      puts "Cloning new VM named #{@vm_name}"
      `prlctl clone "#{base_vm_name}" --name "#{@vm_name}"`
    end

    def start_vm
      puts "Starting #{@vm_name}"
      `prlctl start "#{@vm_name}"`

      # now wait until it's running (this usually is quick)
      timeout = 0
      while `prlctl status "#{@vm_name}"`.split(" ").last != "running" && timeout < 60
        puts "Waiting..."
        sleep(1)
        timeout += 1
      end
    end

    # To pass in variables, such as the branch name, etc, we need to get data *into* the VM.
    # To do this we create a shared folder, and attach it to the VM. The VM will then run some scripts
    # at the beginning to read this and do its thing.
    def setup_vm_environment(pr_name)
      Dir.mkdir("./.vm_setup") unless Dir.exist?("./.vm_setup")
      vm_environment_injection_path = "./.vm_setup/#{Shellwords.escape(@vm_name)}"
      Dir.mkdir(vm_environment_injection_path)

      # Now write the stuff we want
      File.open("#{vm_environment_injection_path}/env_injection_variables.txt", "a") do |line|
        line.puts "HYPATIA_GIT_PR_NAME=#{pr_name}"
      end

      # And add the folder to the VM
      `prlctl set "#{@vm_name}" --shf-host-add "env_injection_variables" --path "#{vm_environment_injection_path}"`
    end

    def shutdown_vm
      puts "Killing #{@vm_name}"
      `prlctl stop "#{@vm_name}" --kill` # We kill here because we delete it immediately anyways

      # now wait until it's stopped
      timeout = 0
      while `prlctl status "#{@vm_name}"`.split(" ").last != "stopped" && timeout < 60
        puts "Waiting..."
        sleep(1)
        timeout += 1
      end
    end

    def delete_vm
      puts "Deleting #{@vm_name}"
      `prlctl delete "#{@vm_name}"`

      # Delete the injection variables too
      FileUtils.rm_rf "./.vm_setup/#{Shellwords.escape(@vm_name)}"
    end
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
# Clone clean VM - done
# Set ENV variables (somehow?) with latest commit ID and PR name
# Launch clean VM - done
# Wait until VM returns
# Send notification if failed
# Kill the clean VM - done
