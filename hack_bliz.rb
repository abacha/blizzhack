#!/usr/bin/env ruby

require "rubygems"
require "eventmachine"
require "amqp"
require "eventmachine-tail"
require "mechanize"

class MechanizeRunner
  URL = "https://us.battle.net/account/management/add-game.html?gameKey="
  def initialize(connection)
    init_amqp(connection)
    login
    init_hashing
  end

  def init_amqp(connection)
    @connection = connection
    @channel = AMQP::Channel.new(connection)
    @queue = @channel.queue("zeh").bind("blizzard.keys")
    @queue.subscribe &method(:receive)
  end

  def init_hashing
    options_chars = ('A'..'Z').to_a
    options_nums = ('0'..'9').to_a
    @chars_ary = (options_chars + options_nums).shuffle.each_slice(4).to_a
  end

  def attempt(key, char)
    attempted_key = key.gsub("?", char)
    page = @agent.get(URL + attempted_key)
    puts "CLAIMED! (#{attempted_key})" if page.content.include? "has already been claimed"
    puts "SUCCESS! (#{attempted_key})" if page.content.include? "Success!"
  end

  def login
    @agent = Mechanize.new
    page = @agent.get("http://us.battle.net/login")
    form = page.form
    form.accountName = ENV["WOWMAIL"]
    form.password = ENV["WOWPASS"]
    @agent.submit(form, form.buttons.first)
    puts "logged in!"
  end

  def test_group(key, group)
    EM.defer do
      puts "\nThread: #{Thread.current} - Group: #{group}"
      group.each do |char|
        attempt(key, char)
      end
    end
  end
  
  def receive(payload)
    puts "Got: #{payload}"
    key = payload.strip.chomp
    @chars_ary.each do |group|
      test_group(key, group)
    end
  end
end

class FileHandler < EM::FileTail
  def initialize(path, connection)
    super path
    @connection = connection
    @channel = AMQP::Channel.new(connection)
    @exchange = @channel.fanout("blizzard.keys")
  end

  def receive_data(data)
    @exchange.publish(data, :key => 'keys') do
      puts "Published: #{data}"
    end
  end
end

EM.run do
  AMQP.connect do |connection|
    EM.file_tail "/tmp/keys.txt", FileHandler, connection
    MechanizeRunner.new(connection)
  end
end
