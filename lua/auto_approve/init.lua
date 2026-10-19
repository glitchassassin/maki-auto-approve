local config = require("auto_approve.config")
local context = require("auto_approve.context")
local review = require("auto_approve.review")
local queue = require("auto_approve.queue")
local util = require("auto_approve.util")
local M = {}

function M.setup()
  local settings = config.register()
  require("auto_approve.inspect").setup()
  local evidence, results, generations = context.new(), {}, {}
  local reviews = queue.new(settings.reviewer.max_concurrent)
  local function identity(sid, task, req)
    return "session=" .. util.clean(sid, 200) .. " task=" .. util.clean(task or "unknown", 200)
      .. " tool_call_id=" .. util.clean(req.tool_id or "unknown", 200)
      .. " tool=" .. util.clean(req.tool, 100)
  end
  local function log(sid, task, req, status, reason)
    maki.log.info("auto-approve: " .. identity(sid, task, req) .. ": " .. status
      .. (reason and (" — " .. util.clean(reason, 400)) or ""))
  end
  local function remember(sid, task, req, status, reason, assessment, limit)
    local records = results[sid] or {}
    records[#records + 1] = { tool = req.tool, tool_id = req.tool_id, task_id = task,
      status = status, reason = util.clean(reason, 1000),
      risk = assessment and assessment.risk_level, authorization = assessment and assessment.user_authorization }
    while #records > (limit or 50) do table.remove(records, 1) end
    results[sid] = records
    local message = tostring(req.tool) .. ": " .. status .. " — " .. util.clean(reason, 400)
    log(sid, task, req, status, reason)
    if status ~= "approved" then maki.notify(message, "info", { title = "Auto-approve" }) end
  end

  maki.api.set_slot("agent.user_message", function(prev, message, ctx)
    -- Invalidate pending decisions immediately, even before history is updated.
    evidence.observe(ctx.session_id, message.text, message.source, message.images)
    return prev(message, ctx)
  end)
  maki.api.create_autocmd({ "SessionReset", "SessionEnd" }, {
    callback = function(ev)
      local sid = ev.data.session_id
      evidence.clear(sid)
      generations[sid] = (generations[sid] or 0) + 1
      results[sid] = nil
    end,
  })

  -- Only this slot grants approval: native allow/deny/YOLO decisions have already
  -- resolved, and explicit human-only escalations never enter the slot.
  maki.api.set_slot("permission.prompt", function(prev, req, ctx)
    local sid = ctx:session_id()
    if not sid then return prev(req, ctx) end
    req = util.copy(req)
    local task, generation = ctx:task_id(), generations[sid]
    local cfg, error_text, ticket
    local accepted, completed = false, false
    local assessment
    local ok, thrown = pcall(function()
      cfg = util.copy(settings)
      maki.async.on_cancel(function(reason)
        if not completed then
          log(sid, task, req, reason == "timeout" and "hook timed out" or "cancelled")
        end
      end)
      ticket = reviews.ticket(cfg.reviewer.timeout_ms)
      if not ticket.acquire(function() log(sid, task, req, "queued") end) then
        error_text = ticket.error(); return
      end
      local function stopped()
        error_text = ticket.error()
        if ctx:cancelled() then error_text = "Review cancelled." end
        if generations[sid] ~= generation then error_text = "Session ended or reset while awaiting review." end
        return error_text ~= nil
      end
      if stopped() then return end
      log(sid, task, req, "started")
      local cwd = util.cwd(sid)
      cfg.root = maki.fs.root(cwd, ".git") or cwd
      if stopped() then return end
      local prompt, build_err, proof = evidence.build(sid, task, req, cfg)
      if not prompt then error_text = build_err; return end
      if stopped() then return end
      local ran, value, run_err = pcall(review.run, ctx, cfg, prompt, cwd, req.tool_id, ticket)
      if not ran then error_text = "Review failed: " .. tostring(value); return end
      assessment, error_text = value, run_err
      if not assessment or assessment.outcome ~= "allow" then return end
      local unchanged, changed_err = evidence.unchanged(sid, proof)
      if not unchanged then error_text = changed_err; return end
      -- Inspection and conversation reads may yield. No yield may occur between
      -- this final authorization/cancellation check and publishing the allow.
      if stopped() then return end
      if evidence.revision(sid) ~= proof.revision then error_text = "User instructions changed during review."; return end
      accepted = true
    end)
    if ticket then ticket.finish() end
    completed = true
    if not ok then error_text = "Review failed: " .. tostring(thrown) end
    local reason = error_text or (assessment and assessment.rationale) or "Review unavailable."
    remember(sid, task, req, accepted and "approved" or "human review", reason, assessment,
      cfg and cfg.logging.history_size)
    if accepted then return { decision = "allow" } end
    return prev(req, ctx)
  end)

  maki.api.register_command({
    name = "/auto-approve", description = "Show recent automatic approval decisions for this session",
    handler = function()
      local sid = maki.session.current()
      local records = results[sid] or {}
      local buf = maki.ui.buf({ scratch = true })
      buf:line("Auto-approve: recent decisions (oldest first)")
      if #records == 0 then buf:line("No reviews recorded in this session since the plugin loaded.") end
      for _, record in ipairs(records) do
        buf:line(record.tool .. ": " .. record.status .. (record.risk and (" [" .. record.risk .. ", authorization=" .. record.authorization .. "]") or ""))
        buf:line("  tool_call_id=" .. util.clean(record.tool_id or "unknown", 200)
          .. " task=" .. util.clean(record.task_id or "unknown", 200))
        buf:line("  " .. record.reason)
      end
      buf:line("Close: q or Esc")
      local win = maki.ui.open_win(buf, { title = "Auto-approve", width = "85%", height = "70%" })
      while true do
        local ev = win:recv()
        if not ev or ev.key == "q" or ev.key == "<Esc>" then break end
      end
      win:close()
    end,
  })
  return { context = evidence, results = results }
end

return M
