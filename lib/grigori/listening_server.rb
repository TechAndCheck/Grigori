require "thin"
require "sidekiq"
require "debug"
require "typhoeus"
require "slack"
require "zip"
require "dotenv"

class ListeningServer
  def initialize
    Thin::Server.start("0.0.0.0", 2345) do
      use Rack::CommonLogger
      use Rack::ShowExceptions
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

      # Verify that we have a VM with that name running

      if VMManager.vm_exist?(vm_id)
        return_code = 200
        return_body = "OK"
        FinishedTestsJob.perform_async(body)
      else
        return_code = 404
        return_body = "#{vm_id} not found"
      end

      [
        return_code,
        { "Content-Type" => "text/plain" },
        [return_body]
      ]
    end
  end

  class FinishedTestsJob
    include Sidekiq::Job
    Dotenv.load

    def initialize
      # if test_status_code == 200
      Slack.configure do |config|
        config.token = ENV["SLACK_TOKEN"]
      end

      @@slack_client = Slack::Web::Client.new
    end

    def perform(message)
      puts "*****************"
      puts "Received message: #{message}"
      puts "*****************"

      vm = VMManager.vm_for_id(message["vm_id"])
      raise "VM not found in our manager" if vm.nil?

      test_status_code = message["status_code"]
      test_status_message = message["status_message"]

      begin
        case test_status_code
        when 200
          send_success_to_slack(message["vm_id"])
        when 400, 500
          send_failure_to_slack(message["vm_id"], test_status_message)
        else
          send_failure_to_slack(message["vm_id"], test_status_message)
        end
      rescue StandardError => e
        puts "Error submitting to Slack: #{e.inspect}"
      end

      vm.shutdown_vm
      vm.delete_vm
    end

    def send_success_to_slack(vm_id)
      vm = VMManager.vm_for_id(vm_id)
      commiter = GithubWrapper.get_user_for_commit(vm.commit_hash)
      slack_user = SlackManager.user_for_email_address(commiter.email)

      SlackManager.send_message(
        channel: ENV["SLACK_NOTIFICATION_ROOM_ID"],
        text: "#{vm_id}: Completed VM run successfully",
        blocks: [
          {
            type: "header",
            text: {
              type: "plain_text",
              text: "Tests Finished Successfully"
            }
          },
          {
            type: "section",
            text: {
              type: "mrkdwn",
              text: "#{slack_user.nil? ? nil : "@#{slack_user["name"]}: "}Your tests have completed successfully! Good job! 🤘"
            }
          },
          {
            type: "section",
            text: {
              type: "mrkdwn",
              text: "*Date/Time*\n#{Time.now.utc.strftime("%Y-%m-%d %k:%M:%S %Z")}  |  #{Time.now.strftime("%Y-%m-%d %k:%M:%S %Z")}"
            }
          },
          {
            type: "divider"
          },
                   {
            type: "section",
            fields: [
              {
                type: "mrkdwn",
                text: "*Branch Name*\n`#{vm.branch}`"
              },
              {
                type: "mrkdwn",
                text: "*Commit SHA*\n`#{vm.commit_hash}`"
              }
            ]
          },
          {
            type: "section",
            fields: [
              {
                type: "mrkdwn",
                text: "*Committer Name*\n`#{commiter.name}`"
              },
              {
                type: "mrkdwn",
                text: "*Committer Email*\n`#{commiter.email}`"
              }
            ]
          },
          {
            type: "divider"
          },
          {
            type: "section",
            text: {
              type: "mrkdwn",
              text: "*VM Id*\n`#{vm_id}`"
            }
          },
          {
            type: "divider"
          },
        ]
      )
    end

    def send_failure_to_slack(vm_id, test_status_message)
      vm = VMManager.vm_for_id(vm_id)
      commiter = GithubWrapper.get_user_for_commit(vm.commit_hash)
      slack_user = SlackManager.user_for_email_address(commiter.email)

      SlackManager.send_message(
        channel: ENV["SLACK_NOTIFICATION_ROOM_ID"],
        text: "#{vm_id}: Internal Error in VM : #{test_status_message}",
        blocks: [
          {
            type: "header",
            text: {
              type: "plain_text",
              text: "Tests Failed"
            }
          },
          {
            type: "section",
            text: {
              type: "mrkdwn",
              text: "#{slack_user.nil? ? "A" : "@#{slack_user["name"]}: Your"} test run failed, sorry about that 🐸"
            }
          },
          {
            type: "section",
            text: {
              type: "mrkdwn",
              text: "*Date/Time*\n#{Time.now.utc.strftime("%Y-%m-%d %k:%M:%S %Z")}  |  #{Time.now.strftime("%Y-%m-%d %k:%M:%S %Z")}"
            }
          },
          {
            type: "section",
            text: {
              type: "mrkdwn",
              text: "*Failure Message*\n#{test_status_message}"
            }
          },
          {
            type: "divider"
          },
          {
            type: "section",
            fields: [
              {
                type: "mrkdwn",
                text: "*Branch Name*\n`#{vm.branch}`"
              },
              {
                type: "mrkdwn",
                text: "*Commit SHA*\n`#{vm.commit_hash}`"
              }
            ]
          },
          {
            type: "section",
            fields: [
              {
                type: "mrkdwn",
                text: "*Committer Name*\n`#{commiter.name}`"
              },
              {
                type: "mrkdwn",
                text: "*Committer Email*\n`#{commiter.email}`"
              }
            ]
          },
          {
            type: "divider"
          },
          {
            type: "section",
            text: {
              type: "mrkdwn",
              text: "*VM Id*\n`#{vm_id}`"
            }
          },
          {
            type: "divider"
          },
        ]
      )

      output_log_file = prepare_logs_for_slack(vm_id)

      SlackManager.send_file(output_log_file, "Logs for #{vm_id}")
    end

    def prepare_logs_for_slack(vm_id)
      # Zip up our logs
      logs_directory = Shellwords.escape(File.join(".", ".vm_setup", vm_id, "logs"))
      output_log_file = File.join(logs_directory, "logs_#{vm_id}.zip")
      log_entries = Dir.entries(logs_directory) - %w[. ..]

      ::Zip::File.open(output_log_file, create: true) do |zipfile|
        log_entries.each do |log_filename|
          zipfile.add(log_filename, File.join(logs_directory, Shellwords.escape(log_filename)))
        end
      end

      output_log_file
    end
  end
end
