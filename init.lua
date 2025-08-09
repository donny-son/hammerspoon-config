-- Window Ease-In Transparency Animation for Hammerspoon
-- Creates a fading overlay effect to simulate transparency animation

-- Configuration
local config = {
	duration = 0.3, -- Animation duration in seconds
	overlayColor = { -- Overlay color (black by default)
		red = 0,
		green = 0,
		blue = 0,
		alpha = 0.7,        -- Starting opacity (0-1, higher = more opaque)
	},
	easingStyle = "cubic", -- Options: "quad", "cubic", "quart", "expo"
}

-- Easing functions
local easingFunctions = {
	quad = function(t)
		return t * t
	end,
	cubic = function(t)
		return t * t * t
	end,
	quart = function(t)
		return t * t * t * t
	end,
	expo = function(t)
		return t == 0 and 0 or math.pow(2, 10 * t - 10)
	end,
}

-- Cache for overlays and animators
local activeOverlays = {}
local activeAnimators = {}
local animatedWindows = {}

-- Get the easing function
local easeIn = easingFunctions[config.easingStyle] or easingFunctions.cubic

-- Create fade overlay for window
function createFadeOverlay(targetWindow)
	if not targetWindow then
		return
	end

	-- Get window frame
	local success, frame = pcall(function()
		return targetWindow:frame()
	end)
	if not success or not frame then
		return
	end

	-- Create canvas overlay
	local overlay = hs.canvas.new(frame)

	-- Set overlay properties
	overlay:level(hs.canvas.windowLevels.overlay)
	overlay:alpha(1.0)
	overlay:appendElements({
		type = "rectangle",
		action = "fill",
		fillColor = {
			red = config.overlayColor.red,
			green = config.overlayColor.green,
			blue = config.overlayColor.blue,
			alpha = config.overlayColor.alpha,
		},
		frame = { x = 0, y = 0, w = "100%", h = "100%" },
	})

	return overlay
end

-- Animate window with transparency effect
function animateWindowActivation(window)
	if not window then
		return
	end

	-- Check if window is valid
	local success, frame = pcall(function()
		return window:frame()
	end)
	if not success or not frame then
		return
	end

	local windowId = window:id()

	-- Clean up any existing overlay for this window
	if activeOverlays[windowId] then
		activeOverlays[windowId]:delete()
		activeOverlays[windowId] = nil
	end

	if activeAnimators[windowId] then
		activeAnimators[windowId]:stop()
		activeAnimators[windowId] = nil
	end

	-- Prevent rapid re-animation
	if animatedWindows[windowId] then
		local timeSinceLastAnimation = hs.timer.secondsSinceEpoch() - animatedWindows[windowId]
		if timeSinceLastAnimation < 0.5 then
			return
		end
	end
	animatedWindows[windowId] = hs.timer.secondsSinceEpoch()

	-- Create overlay
	local overlay = createFadeOverlay(window)
	if not overlay then
		return
	end

	activeOverlays[windowId] = overlay
	overlay:show()

	-- Animate the overlay fade-out
	local startTime = hs.timer.secondsSinceEpoch()
	local startAlpha = config.overlayColor.alpha

	local animator
	animator = hs.timer.doEvery(0.016, function() -- ~60fps
		local elapsed = hs.timer.secondsSinceEpoch() - startTime
		local progress = math.min(elapsed / config.duration, 1)

		-- Apply easing (inverted for fade-out)
		local eased = 1 - easeIn(progress)

		-- Update overlay opacity
		local currentAlpha = startAlpha * eased

		if overlay and activeOverlays[windowId] then
			local success = pcall(function()
				overlay:replaceElements({
					type = "rectangle",
					action = "fill",
					fillColor = {
						red = config.overlayColor.red,
						green = config.overlayColor.green,
						blue = config.overlayColor.blue,
						alpha = currentAlpha,
					},
					frame = { x = 0, y = 0, w = "100%", h = "100%" },
				})
			end)

			if not success then
				animator:stop()
				if activeOverlays[windowId] then
					activeOverlays[windowId]:delete()
					activeOverlays[windowId] = nil
				end
				activeAnimators[windowId] = nil
				return
			end
		end

		-- Animation complete
		if progress >= 1 then
			animator:stop()
			if activeOverlays[windowId] then
				activeOverlays[windowId]:delete()
				activeOverlays[windowId] = nil
			end
			activeAnimators[windowId] = nil
		end
	end)

	activeAnimators[windowId] = animator
