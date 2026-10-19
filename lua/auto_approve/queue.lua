local M = {}

-- Await callbacks only wake coroutines; they never run a waiter inline. Reserve
-- its slot before waking it, so new arrivals cannot overtake queued requests.
function M.new(limit)
  local active, waiting = 0, {}
  local queue = {}

  function queue.ticket(timeout_ms)
    local ticket = { expired = false, cancelled = false, held = false, finished = false }
    local timer, wake, on_timeout
    local function signal(value)
      local callback = wake
      wake = nil
      if callback then callback(value) end
    end
    local function remove()
      for i, entry in ipairs(waiting) do
        if entry == ticket then table.remove(waiting, i); break end
      end
    end
    function ticket.finish()
      if ticket.finished then return end
      ticket.finished = true
      if timer then timer:cancel() end
      remove()
      signal(false)
      if not ticket.held then return end
      ticket.held = false
      active = active - 1
      local next_ticket = table.remove(waiting, 1)
      if next_ticket then next_ticket.grant() end
    end
    function ticket.grant()
      ticket.held = true
      active = active + 1
      signal(true)
    end
    function ticket.acquire(on_wait)
      if ticket.finished or ticket.expired then return false end
      if active < limit then ticket.grant(); return true end
      if on_wait then on_wait() end
      return maki.async.await(1, function(callback)
        wake = callback
        waiting[#waiting + 1] = ticket
      end)
    end
    function ticket.on_timeout(callback)
      on_timeout = callback
      if ticket.expired and callback then callback() end
    end
    function ticket.error()
      if ticket.cancelled then return "Review cancelled." end
      if ticket.expired then
        return ticket.held and "Review timed out; human approval is required."
          or "Review timed out while queued; human approval is required."
      end
    end
    maki.async.on_cancel(function()
      ticket.cancelled = true
      ticket.finish()
    end)
    if not ticket.finished then
      timer = maki.async.spawn(function()
        maki.async.sleep(timeout_ms)
        ticket.expired = true
        remove()
        signal(false)
        if on_timeout then on_timeout() end
      end)
    end
    return ticket
  end
  return queue
end

return M
