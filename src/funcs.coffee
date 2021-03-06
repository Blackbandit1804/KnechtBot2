main = require "./main.js"
mysql = require "mysql"
PushBullet = require "pushbullet"
fs = require 'fs'

# Getting bot instance from main script
bot = null
exports.setBot = (b) -> bot = b


###
Setting bots game with members stats.
"[...] membs ([...] online) | !help"
###
exports.setStatsGame = (guild) ->
    membs = online = 0
    membarr = guild.members.map (m) -> return m
    for m in membarr
        if !m.bot
            membs++
            if m.status != "offline"
                online++
    bot.editStatus {name: "#{membs} membs (#{online} online) | !help"}


###
Chekcing permission level of member.
Returns if max permsision level, the user has,
is bigger or even the required permission level.
###
exports.checkPerm = (memb, lvl, chan) ->
    maxperm = 0
    for rid in memb.roles
        if rid of main.perms
            perm = main.perms[rid]
            maxperm = if perm > maxperm then perm else maxperm
    if maxperm < lvl
        main.sendEmbed chan, """
                             You are not permitted to use this command!
                             *Required perm. lvl:   `#{lvl}`*
                             *Your perm. lvl:   `#{maxperm}`*
                             """, "Not permitted", main.color.red
    return maxperm >= lvl


###
Getting maximum permission level of user.
###
exports.getPerm = (memb) ->
    maxperm = 0
    for rid in memb.roles
        if rid of main.perms
            perm = main.perms[rid]
            maxperm = if perm > maxperm then perm else maxperm
    return maxperm


###
Adding bot and his owner to mySQL database.
Giving bot the userbot role and owner the bot owner role.
Also the bot will get a prefix in his nickname and the owner's 
name in parenthesis behind the name.
###
exports.addbot = (ubot, owner) ->
    main.dbcon.query 'SELECT * FROM userbots WHERE botid = ?', [ubot.id], (err, res) ->
        if typeof res != "undefined"
            return
    main.dbcon.query 'SELECT * FROM userbots WHERE ownerid = ?', [owner.id], (err, res) ->
        if typeof res != "undefined"
            return
    if !ubot.bot or owner.bot
        return
    main.dbcon.query 'INSERT INTO userbots (botid, ownerid, prefix) VALUES (?, ?, "UNSET")', [ubot.id, owner.id], (err, res) ->
        if !err
            ubot.edit {nick: "#{main.botprefix} #{ubot.username} (#{if owner.nick != null then owner.nick else owner.username})"}
            bot.addGuildMemberRole ubot.guild.id, ubot.id, "309622223285780481"
            bot.addGuildMemberRole owner.guild.id, owner.id, "324537251071787009"
            for u in main.inviteReceivers
                bot.getDMChannel(u)
                    .then (chan) ->
                        main.sendEmbed chan, "Bot unvite from #{owner.username} got accepted.", "BOT INVTE ACCEPTED", main.color.green
            bot.getDMChannel(owner.id)
                .then (chan) ->
                    main.sendEmbed chan, 
                                   """
                                   Your bot got accepted!

                                   Please now, register your bot's prefix with the `!prefix` command!
                                   **Bot's without an registered prefix will be kicked after 24 hours!**
                                   """, "BOT INVTE ACCEPTED", main.color.green
            setTimeout checkprefix, 22 * 3600 * 1000, ubot, false
            setTimeout checkprefix, 24 * 3600 * 1000, ubot, true


###
Just a little function for Timeout in 'exports.addbot' to send warning message
or kick a userbot if the prefix of the bot is not set in DB.
###
checkprefix = (ubot, kick) ->
    main.dbcon.query 'SELECT * FROM userbots WHERE botid = ?', [ubot.id], (err, res) ->
        if !err
            if res.length > 0
                console.log res[0].prefix, res[0].whitelisted
                if res[0].prefix == "UNSET" and res[0].whitelisted == 0
                    console.log ("prefix unset")
                    if kick
                        bot.kickGuildMember ubot.guild.id, ubot.id, "Bot prefix not registered"
                    else
                        bot.getDMChannel res[0].ownerid
                            .then (chan) -> main.sendEmbed chan, """
                                                                 Your bot's prefix is still unregistered!
                                                                 Please register a prefix as soon as possible with the `!prefix` command!
                                                                 Otherwise, **the bot will be kicked automatically from the guild in the next 2 hours!**
                                                                 """, "ATTENTION", main.color.red


