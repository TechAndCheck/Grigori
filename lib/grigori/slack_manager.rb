require "singleton"

class SlackManager
  include Singleton

  attr_reader :slack_client

  def initialize
    Slack.configure do |config|
      config.token = ENV["SLACK_TOKEN"]
    end

    @slack_client = Slack::RealTime::Client.new

    @slack_client.on :hello do
      puts "Successfully connected, welcome '#{client.self.name}' to the '#{client.team.name}' team at https://#{client.team.domain}.slack.com."
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

    @slack_client.start!
  end

  def self.send_message(**kwargs)
    self.instance.slack_client.web_client.chat_postMessage(**kwargs)
  end
end
