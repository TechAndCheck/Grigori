require "sqlite3"
require "securerandom"
require "shellwords"
require "fileutils"

class VMManager
  BASE_VM_NAME = "Ubuntu 22.04 ARM64"
  @@db = SQLite3::Database.new "./test.db"
  @@current_vms = []

  def self.clone_vm(pr_name, commit_hash, branch: nil, test_file: nil, run_server: false)
    vm = VM.new(BASE_VM_NAME)
    @@current_vms << vm
    vm.setup_vm_environment(pr_name, commit_hash, branch: branch, test_file: test_file, run_server: run_server)
    vm.start_vm
  end

  def self.vm_exist?(vm_id)
    @@db.execute("select count(*) from vms where id = ?", vm_id).count.positive?
  end

  def self.vm_for_id(vm_id)
    return nil unless self.vm_exist?(vm_id)
    VM.new(vm_id, vm_id, true)
  end

  class VM
    @vm_name = nil
    @db = nil

    attr_reader :vm_name

    def initialize(base_vm_name, new_name = nil, restore = false)
      @db = SQLite3::Database.new "./test.db"

      @vm_name = new_name.nil? ? "#{base_vm_name}_#{SecureRandom.uuid}_#{DateTime.now.strftime("%Y%m%dT%H%M")}" : new_name
      return if restore == true # We bail out here since it already exists

      puts "Cloning new VM named #{@vm_name}"
      `prlctl clone "#{BASE_VM_NAME}" --name "#{@vm_name}"`

      @db.execute "insert into vms values ( ?, 'pending' )", @vm_name
    rescue StandardError => e
      debugger
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
    def setup_vm_environment(pr, commit_hash, branch: nil, test_file: nil, run_server: false)
      Dir.mkdir("./.vm_setup") unless Dir.exist?("./.vm_setup")
      vm_environment_injection_path = "./.vm_setup/#{Shellwords.escape(@vm_name)}"
      Dir.mkdir(vm_environment_injection_path)

      FileUtils.cp_r "./injection_payload/.", vm_environment_injection_path
      # Add the vm name to the variables files
      File.open(File.join(vm_environment_injection_path, "injection_variables.txt"), "a") do |file|
        file.puts "VM_NAME=\"#{@vm_name}\""
        if branch.nil?
          file.puts "PR_NAME=\"#{pr["title"]}\""
          file.puts "BRANCH_NAME=\"#{pr["head"]["ref"]}\""
        else
          file.puts "PR_NAME=\"NA\""
          file.puts "BRANCH_NAME=\"#{branch}\""
        end
        file.puts "COMMIT_HASH=\"#{commit_hash}\""

        file.puts "TEST_FILE=\"#{test_file}\"" unless test_file.nil?
        file.puts "RUN_ONLY=true" if run_server == true
      end

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
