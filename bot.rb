require 'discordrb'
require 'redis'
require 'pp'
require 'Faraday'

API_ENDPOINT = 'https://api.guildwars2.com'
ADMIN_CHANNEL = 'gw2verify-admin'
VERIFICATION_CHANNEL = 'verification'

@bot = Discordrb::Commands::CommandBot.new token: ENV['DISCORD_TOKEN'], prefix: '!'
@redis = Redis.new

def load_world_info  
  # First, let's check if info is saved in Redis
  worlds = @redis.get("worlds")
  if worlds.nil?
    # Grab information from API
    response = Faraday.get "#{API_ENDPOINT}/v2/worlds?ids=all"
    raise "Couldn't retrieve world info from API, status: #{response.status}" if response.status != 200
    
    @worlds = {}
    api_response = JSON.parse(response.body)
    api_response.each do |world|
      @worlds[world["id"]] = world["name"]
    end
    
    @redis.set("worlds", @worlds.to_json)
  else
    @worlds = JSON.parse(worlds)
  end
end

def server_initialized?(server_id)
  info = @redis.get("server_#{server_id}")
  return !info.nil?
end

def add_account(server_id, account_id, key)
  # Check if key is valid
  response = Faraday.get "#{API_ENDPOINT}/v2/account?access_token=#{key}"
  raise "Couldn't retrieve account information. Check API key or try again later." if response.status != 200
  
  @redis.set("account_#{account_id}", key)
  
  # Set roles for current Discord server
  
  # Reset managed roles
  
  # If guild is set, set appropiate guild
  
  # Set role for server
end

def reset_roles(server_id, account_id)
  # If guild is set, reset guild role
  
  # Reset server roles
end

@bot.ready do |event|
  puts "Logged in as #{@bot.profile.username} (ID:#{@bot.profile.id}) | #{@bot.servers.size} servers"
end

@bot.command :guild do |event, *args|
  return if event.channel.nil? || event.channel.name != ADMIN_CHANNEL
  
  if args.length == 0
    return
  end
  
  # Adding a guild
  # Make sure a role is set up for this guild
  
  # Set config
  
end

@bot.command :servers do |event, *args|
  return if event.channel.nil? || event.channel.name != ADMIN_CHANNEL
  
  if args.length == 0
    return
  end
  
  if args[0] == "add"
    # Make sure role is set up for this server
  elsif args[0] == "remove"
  end
  
end

@bot.command :refresh do |event, *args|
  return if event.channel.nil? || event.channel.name != ADMIN_CHANNEL
  
  # For all users on discord server...
  
  # Remove managed roles
  # Add guild role if part of guild
  # Add applicable server role
end

@bot.command :verify do |event, *args|
  return if event.channel.nil? || event.channel.name != VERIFICATION_CHANNEL
  
  if !server_initialized?(event.channel.server.id)
    # TODO remove user's post
    event.respond "Admin has not configured verify bot"
    return
  end
  
  if args.length != 1
    # TODO remove user's post
    event.respond "Invalid command"
    return
  end
  
  begin
    add_account(event.author.id, args[0])
    # TODO remove user's post
    event.respond "API key added successfully."
  rescue => e
    event.respond e.message
  end
end

load_world_info

@bot.run
