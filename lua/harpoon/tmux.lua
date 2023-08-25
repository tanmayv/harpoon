local harpoon = require("harpoon")
local log = require("harpoon.dev").log
local global_config = harpoon.get_global_settings()
local utils = require("harpoon.utils")

local M = {}

if global_config.tmux_autoclose_windows then
    local harpoon_tmux_group = vim.api.nvim_create_augroup(
        "HARPOON_TMUX",
        { clear = true }
    )

    vim.api.nvim_create_autocmd("VimLeave", {
        callback = function()
            require("harpoon.tmux").clear_all()
        end,
        group = harpoon_tmux_group,
    })
end

local function create_terminal()
    log.trace("tmux: _create_terminal())")

    -- Create a new tmux window and store the window id
    local out, ret, err = utils.get_os_command_output({
        "tmux",
        "split-window",
        "-l",
        "20",
        "-P",
    }, vim.loop.cwd()) -- return session:windown.pane

    log.debug("create_terminal > "..vim.inspect(out), ret, err)
    if(ret == nil) then
        return nil
    end
    return out[1]
end

-- Checks if the tmux window with the given window id exists
local function terminal_exists(window_id) -- called with %pane_id
    log.trace("_terminal_exists(): Window:", window_id)

    if (window_id == nil) then
        return false
    end

    local _, ret, _ = utils.get_os_command_output({
        "tmux",
        "has-session",
        "-t",
        window_id,
    }, vim.loop.cwd())

    -- This has to be done this way because tmux has-session does not give
    -- updated results

    return ret ~= 1
end

local function find_terminal(id)
    log.trace("tmux: _find_terminal(): Window:", args)

    local window_exists = terminal_exists(id)

    if not window_exists then
        local window_id = create_terminal()

        if window_id == nil then
            error("Failed to find and create tmux window.")
            return nil
        end
        return window_id

    end
    return id
end

local function get_first_empty_slot()
    log.trace("_get_first_empty_slot()")
    for idx, cmd in pairs(harpoon.get_term_config().cmds) do
        if cmd == "" then
            return idx
        end
    end
    return M.get_length() + 1
end

function M.gotoTerminal(idx)
    log.trace("tmux: gotoTerminal(): Window:", idx)
    find_terminal(idx)

    local _, ret, stderr = utils.get_os_command_output({
        "tmux",
        "select-pane",
        "-t",
        M.active_pane,
    }, vim.loop.cwd())

    if ret ~= 0 then
        error("Failed to go to terminal." .. stderr[1])
    end
end

function M.sendCommand(idx, cmd, ...)
    log.trace("tmux: sendCommand(): Window:", idx)
    local id = M.active_pane
    if (type(idx) == "string") then
        id = idx
    end
    M.active_pane = find_terminal(id)

    if type(cmd) == "number" then
        cmd = harpoon.get_term_config().cmds[cmd]
    end

    if global_config.enter_on_sendcmd then
        cmd = cmd .. "\n"
    end

    if cmd then
        log.debug("sendCommand:", cmd)

        local job_cmd = {
            "tmux",
            "send-keys",
            "-t",
            M.active_pane,
            string.format(cmd, ...),
            "ENTER"
        }
        log.debug("============job_command================:", job_cmd)
        local _, ret, stderr = utils.get_os_command_output(job_cmd, vim.loop.cwd())

        if ret ~= 0 then
            error("Failed to send command. " .. stderr[1])
        else
            local _, ret, stderr = utils.get_os_command_output({
                "tmux",
                "select-pane",
                "-l",
            }, vim.loop.cwd())
        end
    end
end

function M.clear_all()
    log.trace("tmux: clear_all(): Clearing all tmux windows.")

    if M.active_pane then
        utils.get_os_command_output({
            "tmux",
            "kill-pane",
            "-t",
            M.active_pane
        }, vim.loop.cwd())
    end
end

function M.get_length()
    log.trace("_get_length()")
    return table.maxn(harpoon.get_term_config().cmds)
end

function M.valid_index(idx)
    if idx == nil or idx > M.get_length() or idx <= 0 then
        return false
    end
    return true
end

function M.emit_changed()
    log.trace("_emit_changed()")
    if harpoon.get_global_settings().save_on_change then
        harpoon.save()
    end
end

function M.add_cmd(cmd)
    log.trace("add_cmd()")
    local found_idx = get_first_empty_slot()
    harpoon.get_term_config().cmds[found_idx] = cmd
    M.emit_changed()
end

function M.rm_cmd(idx)
    log.trace("rm_cmd()")
    if not M.valid_index(idx) then
        log.debug("rm_cmd(): no cmd exists for index", idx)
        return
    end
    table.remove(harpoon.get_term_config().cmds, idx)
    M.emit_changed()
end

function M.set_cmd_list(new_list)
    log.trace("set_cmd_list(): New list:", new_list)
    for k in pairs(harpoon.get_term_config().cmds) do
        harpoon.get_term_config().cmds[k] = nil
    end
    for k, v in pairs(new_list) do
        harpoon.get_term_config().cmds[k] = v
    end
    M.emit_changed()
end

return M




