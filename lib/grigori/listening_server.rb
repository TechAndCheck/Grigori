require "thin"
require "sidekiq"
require "debug"
require "typhoeus"
require "slack"
require "zip"

class ListeningServer
  def initialize
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

    def perform(message)
      puts "*****************"
      puts "Received message: #{message}"
      puts "*****************"

      vm = VMManager.vm_for_id(message["vm_id"])
      raise "VM not found in our manager" if vm.nil?

      test_status_code = message["status_code"]
      test_status_message = message["status_message"]

      # if test_status_code == 200
      Slack.configure do |config|
        config.token = ENV["SLACK_TOKEN"]
      end

      client = Slack::Web::Client.new
      client.auth_test

      case test_status_code
      when 200
        slack_message = "#{message["vm_id"]}: Completed VM run successfully"
      when 500
        slack_message = "#{message["vm_id"]}: Internal Error in VM : #{test_status_message}"

        # Zip up our logs
        logs_directory = Shellwords.escape(File.join(".", ".vm_setup", message["vm_id"], "logs"))
        output_log_file = File.join(logs_directory, "logs.zip")
        log_entries = Dir.entries(logs_directory) - %w[. ..]

        ::Zip::File.open(output_log_file, create: true) do |zipfile|
          log_entries.each do |log_filename|
            zipfile.add(log_filename, File.join(logs_directory, Shellwords.escape(log_filename)))
          end
        end

      end

      client.chat_postMessage(
        channel: ENV["SLACK_NOTIFICATION_ROOM_ID"],
        text: slack_message
      )

      # Upload it
      client.files_upload(
        channels: ENV["SLACK_NOTIFICATION_ROOM_ID"],
        as_user: true,
        file: Faraday::UploadIO.new(output_log_file, "application/zip")
      ) unless output_log_file.nil?

      vm.shutdown_vm
      vm.delete_vm
    end
  end
end
