class GithubWatcherJob
  include Sidekiq::Job

  def perform
    puts "Checking for new commits..."
    open_prs = GithubWrapper.get_open_prs
    open_prs.each do |pr|
      branch = GithubWrapper.get_branch_for_pr(pr)
      latest_commit_on_server = GithubWrapper.get_latest_commit_for_branch(branch)["sha"]
      latest_commit_locally = GithubWrapper.get_last_commit(branch)

      # Get number of running servers
      container_count = `prlctl list | grep -c "running"`.chomp.to_i
      # Skip unless there's less containers
      puts "Container Count: #{container_count}"
      if container_count >= 2
        puts "Waiting for a free space to test container"
        next
      end

      puts "Checking if #{latest_commit_locally} matches #{latest_commit_on_server} for #{branch}"
      next if latest_commit_locally == latest_commit_on_server

      # Make sure we don't run it again
      GithubWrapper.save_last_commit(branch, latest_commit_on_server)

      puts "Launching new CI testing instance for #{branch} with commit #{latest_commit_on_server}"
      puts "--------------------------------------------------------------------------------------"
      VMManager.clone_vm(pr, latest_commit_on_server)
    end

    # Reschedule this again in a few seconds
    GithubWatcherJob.perform_in(30)
  end
end
