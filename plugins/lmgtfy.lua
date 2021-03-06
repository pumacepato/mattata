--[[
    Copyright 2020 Matthew Hesketh <matthew@matthewhesketh.com>
    This code is licensed under the MIT. See LICENSE for details.
]]

local lmgtfy = {}
local mattata = require('mattata')
local url = require('socket.url')
local redis = require('libs.redis')

function lmgtfy:init()
    lmgtfy.commands = mattata.commands(self.info.username):command('lmgtfy').table
    lmgtfy.help = '/lmgtfy [anything] - Helps that special someone out. Input can be given via an argument or using the replied-to person\'s message text.'
end

function lmgtfy:on_message(message)
    local input = mattata.input(message.text)
    if not input then
        if not message.reply then
            return mattata.send_reply(message, lmgtfy.help)
        end
        input = message.reply.text
    end
    if message.reply then
        message.message_id = message.reply.message_id -- if we're sending in reply to a reply, we need it to trick it!
    end
    input = 'https://lmgtfy.com/?q=' .. url.escape(input)
    local output = redis:get('chat:' .. message.chat.id .. ':lmgtfy') or 'Here you go, idiot.'
    output = mattata.escape_html(output)
    output = string.format('<a href="%s">%s</a>', input, output)
    if message.reply then
        return mattata.send_reply(message, output, 'html')
    end
    return mattata.send_message(message.chat.id, output, 'html')
end

return lmgtfy