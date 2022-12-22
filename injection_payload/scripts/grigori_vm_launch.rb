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

  FileUtils.cp("/media/psf/env_injection_files/injection_variables.txt", "./.env")
  Dotenv.load("./.env") # Load the variables for use later in this script

  puts "_____________________________________________________"
  puts "         Checking out #{ENV["COMMIT_HASH"]}          "
  puts "_____________________________________________________"
  system("git checkout #{ENV["COMMIT_HASH"]}")

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
  system("wget -P /media/psf/env_injection_files/ https://github.com/SeleniumHQ/selenium/releases/download/selenium-4.5.0/selenium-server-4.5.0.jar")
  system("java -jar /media/psf/env_injection_files/selenium-server-4.5.0.jar hub > /media/psf/env_injection_files/logs/selenium-hub.log &")
  system("java -jar /media/psf/env_injection_files/selenium-server-4.5.0.jar node --port 5555 --session-timeout 10000 --drain-after-session-count 0 > /media/psf/env_injection_files/logs/selenium-node_1.log &")
  system("java -jar /media/psf/env_injection_files/selenium-server-4.5.0.jar node --port 5556 --session-timeout 10000 --drain-after-session-count 0 > /media/psf/env_injection_files/logs/selenium-node_2.log &")

  puts "-----------------------------------------------------"
  puts "                 Start Sidekiq                       "
  puts "-----------------------------------------------------"

  system("bundle exec sidekiq -c 1 > /media/psf/env_injection_files/logs/sidekiq.log &")

  if ENV["RUN_ONLY"].nil? == false
    puts "-----------------------------------------------------"
    puts "                 Starting Server                     "
    puts "-----------------------------------------------------"

    auth_code = `rails r "puts Setting.generate_auth_key"`.split.last
    puts "******"
    puts "URL: http://grigori-reporterslab.pagekite.me"
    puts "Auth Code: #{auth_code}"
    puts "******"

    system("rails s > /media/psf/env_injection_files/logs/rails_server.log &")
    system("python3 ~/pagekite.py")
    return
  end

  puts "-----------------------------------------------------"
  puts "                 Starting Tests                      "
  puts "-----------------------------------------------------"

  if ENV["TEST_FILE"].nil?
    test_result = system("rails test > /media/psf/env_injection_files/logs/rails_test.log")
  else
    test_result = system("rails test #{ENV["TEST_FILE"]} > /media/psf/env_injection_files/logs/rails_test.log")
  end
  # test_result = true

  # get test_result to determine if any tests failed
  status_code = test_result == true ? 200 : 400
  status_message = test_result == true ? "Success" : "Failed"

  # Send notification that something failed
  request = Typhoeus::Request.new("http://10.211.55.2:2345/tests_completed",
  headers: { "Content-Type": "application/json" },
  method: :post,
  body: { vm_id: ENV["VM_NAME"], status_code: status_code, status_message: status_message }.to_json)

  request.run
  response = request.response
  puts response.code
  puts response.total_time
  puts response.headers
  puts response.body

rescue StandardError => e
  # Send this back to the main manager
  status_message = "Error running tests: #{e.inspect}"

  Typhoeus.post("http://10.211.55.2:2345/tests_completed",
  headers: { "Content-Type": "application/json" },
  body: { vm_id: ENV["VM_NAME"], status_code: 500, status_message: status_message }.to_json)

  # SEnd to slack  https://github.com/slack-ruby/slack-ruby-client
  # Pull the user name from slack and tag them in the slack message even?
  # Should we add a failing comment to the PR?
end
