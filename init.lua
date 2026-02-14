--- hs_emacs_helper
-- Hammerspoon spoon for Emacs automation and message display.
-- Provides elisp execution, hotkey management, and on-screen message display.

local obj = {}

obj.__index = obj

-- metadata
obj.name = "hs emacs helper"
obj.version = "0.3"
obj.author = "dmg <dmg@turingmachine.org>"
obj.license = "MIT - https://opensource.org/licenses/MIT"
obj.logger = hs.logger.new("emacs_helper")

-- Emacs configuration
obj.emacsClient = "/opt/homebrew/bin/emacsclient"
obj.EMACS_BUNDLE_ID = "org.gnu.Emacs"

-- Message display configuration
obj.alwaysShow = true
obj.iconEmpty = "🦬"
obj.iconMessage = "🦄️"

obj.msgWidth = 500
obj.msgHeight = 120
obj.msgTextHeight = 60
obj.msgShowDuration = 3 -- in seconds

obj.msgCanvas = hs.canvas.new({x = 0, y = 0, w = 0, h = 0})
obj.msgCanvas[1] = {
  type = "text",
  text = "",
  textFont = "Impact",
  textSize = obj.msgTextHeight,
  textColor = {hex = "#883342"},
  textAlignment = "center",
}

obj.menu = nil
obj.bundleKeys = {}

-------------------------------------------------
-- Helper functions
-------------------------------------------------

--- Checks if Emacs is the frontmost application.
--
-- @return (boolean): true if Emacs is frontmost, false otherwise
function obj:emacs_is_front_app()
  local app = hs.application.frontmostApplication()
  return app:bundleID() == obj.EMACS_BUNDLE_ID
end

--- Activates the Emacs application.
-- Uses bundle ID lookup via Hammerspoon's application API.
--
-- @return (boolean): true if Emacs was activated, false if not found
--
-- @details:
-- - Assumes Emacs always has at least one window open
-- - If Emacs is already frontmost, returns true (nothing to do)
-- - Otherwise finds Emacs by bundle ID and activates it
-- - Returns false only if Emacs app is not found
function obj:focus_emacs()
  -- If already frontmost, nothing to do
  if obj:emacs_is_front_app() then
    return true
  end

  local emacs = hs.application.find(obj.EMACS_BUNDLE_ID)
  return emacs and emacs:activate()
end

--- Sets hotkey enabled/disabled state.
--
-- @param hotkey (hs.hotkey): The hotkey object to manage
-- @param enable (boolean): true=enable, false=disable
function obj:set_hotkey_state(hotkey, enable)
  if enable then
    hotkey:enable()
  else
    hotkey:disable()
  end
end

--- Sends a key combination while managing hotkey state.
-- Temporarily disables the hotkey to prevent recursive firing.
--
-- @param hotkey (hs.hotkey): The hotkey object to manage
-- @param key1 (table): Modifier keys (e.g., {"cmd", "alt"})
-- @param key2 (string): Key to send (e.g., "c")
function obj:send_key_with_hotkey_management(hotkey, key1, key2)
  obj:set_hotkey_state(hotkey, false)
  hs.eventtap.keyStroke(key1, key2)
  obj:set_hotkey_state(hotkey, true)
end

--- Waits for Emacs to become frontmost.
--
-- @param maxWaitTenths (number): Max time to wait in tenths of a second (default: 10 = 1 second)
-- @return (boolean): true if Emacs became frontmost, false if timeout
function obj:wait_for_emacs_frontmost(maxWaitTenths)
  maxWaitTenths = maxWaitTenths or 10
  local count = 0
  while count < maxWaitTenths and not obj:emacs_is_front_app() do
    hs.timer.usleep(100)
    count = count + 1
  end
  return obj:emacs_is_front_app()
end

--- Binds a hotkey that triggers within Emacs.
-- Ensures Emacs is frontmost before sending the key combination.
-- Multiple hotkeys can be bound; calling twice with different keys adds both.
--
-- @param key1 (table): Modifier keys (e.g., {"cmd", "alt"})
-- @param key2 (string): Key to send (e.g., "c")
--
-- @return (string): Unique identifier for this hotkey binding
--
-- @details:
-- - Switches to Emacs before sending keystrokes
-- - Waits up to 1 second for Emacs to become frontmost
-- - Falls back to direct key sending if Emacs unavailable
-- - Each unique key combination is stored separately
-- - Returns keyId for reference (e.g., "cmd+ctrl+c")
function obj:bind_key_to_emacs(key1, key2)
  local keyId = table.concat(key1, "+") .. "+" .. key2

  obj.bundleKeys[keyId] = hs.hotkey.bind(key1, key2, "Forward " .. keyId .. " to Emacs [Emacs]", function()
    local hotkey = obj.bundleKeys[keyId]

    if not hotkey then
      hs.alert.show("Bug: Emacs hotkey not found")
      hs.eventtap.keyStroke(key1, key2)
      return
    end

    if not obj:focus_emacs() then
      hs.alert.show("Emacs is not running")
      obj:send_key_with_hotkey_management(hotkey, key1, key2)
      return
    end

    if obj:wait_for_emacs_frontmost() then
      obj:send_key_with_hotkey_management(hotkey, key1, key2)
    else
      hs.alert.show("Emacs could not be brought forward")
    end
  end)

  return keyId
