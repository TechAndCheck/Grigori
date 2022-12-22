require "singleton"

class SlackManager
  include Singleton

  attr_reader :slack_client

  def initialize
    # Slack.configure do |config|
    #   config.token = ENV["SLACK_TOKEN"]
    # end

    Slack::RealTime::Client.configure do |config|
      config.token = ENV["SLACK_API_TOKEN"]
    end

    @slack_client = Slack::RealTime::Client.new

    @slack_client.on :hello do
      puts "Successfully connected, welcome '#{client.self.name}' to the '#{client.team.name}' team at https://#{client.team.domain}.slack.com."
      @slack_client.ping
    end

    @slack_client.on :message do |data|
      case data.text
      when "bot hi" then
        @slack_client.web_client.chat_postMessage(channel: data.channel, text: "Hi <@#{data.user}>!")
      when /^bot/ then
        @slack_client.web_client.chat_postMessage(channel: data.channel, text: "Sorry <@#{data.user}>, what?")
      end
    end

    @slack_client.on :close do |_data|
      puts "Client is about to disconnect"
    end

    @slack_client.on :closed do |_data|
      puts "Client has disconnected successfully!"
    end

    # @slack_client.start!
  end

  def self.send_message(**kwargs)
    self.instance.slack_client.web_client.chat_postMessage(**kwargs)
  end

  def self.send_file(file_name, initial_comment = nil)
    Typhoeus.post("https://slack.com/api/files.upload",
      headers: { "Content-Type": "multipart/form-data",
                 "Authorization": "Bearer #{ENV["SLACK_API_TOKEN"]}" },
      body: {
        file: File.open(file_name, "r"),
        initial_comment: initial_comment,
        channels: ENV["SLACK_NOTIFICATION_ROOM_ID"] })
  end

  def self.user_for_email_address(email_address)
    email_address = email_address.downcase
    request = Typhoeus.get("https://slack.com/api/users.list",
      headers: { "Authorization": "Bearer #{ ENV["SLACK_API_TOKEN"] }" })
    response = JSON.parse(request.response_body)
    index = response["members"].find_index do |member|
      member["profile"]["email"].downcase == email_address unless member["profile"]["email"].nil?
    end

    return if index.nil?
    response["members"][index]["profile"]
  end
end
