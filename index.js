const Discord = require("discord.js");
const gw2 = require("gw2-api");
const http = require("http");
const redis = require("redis");

const client = new Discord.Client();
const api = new gw2.gw2();
const redisClient = redis.createClient(process.env.REDIS_URL);

// Configuration variables
const role = "Auto Verified";
const guilds = JSON.parse(process.env.guildConfig);

api.setStorage(new gw2.memStore());

// For Heroku - open something to listen on env.PORT
http.createServer(function (req, res) {
  res.writeHead(200, {'Content-Type': 'text/plain'});
  res.write('GW2 Verify Bot');
  res.end();
}).listen(process.env.PORT);

client.on("ready", () => {
  // This event will run if the bot starts, and logs in, successfully.
  console.log(`Bot has started, with ${client.users.size} users, in ${client.channels.size} channels of ${client.guilds.size} guilds.`); 
  // Example of changing the bot's playing game to something useful. `client.user` is what the
  // docs refer to as the "ClientUser".
  client.user.setActivity(`Serving ${client.guilds.size} servers`);
});

client.on("guildCreate", guild => {
  // This event triggers when the bot joins a guild.
  console.log(`New guild joined: ${guild.name} (id: ${guild.id}). This guild has ${guild.memberCount} members!`);
  client.user.setActivity(`Serving ${client.guilds.size} servers`);
});

client.on("guildDelete", guild => {
  // this event triggers when the bot is removed from a guild.
  console.log(`I have been removed from: ${guild.name} (id: ${guild.id})`);
  client.user.setActivity(`Serving ${client.guilds.size} servers`);
});

client.on("message", async message => {
  // This event will run on every single message received, from any channel or DM.
  
  // It's good practice to ignore other bots. This also makes your bot ignore itself
  // and not get into a spam loop (we call that "botception").
  if (message.author.bot) return;
  
  // Only respond to direct messages
  if (message.channel.type != "dm") return;
  
  const args = message.content.trim().split(/ +/g);
  const command = args.shift().toLowerCase();
  
  if (command === "ping") {
    // Calculates ping between sending a message and editing it, giving a nice round-trip latency.
    // The second ping is an average latency between the bot and the websocket server (one-way, not round-trip)
    const m = await message.channel.send("Ping?");
    m.edit(`Pong! Latency is ${m.createdTimestamp - message.createdTimestamp}ms. API Latency is ${Math.round(client.ping)}ms`);
  }

  if (command === "verify") {
    var operations = []; // Array of operations to wait for (Promises)
    
    if (args.length > 0) {
      const apiKey = args[0];
      api.setAPIKey(apiKey);
      api.getAccount().then(function (res) {
        var verified = false;
        if (res.guilds) {
          for (var guild in guilds) {
            const data = guilds[guild];
            if (res.guilds.includes(data.gw2Id)) {
              // Get guild configuration
              const discordGuild = client.guilds.get(data.discordId);
              if (discordGuild) {
                // Get discord role
                const discordRole = discordGuild.roles.find("name", role);
                if (discordRole) {
                  // Get discord member for the specific guild
                  const discordMember = discordGuild.members.get(message.author.id);
                  if (discordMember) {
                    const redisKey = guild + "_" + message.author.id;
                    operations.push(new Promise(function(resolve, reject) {
                      redisClient.set(redisKey, apiKey, function(err) {
                         if (!err) {
                           verified = true;
                           message.channel.send("Verified with guild: " + guild);
                           discordMember.addRole(discordRole).catch(console.error);
                         }
                         else {
                           console.error(err);
                         }
                         resolve();
                      });
                    }));
                  }
                }
              }
            }
          }
        }
      });
    }
    
    Promise.all(operations).then(function() {
      if (!verified)
        message.channel.send("Could not verify guild membership");
    });
  }
  
  if (command === "purge") {
    // This removes the 'auto-verified' role from users who are no longer in the guild.
    // If users have no role remaining, they are kicked from the discord
    
    var operations = []; // Array of operations to wait for (Promises)
    
    if (args.length > 0) {
      const guild = args[0];
      const data = guilds[guild];
      var success = false;

      if (data) {
        const discordGuild = client.guilds.get(data.discordId);
        if (discordGuild) {
          const discordMember = discordGuild.members.get(message.author.id);
          if (discordMember) {
            if (discordMember.hasPermission("KICK_MEMBERS")) {
              const prefix = guild + "_";
              operations.push(new Promise(function(resolve, reject) {
                redisClient.keys(prefix + "*", function (err, res) {
                  if (err) {
                    console.error(err);
                    resolve();
                    return;
                  }
                  
                  res.forEach(function(key) {
                    redisClient.get(key, function(err2, res2) {
                      if (err2) {
                        console.error(err2);
                        return;
                      }
                      
                      api.setAPIKey(res2);
                      // TODO: catch API failure vs. bad key
                      api.getAccount().then(function (gw2res) {
                        const discordMember = discordGuild.members.get(key.substring(prefix.length));
                        if (discordMember) {
                          if (gw2res.guilds) {
                            if (gw2res.guilds.includes(data.gw2Id)) {
                              const discordName = (discordMember.nickname != null) ?
                                    discordMember.nickname :
                                    discordMember.username + "." + discordMember.discriminator;
                              message.channel.send("Keeping " + gw2res.name + "(Discord: " + discordName + " ) in Discord.");
                            }
                            else {
                              message.channel.send("Removing " + role + " role from " + gw2res.name + " (Discord: " + discordName + " )");
                              discordMember.removeRole(discordRole).catch(console.error);
                            }
                          }
                        }
                        else {
                          message.channel.send(gw2res.name + " already removed from Discord - removing from database.");
                          redisClient.del(key);
                        }
                      });
                    });
                  });
                  
                  // TODO: kick members that have no role
                  // member.kick(reason).catch(console.error);
                  
                  success = true;
                  console.log(res);
                  console.log(err);
                  resolve();
                });
              }));
            }
            else {
              message.channel.send("You must have the KICK_MEMBERS permission to purge accounts.")
            }
          }
        }
      }
    }
    
    Promise.all(operations).then(function() {
      if (!success)
        message.channel.send("Could not purge guild accounts");
    }); 
  }
});

client.login(process.env.secret);