###
If a bot gets kicked, this will remove its entry from mySQL databse
and will remove bot owner role from the user who was invited the bot.
If the kicked one is a member, which is also a bot owner on the guild,
all his bots will be unregistered and kicked from the guild.
###
exports.removebot = (ubot) ->
    ownerid = null
    if ubot.bot
        main.dbcon.query 'SELECT * FROM userbots WHERE botid = ?', [ubot.id], (err, res) ->
            if typeof res == "undefined"
                console.log "BOT NOT REGISTERED"
                return
            else if res.length == 0
                return
        main.dbcon.query 'SELECT * FROM userbots WHERE botid = ?', [ubot.id], (err, res) ->
            if !err and res != null
                ownerid = res[0].ownerid
                console.log "OWNER ID: #{ownerid}"
                main.dbcon.query 'DELETE FROM userbots WHERE botid = ?', [ubot.id], (err, res) ->
                    if !err
                        # checking again if the owner has any other registered bot. If not, he will lose
                        # the botowner role, else not.
                        main.dbcon.query 'SELECT * FROM userbots WHERE ownerid = ?', [ownerid], (err, res) ->
                            if !err and res.length == 0
                                bot.removeGuildMemberRole ubot.guild.id, ownerid, "324537251071787009"
    else
        main.dbcon.query 'SELECT * FROM userbots WHERE ownerid = ?', [ubot.id], (err, res) ->
            if typeof res == "undefined"
                return
            else if res.length == 0
                return
            else
                for row in res
                    bot.kickGuildMember ubot.guild.id, row.botid, "Bot owner left guild"
                main.dbcon.query 'DELETE FROM userbots WHERE ownerid = ?', [ubot.id]



###
Changes the nicknames of users if they get or lose a role
entered in main's 'exports.rolepres' map with the set
prefix.
Also adding and removing staff role.
###
exports.rolepres = (after, before) ->
    if before.roles.length < after.roles.length
        for r in after.roles
            if !(r in before.roles)
                if r of main.rolepres
                    after.edit {nick: "#{main.rolepres[r]} #{if after.nick != null then after.nick else after.username}"}
                    bot.addGuildMemberRole after.guild.id, after.id, "373081803487182849"
    else if before.roles.length > after.roles.length
        for r in before.roles
                if !(r in after.roles)
                    if r of main.rolepres
                        try after.edit {nick: "#{after.nick.substring 2, after.nick.length}"}
                        catch e then console.log e
                        bot.removeGuildMemberRole after.guild.id, after.id, "373081803487182849"


###
Changes xp in database for specific member.
Ammount can be positive as also negative.
###
exports.xpchange = (member, ammount) ->
    main.dbcon.query 'SELECT * FROM xp WHERE uid = ?', [member.id], (err, res) ->
        if !err and res.length == 0
            main.dbcon.query 'INSERT INTO xp (uid, xp) VALUES (?, ?)', [member.id, ammount]
        else if !err
            main.dbcon.query 'UPDATE xp SET xp = xp + ? WHERE uid = ?', [ammount, member.id]


###
Function for xp timer, which increases the xp value of
all online users of an ammount read out of config file
###
exports.xptimer = (val) ->
    guild = bot.guilds.find (g) -> true
    guild.members.filter (m) -> m.status != "offline"
        .forEach (m) ->
            exports.xpchange m, main.config["exp"]["xpinterval"]


###
Function to get current lvl, xp to next lvl
and progress from current total xp value.
###
exports.xpgetlvl = (xpval) ->
    start = main.config["exp"]["startlvl"]
    delta = main.config["exp"]["delta"]
    getreq = (x) -> if x == 0 then 0 else start * delta ** (x-1)
    lvl = 0
    while xpval > getreq(lvl)
        lvl++
    lvl = lvl-1
    nextlvl =   parseInt(xpval - getreq(lvl))
    nextlvln =  parseInt(getreq(lvl+1))
    nextlvlp =  parseInt((nextlvl / nextlvln) * 100)
    return [lvl, nextlvl, nextlvln, nextlvlp]