end

--- Toggles or forces a specific Emacs hotkey's state.
--
-- @param keyId (string): Unique identifier for the hotkey (e.g., "cmd+ctrl+c")
-- @param forceEnable (boolean or nil): nil=toggle, true=enable, false=disable
--
-- @details:
-- - If forceEnable is nil, toggles the hotkey state
-- - If forceEnable is true/false, forces that state
-- - Displays alert with the new status
function obj:toggle_key_to_emacs(keyId, forceEnable)
  local hotkey = obj.bundleKeys[keyId]
  if not hotkey then
    hs.alert.show("Hotkey not found: " .. keyId)
    return
  end

  local shouldEnable = forceEnable ~= nil and forceEnable or (not hotkey:isEnabled())
  obj:set_hotkey_state(hotkey, shouldEnable)

  local status = shouldEnable and "enabled" or "disabled"
  hs.alert.show("Hotkey " .. keyId .. " is now " .. status)
end

--- Sets all Emacs hotkeys to the specified state.
--
-- @param enable (boolean): true=enable all, false=disable all
--
-- @details:
-- - Sets all hotkeys to the same state regardless of current status
-- - Displays alert with the new status and count of hotkeys
function obj:toggle_all_keys_to_emacs(enable)
  if not next(obj.bundleKeys) then
    hs.alert.show("No hotkeys bound")
    return
  end

  for _, hotkey in pairs(obj.bundleKeys) do
    obj:set_hotkey_state(hotkey, enable)
  end

  local status = enable and "enabled" or "disabled"
  hs.alert.show("All " .. #obj.bundleKeys .. " Emacs hotkeys are now " .. status)
end

--- Executes elisp code via emacsclient.
-- Properly escapes single quotes for shell execution.
--
-- @param elisp (string): The elisp code to execute
--
-- @details:
-- - Focuses Emacs window first
-- - Escapes single quotes: ' becomes '\''
-- - Executes asynchronously via os.execute
-- - Logs command for debugging
function obj:emacs_execute(elisp)
  if not obj:focus_emacs() then
    hs.alert("No emacs window found")
    return false
  end

  if type(elisp) ~= "string" or elisp == "" then
    obj.logger.ef("emacs_execute called with invalid elisp")
    return false
  end

  local args = { "-n", "-e", elisp }

  obj.logger.df(
    "executing emacsclient [%s] %s",
    obj.emacsClient,
    hs.inspect(args)
  )

  local task = hs.task.new(
    obj.emacsClient,
    function(exitCode, stdOut, stdErr)
      if exitCode ~= 0 then
        obj.logger.ef(
          "emacsclient failed (%d): %s",
          exitCode,
          stdErr
        )
      end
    end,
    args
  )

  if not task then
    obj.logger.ef("failed to create hs.task for emacsclient")
    return false
  end

  task:start()
  return true
end

-------------------------------------------------
-- Message display functions (from hs_emacs_message)
-------------------------------------------------

--- Hides the message canvas.
--
-- @details:
-- - Immediately hides the on-screen message display
-- - Called automatically when msgShowDuration expires
function obj:message_hide()
  obj.msgCanvas:hide()
end

--- Displays a temporary message on screen.
-- Message appears in the upper-left area and auto-hides after specified duration.
--
-- @param message (string): The message text to display
-- @param duration (number or nil): Display duration in seconds (default: msgShowDuration = 3)
--
-- @details:
-- - Positions relative to primary screen
-- - Automatically hides after duration expires
-- - Computes position at display time to handle screen changes
function obj:message(message, duration)
  duration = duration or obj.msgShowDuration
  local mainScreen = hs.screen.primaryScreen()
  local mainRes = mainScreen:fullFrame()
  obj.msgCanvas:frame({
    x = (mainRes.w - obj.msgWidth) / 8,
    y = (mainRes.h - obj.msgHeight) / 4,
    w = obj.msgWidth,
    h = obj.msgHeight,
  })

  obj.msgCanvas[1].text = message
  obj.msgCanvas:show()
  obj.msg_timer = hs.timer.doAfter(duration, function()
    obj:message_hide()
  end)
end

--- Resets menu title to empty state.
--
-- @details:
-- - Displays only the empty icon in the menubar
-- - Used to clear any active status message
function obj:reset_menu_message()
  obj.menu:setTitle(obj.iconEmpty)
end

--- Updates menu title with status message.
--
-- @param message (string): Status message to display
--
-- @details:
-- Shows message icon followed by the message text in menubar
function obj:update_menu_message(message)
  obj.menu:setTitle(obj.iconMessage .. " " .. message)
end

--- Initializes the menubar status indicator.
--
-- @details:
-- - Creates a new menubar instance for displaying status
-- - Called automatically on spoon load
-- - Uses alwaysShow setting to determine visibility behavior
function obj:init_menu()
  obj.menu = hs.menubar.new(obj.alwaysShow)
end

-- Initialize menubar on load
obj:init_menu()

return obj

