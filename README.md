# Grigori
- "Watcher" in Ancient Greek via Biblical Hebrew

## Purpose
A self-hosted CI server for the [Hypaia](https://www.github.com/techancheck/hypatia) project. The reason we implement this ourselves instead of something like Jenkis or whatever is because we need to be able to run it in a desktop environment for the Chrome runners.

Unfortunately for our purposes a headless browser won't do, and since running the test locally is a HUGE pain and take the better part of an hour, we wrote this up.

## Requirements
We use Parallels for MacOS to handle the creation and management of the virtual machines, so we're currently limited to the Apple platform. This could theoretically be redone using QEMU, which would be awesome, but also a lot of work and I have a spare Macbook laying around.

- MacOS 12.5.1 (or latest version)
- Parallels Desktop 18 Business Edition (you need this version for the CLI)
- Ruby 3.1.2 or greater
- Redis
- A base Parallels image for this all to run (From @cguess most likely)

## Setup
These will be quite general, if you don't know how to follow one of these steps on your own this is not the project for you. Trust me, it's not what you need.

1. Install Ruby (I like rbenv)
1. Install Redis
1. Install Parallels
1. Ask @cguess for the base image and add it to Parallels
1. Duplicate `injection_variables.txt.sample` and name it `injection_variables.txt`
1. Add your appropriate Hypatia `.env` setup to the `injection_variables.txt`, this will be copied into every test run
1.


TODO!!!!!
Remove injection_variables.txt from commit history

