--[[
    Copyright 2020 Matthew Hesketh <matthew@matthewhesketh.com>
    This code is licensed under the MIT. See LICENSE for details.
]]

local feds = {}
local mattata = require('mattata')
local redis = require('libs.redis')

function feds:init()
    feds.commands = mattata.commands(self.info.username):command('feds').table
    feds.help = '/feds - Allows group admins to view the group\'s current Feds.'
end

function feds:on_message(message, configuration, language)
    if message.chat.type == 'private' then
        return mattata.send_reply(message, language.errors.supergroup)
    elseif not mattata.is_group_admin(message.chat.id, message.from.id) then
        return mattata.send_reply(message, language.errors.admin)
    end
    local all = redis:smembers('chat:' .. message.chat.id .. ':feds')
    if #all == 0 then
        local output = '<b>%s</b> isn\'t part of any Feds! To join one, use <code>/joinfed &lt;fed UUID&gt;</code>!'
        output = string.format(output, mattata.escape_html(message.chat.title))
        return mattata.send_reply(message, output, 'html')
    end
    local output = { '<b>' .. mattata.escape_html(message.chat.title) .. '</b> is part of the following Feds:' }
    for _, fed in pairs(all) do
        local formatted = mattata.symbols.bullet .. ' <em>%s</em> <code>[%s]</code>'
        local title = redis:hget('fed:' .. fed, 'title')
        formatted = string.format(formatted, mattata.escape_html(title), fed)
        table.insert(output, formatted)
    end
    output = table.concat(output, '\n')
    return mattata.send_reply(message, output, 'html')
end

return feds