###
Just a simple logging function for commands in DB.
###
exports.log = (msg) ->
    memb = msg.member
    chan = msg.channel
    cont = msg.content
    main.dbcon.query 'INSERT INTO cmdlog (uid, uname, cmd, content, timestamp, chanid, channame) VALUES (?, ?, ?, ?, ?, ?, ?)', 
        [
            memb.id
            "#{memb.username}##{memb.discriminator}"
            cont.split(" ")[0]
            cont,
            main.getTime(),
            chan.id,
            chan.name
        ]


###
Edits a message in 'welcome' channel on my dev discord
to show there live all staff members, so this list
will be refreshed automatically if there is a new
staff member or if someone left staff.
###
exports.welcomeStaff = ->
    guild = bot.guilds.find (g) -> true
    membs = guild.members
    admins = sups = mods = ""
    owner = membs.find (m) -> m.id == guild.ownerID

    membs.filter((m) -> m.roles.filter((r) -> r == "307084714890625024").length > 0).forEach (m) -> admins += m.mention + "\n"
    membs.filter((m) -> m.roles.filter((r) -> r == "307084853155725312").length > 0).forEach (m) -> sups += m.mention + "\n"
    membs.filter((m) -> m.roles.filter((r) -> r == "353193585727766539").length > 0).forEach (m) -> mods += m.mention + "\n"

    emb =
        embed:
            description: ":diamond_shape_with_a_dot_inside:  **STAFF TEAM**\n\n*The responsible dudes for shit is going on on this guild. :^) <3*"
            color: main.color.gold
            fields: [
                {
                    name: "Owner"
                    value: owner.mention
                    inline: false
                }
                {
                    name: "Admins"
                    value: admins
                    inline: false
                }
                {
                    name: "Supporters"
                    value: sups
                    inline: false
                }
                {
                    name: "Moderators"
                    value: mods
                    inline: false
                }
            ]
    bot.editMessage "307085753744228356", "374574875572043776", emb


###
Handler for bot notification system, checking for bots going
offline and sending notification via discord DM and pushpullet
notification, if token was set with !nots command.
###
exports.notshandle = (after, presence) ->
    if after.bot and after.status == "offline" && presence.status != "offline"
        main.dbcon.query 'SELECT * FROM userbots WHERE botid = ?', [after.id], (err, res) ->
            if err
                return
            if res.length > 0
                if res[0].enabled == 1
                    ubot = after.guild.members.find (m) -> m.id = "#{res[0].botid}"
                    uname = if typeof ubot != "undefined" then ubot.username else "~invalid~"
                    bot.getDMChannel res[0].ownerid
                        .then (chan) -> main.sendEmbed chan, "Your bot #{if typeof ubot == "undefined" then "*invalid*" else ubot.mention} (`#{uname}`) just went offline!", "Notification", main.color.red
                    if res[0].pbtoken != ""
                        push = new PushBullet(res[0].pbtoken)
                        push.note {}, "BOT NOTIFICATION", "Your bot '#{uname}' just went offline!", (err, res) ->
                            if err
                                bot.getDMChannel res[0].ownerid
                                    .then (chan) -> main.sendEmbed chan, "Failed to send PushBullet message! Please check your entered token!", "Error", main.color.red


###
Sending welcome message to (new) member.
###
exports.welcome = (memb) ->
    guild = memb.guild
    bot.createMessage main.config.welcomechan, "<@#{memb.id}>"
        .then (m) -> bot.deleteMessage main.config.welcomechan, m.id


exports.createWelcMsg = ->
    if fs.existsSync 'welcid'
        cont = fs.readFileSync 'welcid', 'utf8'
        bot.deleteMessage main.config.welcomechan, cont
    emb =
        embed:
            description: "If you have read all of this, accept it with a reaction below and then you will get access to all public channels. ;)\n\n:point_down:"
            color: main.color.cyan
    bot.createMessage main.config.welcomechan, emb
        .then (m) -> 
            main.welcmsg = m
            m.addReaction main.config.checkemote
            fs.writeFile 'welcid', m.id


exports.welcMsgAccepted = (msg, emote, userid) ->
    if emote.name = main.config.checkemote
        bot.addGuildMemberRole msg.member.guild.id, userid, main.config.autorole, "Joined server and accepted rules"
        msg.removeReaction emote.name, userid