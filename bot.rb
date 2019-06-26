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
      @worlds[world["id"]] = world["name"].gsub(/ \[.*$/, "")
    end
    
    @redis.set("worlds", @worlds.to_json)
  else
    @worlds = JSON.parse(worlds)
  end
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

# Maps role name to role id
def get_server_roles(server_id)
  roles = JSON.parse(Discordrb::API::Server.roles(@bot.token, server_id))
  result = {}
  roles.each do |role|
    result[role["name"]] = role["id"]
  end
  return result
end

def reset_roles(server_roles, server_id, account_id, guild)
  begin
    member_info = JSON.parse(Discordrb::API::Server.resolve_member(@bot.token, server_id, account_id))
    roles = member_info["roles"]
    # If guild is set, remove guild role
    unless guild.nil?
      role_id = server_roles[guild]
      roles = roles - [role_id] unless role_id.nil?
    end

    # Remove server roles
    @worlds.each_value do |world|
      role_id = server_roles[world]
      roles = roles - [role_id] unless role_id.nil?
    end
    
    # Update user
    Discordrb::API::Server.update_member(@bot.token, server_id, account_id, roles: roles)
  rescue => e
    # TODO print error to admin channel
    throw e
  end
end

def initial_server_info(name)
  return {
    "name" => name,
    "guild" => nil
  };
end

@bot.ready do |event|
  puts "Invite URL: #{@bot.invite_url}"
  puts "Logged in as #{@bot.profile.username} (ID:#{@bot.profile.id}) | #{@bot.servers.size} servers"
end

@bot.command :guild do |event, *args|
  return if event.channel.nil? || event.channel.name != ADMIN_CHANNEL
  
  if args.length == 0
    server_info = @redis.get("server_#{event.channel.server.id}")
    if server_info.nil?
      event.respond "No Guild Set"
    else
      server_info = JSON.parse(server_info)
      if server_info["guild"].nil?
        event.respond "No Guild Set"
      else
        event.respond "Server guild: [#{server_info["guild"]["tag"]}] #{server_info["guild"]["name"]}"
      end
    end
    
    return
  end
  
  # Get guild information from API
  response = Faraday.get "#{API_ENDPOINT}/v2/guild/search?name=#{args.join(" ")}"
  if response.status != 200
    event.respond "API Error. Please try again later."
    return
  end
  guild_ids = JSON.parse(response.body)
  if guild_ids.length == 0
    event.respond "Guild not found"
    return
  end
  
  response = Faraday.get "#{API_ENDPOINT}/v2/guild/#{guild_ids.first}"
  if response.status != 200
    event.respond "API Error. Please try again later."
    return
  end
  
  guild_info = JSON.parse(response.body)
  
  # Get server info from Redis
  server_info = @redis.get("server_#{event.channel.server.id}")
  server_info = server_info.nil? ? initial_server_info(event.channel.server.name) : JSON.parse(server_info)
  server_info["guild"] = {
    "id" => guild_info["id"],
    "tag" => guild_info["tag"],
    "name" => guild_info["name"]
  }
  @redis.set("server_#{event.channel.server.id}", server_info.to_json)
  event.respond "Server guild set to: [#{server_info["guild"]["tag"]}] #{server_info["guild"]["name"]}"
end

@bot.command :audit do |event, *args|
  return if event.channel.nil? || event.channel.name != ADMIN_CHANNEL
  
  # For all users on discord server...
  
  # Remove managed roles
  # Add guild role if part of guild
  # Add applicable server role
end

@bot.command :verify do |event, *args|
  return if event.channel.nil? || event.channel.name != VERIFICATION_CHANNEL
  
  if args.length != 1
    # TODO remove user's post
    event.respond "Invalid command"
    return
  end
  
  begin
    add_account(event.channel.server.id, event.author.id, args[0])
    # TODO remove user's post
    event.respond "API key added successfully."
  rescue => e
    event.respond e.message
  end
end

@bot.command :debug do |event, *args|
  roles = get_server_roles(event.channel.server.id)
  reset_roles(roles, event.channel.server.id, event.author.id, "Chewbacca")
  event.respond "pong"
end

load_world_info

@bot.run
