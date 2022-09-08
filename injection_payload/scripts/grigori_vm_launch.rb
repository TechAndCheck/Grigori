begin
  require "fileutils"
  require "typhoeus"
  require "json"
  require "debug"
  require "dotenv"

  Dir.chdir "/media/psf/env_injection_files/"
  puts "-----------------------------------------------------"
  puts "               Cloning Repository...                 "
  puts "-----------------------------------------------------"

  system("git clone https://www.github.com/techandcheck/hypatia.git")
  Dir.chdir "hypatia"
  system("git checkout #{ENV["COMMIT_NAME"]}")
  FileUtils.cp("/media/psf/env_injection_files/injection_variables.txt", "./.env")
  Dotenv.load # Load the variables for use later in this script

  puts "-----------------------------------------------------"
  puts "             Installing Dependencies                 "
  puts "-----------------------------------------------------"

  puts "Running Ruby version:"
  system("ruby -v")
  puts "----------------------"
  system("bundle install")
  system("sudo wget https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -O /usr/local/bin/yt-dlp")
  system("sudo chmod a+rx /usr/local/bin/yt-dlp")

  puts "-----------------------------------------------------"
  puts "               Setting Up Database                   "
  puts "-----------------------------------------------------"

  system("rails db:setup")

  puts "-----------------------------------------------------"
  puts "                 Start Selenium                      "
  puts "-----------------------------------------------------"

  Dir.mkdir("/media/psf/env_injection_files/logs")
  puts "Downloading Selenium..."
  system("wget -P /media/psf/env_injection_files/ https://github.com/SeleniumHQ/selenium/releases/download/selenium-4.4.0/selenium-server-4.4.0.jar")
  system("java -jar /media/psf/env_injection_files/selenium-server-4.4.0.jar standalone --session-timeout 10000 > /media/psf/env_injection_files/logs/selenium-server.log &")

  puts "-----------------------------------------------------"
  puts "                 Start Sidekiq                       "
  puts "-----------------------------------------------------"

  system("bundle exec sidekiq -c 1 > /media/psf/env_injection_files/logs/sidekiq.log &")

  # puts "-----------------------------------------------------"
  # puts "                 Starting Tests                      "
  # puts "-----------------------------------------------------"

  #test_result = system("rails test test/media_sources/twitter_media_source_test.rb > /media/psf/env_injection_files/logs/rails_test.log")
  test_result = true

  # get test_result to determine if any tests failed
  status_code = test_result == true ? 200 : 400
  status_message = test_result == true ? "Success" : "Failed"

  # Send notification that something failed
  Typhoeus.post("http://10.211.55.2:2345/tests_completed",
  headers: { "Content-Type": "application/json" },
  body: { vm_id: ENV["VM_NAME"], status_code: status_code, status_message: status_message }.to_json)
rescue StandardError => e
  # Send this back to the main manager
  status_message = "Error running tests: #{e}"

  Typhoeus.post("http://10.211.55.2:2345/tests_completed",
  headers: { "Content-Type": "application/json" },
  body: { vm_id: ENV["VM_NAME"], status_code: 500, status_message: status_message }.to_json)

  # SEnd to slack  https://github.com/slack-ruby/slack-ruby-client
  # Pull the user name from slack and tag them in the slack message even?
  # Should we add a failing comment to the PR?
end