end

-- Alternative: Flash border effect (less intrusive)
function createBorderFlash(targetWindow)
	if not targetWindow then
		return
	end

	local success, frame = pcall(function()
		return targetWindow:frame()
	end)
	if not success or not frame then
		return
	end

	local windowId = targetWindow:id()

	-- Clean up existing effects
	if activeOverlays[windowId] then
		activeOverlays[windowId]:delete()
		activeOverlays[windowId] = nil
	end

	if activeAnimators[windowId] then
		activeAnimators[windowId]:stop()
		activeAnimators[windowId] = nil
	end

	-- Create border canvas
	local border = hs.canvas.new(frame)
	border:level(hs.canvas.windowLevels.overlay)
	border:alpha(1.0)

	local borderWidth = 3
	border:appendElements({
		type = "rectangle",
		action = "stroke",
		strokeColor = { red = 0.3, green = 0.5, blue = 1.0, alpha = 1.0 },
		strokeWidth = borderWidth,
		frame = {
			x = borderWidth / 2,
			y = borderWidth / 2,
			w = frame.w - borderWidth,
			h = frame.h - borderWidth,
		},
	})

	activeOverlays[windowId] = border
	border:show()

	-- Animate fade out
	local startTime = hs.timer.secondsSinceEpoch()

	local animator
	animator = hs.timer.doEvery(0.016, function()
		local elapsed = hs.timer.secondsSinceEpoch() - startTime
		local progress = math.min(elapsed / config.duration, 1)
		local eased = 1 - easeIn(progress)

		if border and activeOverlays[windowId] then
			pcall(function()
				border:alpha(eased)
			end)
		end

		if progress >= 1 then
			animator:stop()
			if activeOverlays[windowId] then
				activeOverlays[windowId]:delete()
				activeOverlays[windowId] = nil
			end
			activeAnimators[windowId] = nil
		end
	end)

	activeAnimators[windowId] = animator
end

-- Window filter setup
local windowFilter = hs.window.filter.new()
windowFilter:setDefaultFilter({})
windowFilter:setSortOrder(hs.window.filter.sortByFocusedLast)

-- Excluded apps
local excludedApps = {
	"Hammerspoon",
	"Alfred",
	"Spotlight",
	"Notification Center",
}

-- Subscribe to window focus
windowFilter:subscribe(hs.window.filter.windowFocused, function(window)
	if window then
		local app = window:application()
		if app then
			local appName = app:name()
			for _, excluded in ipairs(excludedApps) do
				if appName == excluded then
					return
				end
			end
		end
		animateWindowActivation(window)
	end
end)

-- Application watcher
hs.application.watcher
		.new(function(appName, eventType, appObject)
			if eventType == hs.application.watcher.activated then
				for _, excluded in ipairs(excludedApps) do
					if appName == excluded then
						return
					end
				end

				hs.timer.doAfter(0.01, function()
					local app = hs.application.frontmostApplication()
					if app then
						local window = app:focusedWindow()
						if window then
							animateWindowActivation(window)
						end
					end
				end)
			end
		end)
		:start()

-- Clean up periodically
hs.timer.doEvery(60, function()
	local currentTime = hs.timer.secondsSinceEpoch()
	for windowId, timestamp in pairs(animatedWindows) do
		if currentTime - timestamp > 60 then
			animatedWindows[windowId] = nil
			if activeOverlays[windowId] then
				activeOverlays[windowId]:delete()
				activeOverlays[windowId] = nil
			end
			if activeAnimators[windowId] then
				activeAnimators[windowId]:stop()
				activeAnimators[windowId] = nil
			end
		end
	end
end)

