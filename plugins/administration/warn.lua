--[[
    Copyright 2020 Matthew Hesketh <matthew@matthewhesketh.com>
    This code is licensed under the MIT. See LICENSE for details.
]]

local warn = {}
local mattata = require('mattata')
local redis = require('libs.redis')

function warn:init()
    warn.commands = mattata.commands(self.info.username):command('warn').table
    warn.help = '/warn [user] - Warns a user in the current chat. This command can only be used by moderators and administrators of a supergroup. Once a user has reached the maximum allowed number of warnings allowed in the chat, the configured action for the chat is performed on them.'
end

function warn.on_callback_query(_, callback_query, message, configuration)
    if not callback_query
    or not callback_query.data
    or not callback_query.data:match('^%a+%:%-%d+%:%d+$')
    then
        return
    elseif not mattata.is_group_admin(
        callback_query.data:match('^%a+%:(%-%d+)%:%d+$'),
        callback_query.from.id
    )
    then
        return mattata.answer_callback_query(
            callback_query.id,
            configuration.errors.admin
        )
    elseif callback_query.data:match('^reset%:%-%d+%:%d+$')
    then
        local chat_id, user_id = callback_query.data:match('^reset%:(%-%d+)%:(%d+)$')
        redis:hdel(
            string.format(
                'chat:%s:%s',
                chat_id,
                user_id
            ),
            'warnings'
        )
        return mattata.edit_message_text(
            message.chat.id,
            message.message_id,
            string.format(
                '<pre>Warnings reset by %s%s!</pre>',
                callback_query.from.username
                and '@'
                or '',
                callback_query.from.username
                or mattata.escape_html(callback_query.from.first_name)
            ),
            'html'
        )
    elseif callback_query.data:match('^remove%:%-%d+%:%d+$')
    then
        local chat_id, user_id = callback_query.data:match('^remove%:(%-%d+)%:(%d+)$')
        local amount = redis:hincrby(
            string.format(
                'chat:%s:%s',
                chat_id,
                user_id
            ),
            'warnings',
            -1
        )
        if tonumber(amount) < 0
        then
            redis:hincrby(
                string.format(
                    'chat:%s:%s',
                    chat_id,
                    user_id
                ),
                'warnings',
                1
            )
            return mattata.answer_callback_query(
                callback_query.id,
                'This user hasn\'t got any warnings to be removed!'
            )
        end
        return mattata.edit_message_text(
            message.chat.id,
            message.message_id,
            string.format(
                '<pre>Warning removed by %s%s! [%s/%s]</pre>',
                callback_query.from.username
                and '@'
                or '',
                callback_query.from.username
                or mattata.escape_html(callback_query.from.first_name),
                redis:hget(
                    string.format(
                        'chat:%s:%s',
                        chat_id,
                        user_id
                    ),
                    'warnings'
                ),
                redis:hget(
                    string.format(
                        'chat:%s:settings',
                        chat_id
                    ),
                    'max warnings'
                )
                or 3
            ),
            'html'
        )
    end
end

function warn:on_message(message, _, language)
    if message.chat.type ~= 'supergroup'
    then
        return mattata.send_reply(
            message,
            language['errors']['supergroup']
        )
    elseif not mattata.is_group_admin(
        message.chat.id,
        message.from.id
    )
    then
        return mattata.send_reply(
            message,
            language['errors']['admin']
        )
    end
    local reason = false
    local input = message.reply
    and tostring(message.reply.from.id)
    or mattata.input(message)
    if not input
    then
        return mattata.send_reply(
            message,
            warn.help
        )
    elseif not message.reply
    and input:match('^%@?%w+ ')
    then
        input, reason = input:match('^(%@?%w+) (.-)$')
    elseif mattata.input(message.text)
    then
        reason = mattata.input(message.text)
    end
    if tonumber(input) == nil
    and not input:match('^%@')
    then
        input = '@' .. input
    end
    local user = mattata.get_user(input)
    or mattata.get_chat(input) -- Resolve the username/ID to a user object.
    if not user
    then
        return mattata.send_reply(
            message,
            language['errors']['unknown']
        )
    elseif user.result.id == self.info.id
    then
        return
    end
    user = user.result
    local status = mattata.get_chat_member(
        message.chat.id,
        user.id
    )
    if not status
    then
        return mattata.send_reply(
            message,
            language['errors']['generic']
        )
    elseif mattata.is_group_admin(
        message.chat.id,
        user.id
    ) or status.result.status == 'creator'
    or status.result.status == 'administrator'
    then -- We won't try and warn moderators and administrators.
        return mattata.send_reply(
            message,
            'I cannot warn this user because they are a moderator or an administrator in this chat.'
        )
    elseif status.result.status == 'left'
    or status.result.status == 'kicked'
    then -- Check if the user is in the group or not.
        return mattata.send_reply(
            message,
            string.format(
                'I cannot warn this user because they have already %s this chat.',
                (
                    status.result.status == 'left'
                    and 'left'
                )
                or 'been kicked from'
            )
        )
    end
    local amount = redis:hincrby(
        string.format(
            'chat:%s:%s',
            message.chat.id,
            user.id
        ),
        'warnings',
        1
    )
    local maximum = redis:hget(
        string.format(
            'chat:%s:settings',
            message.chat.id
        ),
        'max warnings'
    )
    or 3
    if tonumber(amount) >= tonumber(maximum)
    then
        local success = mattata.ban_chat_member(
            message.chat.id,
            user.id
        )
        if not success
        then -- Since we've ruled everything else out, it's safe to say if it wasn't a
        -- success then the bot isn't an administrator in the group.
            return mattata.send_reply(
                message,
                'I need to have administrative permissions in order to ban this user. Please amend this issue, and try again.'
            )
        end
    end
    mattata.increase_administrative_action(message.chat.id, user.id, 'warns')
    reason = reason and ', for ' .. reason:gsub('^for ', '') or ''
    local admin_username = mattata.get_formatted_user(message.from.id, message.from.first_name, 'html')
    local warned_username = mattata.get_formatted_user(user.id, user.first_name, 'html')
    if mattata.get_setting(message.chat.id, 'log administrative actions') then
        local log_chat = mattata.get_log_chat(message.chat.id)
        local output = '%s <code>[%s]</code> has warned %s <code>[%s]</code> in %s <code>[%s]</code>%s.\n%s %s'
        output = string.format(output, admin_username, message.from.id, warned_username, user.id, mattata.escape_html(message.chat.title), message.chat.id, reason, '#chat' .. tostring(message.chat.id):gsub('^-100', ''), '#user' .. user.id)
        mattata.send_message(log_chat, output, 'html')
    end
    if message.reply and mattata.get_setting(message.chat.id, 'delete reply on action') then
        mattata.delete_message(message.chat.id, message.reply.message_id)
        mattata.delete_message(message.chat.id, message.message_id)
    end
    local output = '%s has warned %s%s.'
    output = string.format(output, admin_username, warned_username, reason)
    local keyboard = mattata.inline_keyboard():row(
        mattata.row():callback_data_button(
            'Reset Warnings',
            string.format(
                'warn:reset:%s:%s',
                message.chat.id,
                user.id
            )
        ):callback_data_button(
            'Remove 1 Warning',
            string.format(
                'warn:remove:%s:%s',
                message.chat.id,
                user.id
            )
        )
    )
    return mattata.send_message(message.chat.id, output, 'html', true, false, nil, keyboard)
end

return warn