require "github_api"
require "debug"

require "thor"
require "sqlite3"
require "securerandom"
require "shellwords"
require "fileutils"
require "socket"
require "thin"

class Grigori < Thor
  @github = Github.new

  desc "init", "Set up everything for the first use"
  def init
    db = SQLite3::Database.new "./test.db"

    # Create a table
    db.execute <<-SQL
      create table status (
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

  desc "listen", "Start listening"
  def listen
    ractor = Ractor.new do
      loop do
        message = Ractor.receive
        puts "*****************"
        puts "Received message: #{message}"
        puts "*****************"
        vm_index = VMManager.current_vms.find_index { |vm| vm.vm_name == message }
        raise "VM not found in our manager" if vm_index.nil?

        vm = VMManager.current_vms[vm_index]
        vm.shutdown_vm
        vm.delete_vm
      end
    end

    ListeningServer.new(ractor)
  end
end

class ListeningServer
  def initialize(response_ractor)
    @@response_ractor = response_ractor

    Thin::Server.start("0.0.0.0", 2345) do
      use Rack::CommonLogger
      map "/tests_completed" do
        run SimpleAdapter.new
      end
    end
  end

  def self.response_ractor
    @@response_ractor
  end

  class SimpleAdapter
    def call(env)
      request = Rack::Request.new(env)
      # Get body from request
      body = JSON.parse(request.body.string)
      # Get ID of VM from request
      vm_id = body["vm_id"]
      # Get the status
      test_status_code = body["status_code"]
      test_status_message = body["status_message"]
      # Verify that we have a VM with that name running
      body = { message: "successfully finished vm: #{vm_id}", code: 200 } if VMManager.vm_exist?(vm_id)

      # Send a ractor message to handle this all
      ListeningServer.response_ractor.send(vm_id)

      [
        200,
        { "Content-Type" => "text/plain" },
        body
      ]
    end
  end
end

class VMManager
  BASE_VM_NAME = "Ubuntu 22.04 ARM64"
  @@db = SQLite3::Database.new "./test.db"
  @@current_vms = []

  def self.clone_vm
    vm = VM.new(BASE_VM_NAME)
    @@current_vms << vm
    vm.setup_vm_environment("something-like-a-pr")
    vm.start_vm
    # vm.shutdown_vm
    # vm.delete_vm
  end

  def self.vm_exist?(vm_id)
    @@db.execute("select count(*) from vms where id = ?", vm_id).count.positive?
  end

  def self.current_vms
    # TODO
    # If we restart the service we still want it to manage the already running systems, so we find them
    # @@current_vms = @@db.execute("select * from vms", vm_id).map do |vm|
    #   VM.new(vm_id, vm_id)
    # end if @@current_vms.empty?

    @@current_vms
  end

  class VM
    @vm_name = nil
    @db = nil

    attr_reader :vm_name

    def initialize(base_vm_name, new_name = nil)
      @vm_name = new_name.nil? ? "#{base_vm_name}_#{SecureRandom.uuid}_#{DateTime.now.strftime("%Y%m%dT%H%M")}" : new_name
      puts "Cloning new VM named #{@vm_name}"
      `prlctl clone "#{BASE_VM_NAME}" --name "#{@vm_name}"`

      @db = SQLite3::Database.new "./test.db"
      @db.execute "insert into vms values ( ?, 'pending' )", @vm_name
    end

    def start_vm
      # puts "Starting #{@vm_name}"
      `prlctl start "#{@vm_name}"`
      update_vm_status("starting")

      # now wait until it's running (this usually is quick)
      timeout = 0
      while `prlctl status "#{@vm_name}"`.split(" ").last != "running" && timeout < 60
        puts "Waiting..."
        sleep(1)
        timeout += 1
      end

      update_vm_status("running")
    end

    # To pass in variables, such as the branch name, etc, we need to get data *into* the VM.
    # To do this we create a shared folder, and attach it to the VM. The VM will then run some scripts
    # at the beginning to read this and do its thing.
    def setup_vm_environment(pr_name)
      Dir.mkdir("./.vm_setup") unless Dir.exist?("./.vm_setup")
      vm_environment_injection_path = "./.vm_setup/#{Shellwords.escape(@vm_name)}"
      Dir.mkdir(vm_environment_injection_path)

      FileUtils.cp_r "./injection_payload/.", vm_environment_injection_path
      # TODO: Add vmname to the variables files

      # And add the folder to the VM
      `prlctl set "#{@vm_name}" --shf-host-add "env_injection_files" --path "#{vm_environment_injection_path}"`

      # Save it so we know what's going on
      update_vm_status("pending")
    end

    def shutdown_vm
      update_vm_status("stopping")
      puts "Killing #{@vm_name}"
      `prlctl stop "#{@vm_name}" --kill` # We kill here because we delete it immediately anyways

      # now wait until it's stopped
      timeout = 0
      while `prlctl status "#{@vm_name}"`.split(" ").last != "stopped" && timeout < 60
        puts "Waiting..."
        sleep(1)
        timeout += 1
      end
      update_vm_status("stopped")
    end

    def delete_vm
      update_vm_status("deleting")
      puts "Deleting #{@vm_name}"
      `prlctl delete "#{@vm_name}"`

      # Delete the injection variables too
      FileUtils.rm_rf "./.vm_setup/#{Shellwords.escape(@vm_name)}"
      update_vm_status("deleted")
    end

    def update_vm_status(status = nil)
      # Consider adding an enum?

      unless @db.execute("select count(*) from vms where id = ?", @vm_name).count.positive?
        @db.execute("insert into vms values ( ?, ? )", @vm_name, "pending")
        return if status.nil?
      end

      @db.execute("update vms set current_status = ? where id = ?", status, @vm_name)
    end
  end
end

class GithubWrapper
  @@github = Github.new
  @@db = SQLite3::Database.new "./test.db"

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
    @@db.execute "insert into status values ( ? )", commit["sha"]
  end

  def self.get_last_commit
    @@db.execute("select latest_commit from status limit 1").first
  end
end

Grigori.start(ARGV)

# Check the most recently PR - done
# Get the most recently commit - done
# If it's been committed since the last time we check, run the tests - done
# Actually search for the pr we're looking for, but meh, that's last

# Set up tiny localhost only web server - done
# Clone clean VM - done
# Set ENV variables (somehow?) with latest commit ID and PR name - done
# Launch clean VM - done
# Wait until VM returns
# Send notification if failed
# Kill the clean VM - done