-- Configuration hotkeys
-- Toggle between overlay and border effect
local useBorderEffect = false
hs.hotkey.bind({ "cmd", "alt", "ctrl" }, "T", function()
	useBorderEffect = not useBorderEffect
	if useBorderEffect then
		-- Replace animation function
		animateWindowActivation = createBorderFlash
		hs.alert.show("Effect: Border flash")
	else
		-- Restore original function
		animateWindowActivation = function(window)
			if not window then
				return
			end
			local success, frame = pcall(function()
				return window:frame()
			end)
			if not success or not frame then
				return
			end

			local windowId = window:id()
			if activeOverlays[windowId] then
				activeOverlays[windowId]:delete()
				activeOverlays[windowId] = nil
			end
			if activeAnimators[windowId] then
				activeAnimators[windowId]:stop()
				activeAnimators[windowId] = nil
			end

			if animatedWindows[windowId] then
				local timeSinceLastAnimation = hs.timer.secondsSinceEpoch() - animatedWindows[windowId]
				if timeSinceLastAnimation < 0.5 then
					return
				end
			end
			animatedWindows[windowId] = hs.timer.secondsSinceEpoch()

			local overlay = createFadeOverlay(window)
			if not overlay then
				return
			end

			activeOverlays[windowId] = overlay
			overlay:show()

			local startTime = hs.timer.secondsSinceEpoch()
			local startAlpha = config.overlayColor.alpha

			local animator = hs.timer.doEvery(0.016, function()
				local elapsed = hs.timer.secondsSinceEpoch() - startTime
				local progress = math.min(elapsed / config.duration, 1)
				local eased = 1 - easeIn(progress)
				local currentAlpha = startAlpha * eased

				if overlay and activeOverlays[windowId] then
					pcall(function()
						overlay:replaceElements({
							type = "rectangle",
							action = "fill",
							fillColor = {
								red = config.overlayColor.red,
								green = config.overlayColor.green,
								blue = config.overlayColor.blue,
								alpha = currentAlpha,
							},
							frame = { x = 0, y = 0, w = "100%", h = "100%" },
						})
					end)
				end

				if progress >= 1 then
					animator:stop()
					if activeOverlays[windowId] then
						activeOverlays[windowId]:delete()
						activeOverlays[windowId] = nil
					end
					activeAnimators[windowId] = nil
				end
			end)

			activeAnimators[windowId] = animator
		end
		hs.alert.show("Effect: Overlay fade")
	end
end)

-- Adjust overlay darkness
hs.hotkey.bind({ "cmd", "alt", "ctrl" }, "D", function()
	config.overlayColor.alpha = math.min(config.overlayColor.alpha + 0.1, 1.0)
	hs.alert.show(string.format("Overlay opacity: %.1f", config.overlayColor.alpha))
end)

hs.hotkey.bind({ "cmd", "alt", "ctrl" }, "L", function()
	config.overlayColor.alpha = math.max(config.overlayColor.alpha - 0.1, 0.1)
	hs.alert.show(string.format("Overlay opacity: %.1f", config.overlayColor.alpha))
end)

-- Change easing style
hs.hotkey.bind({ "cmd", "alt", "ctrl" }, "E", function()
	local styles = { "quad", "cubic", "quart", "expo" }
	local currentIndex = 1
	for i, style in ipairs(styles) do
		if style == config.easingStyle then
			currentIndex = i
			break
		end
	end
	currentIndex = currentIndex % #styles + 1
	config.easingStyle = styles[currentIndex]
	easeIn = easingFunctions[config.easingStyle]
	hs.alert.show("Easing style: " .. config.easingStyle)
end)

-- Reload
hs.hotkey.bind({ "cmd", "alt", "ctrl" }, "R", function()
	hs.reload()
end)

hs.alert.show("Transparency ease-in animations loaded")
