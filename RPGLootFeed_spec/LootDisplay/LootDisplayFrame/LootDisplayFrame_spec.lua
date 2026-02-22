local nsMocks = require("RPGLootFeed_spec._mocks.Internal.addonNamespace")
local assert = require("luassert")
local match = require("luassert.match")
local busted = require("busted")
local before_each = busted.before_each
local describe = busted.describe
local it = busted.it
local spy = busted.spy
local stub = busted.stub

describe("LootDisplayFrameMixin", function()
	local ns, _
	_ = match._

	describe("load order", function()
		it("loads the file successfully", function()
			ns = nsMocks:unitLoadedAfter(nsMocks.LoadSections.LootDisplay)
			local loaded =
				assert(loadfile("RPGLootFeed/LootDisplay/LootDisplayFrame/LootDisplayFrame.lua"))("TestAddon", ns)
			assert.is_not_nil(loaded)
			assert.is_not_nil(_G.LootDisplayFrameMixin)
			assert.is_not_nil(_G.LootDisplayFrameMixin.Load)
			assert.is_not_nil(_G.LootDisplayFrameMixin.getFrameHeight)
			assert.is_not_nil(_G.LootDisplayFrameMixin.LeaseRow)
			assert.is_not_nil(_G.LootDisplayFrameMixin.ReleaseRow)
			assert.is_not_nil(_G.LootDisplayFrameMixin.UpdateSize)
		end)
	end)

	local frame, mockSizing, mockPositioning, mockStyling, mockGlobalFns
	before_each(function()
		mockGlobalFns = require("RPGLootFeed_spec._mocks.WoWGlobals.Functions")
		-- Define the global G_RLF
		ns = nsMocks:unitLoadedAfter(nsMocks.LoadSections.All)

		-- Load the module before each test
		frame = assert(loadfile("RPGLootFeed/LootDisplay/LootDisplayFrame/LootDisplayFrame.lua"))("TestAddon", ns)

		-- Set up necessary mocks for DBAccessor
		mockSizing = stub(ns.DbAccessor, "Sizing").returns({
			maxRows = 5,
			rowHeight = 40,
			padding = 8,
			feedWidth = 300,
		})

		mockPositioning = stub(ns.DbAccessor, "Positioning").returns({
			anchorPoint = "CENTER",
			relativePoint = "UIParent",
			xOffset = 1,
			yOffset = 2,
			frameStrata = "MEDIUM",
		})

		mockStyling = stub(ns.DbAccessor, "Styling").returns({
			growUp = true,
		})
	end)

	it("initializes correctly with Load method", function()
		mockGlobalFns.CreateFramePool.returns({})

		local testList = {}
		nsMocks.list.returns(testList)
		local stubGetPositioningDetails = stub(frame, "getPositioningDetails")
		local stubInitQueueLabel = stub(frame, "InitQueueLabel")
		local stubUpdateSize = stub(frame, "UpdateSize")
		local stubSetPoint = stub(frame, "SetPoint")
		local stubSetFrameStrata = stub(frame, "SetFrameStrata")
		local stubConfigureTestArea = stub(frame, "ConfigureTestArea")
		local stubCreateTab = stub(frame, "CreateTab")

		frame:Load(ns.Frames.MAIN)

		assert.equal(ns.Frames.MAIN, frame.frameType)
		assert.equal(testList, frame.rows)
		assert.equal(0, frame.keyRowMap.length)
		assert.equal(0, #frame.rowHistory)
		assert.is_not_nil(frame.rowFramePool)
		assert.stub(stubGetPositioningDetails).was.called(1)
		assert.stub(mockPositioning).was.called(1)
		assert.stub(mockPositioning).was.called_with(ns.DbAccessor, ns.Frames.MAIN)
		assert.stub(stubUpdateSize).was.called(1)
		assert.stub(stubSetPoint).was.called(1)
		assert.stub(stubSetPoint).was.called_with(frame, "CENTER", _G["UIParent"], 1, 2)
		assert.stub(stubSetFrameStrata).was.called(1)
		assert.stub(stubSetFrameStrata).was.called_with(frame, "MEDIUM")
		assert.stub(stubConfigureTestArea).was.called(1)
		assert.stub(stubCreateTab).was.called(1)
	end)

	it("calculates frame height correctly with getFrameHeight", function()
		local mockSizingData = {
			maxRows = 3,
			rowHeight = 20,
			padding = 5,
		}
		mockSizing.returns(mockSizingData)
		frame.frameType = ns.Frames.MAIN

		local result = frame:getFrameHeight()

		-- Expected height calculation from actual implementation: maxRows * (rowHeight + padding) - padding
		local expectedHeight = mockSizingData.maxRows * (mockSizingData.rowHeight + mockSizingData.padding)
			- mockSizingData.padding
		assert.equal(expectedHeight, result)
		assert.stub(mockSizing).was.called(1)
		assert.stub(mockSizing).was.called_with(ns.DbAccessor, ns.Frames.MAIN)
	end)

	it("returns correct row count with getNumberOfRows", function()
		frame.rows = { length = 3 }
		local result = frame:getNumberOfRows()
		assert.equal(3, result)
	end)

	it("retrieves positioning details correctly with getPositioningDetails", function()
		mockStyling.returns({ growUp = true })
		frame.frameType = ns.Frames.MAIN
		mockSizing.returns({ padding = 8 })

		local vertDir, opposite, yOffset = frame:getPositioningDetails()

		assert.equal("BOTTOM", vertDir)
		assert.equal("TOP", opposite)
		assert.equal(8, yOffset)

		-- Test with growUp = false
		mockStyling.returns({ growUp = false })
		vertDir, opposite, yOffset = frame:getPositioningDetails()

		assert.equal("TOP", vertDir)
		assert.equal("BOTTOM", opposite)
		assert.equal(-8, yOffset) -- negative when growing down
	end)

	it("leases a row correctly with LeaseRow", function()
		-- Set up mocks
		local mockRow = {
			Init = spy.new(function() end),
			SetParent = spy.new(function() end),
			UpdatePosition = spy.new(function() end),
			Hide = spy.new(function() end),
			ResetHighlightBorder = spy.new(function() end),
		}
		frame.rowFramePool = {
			Acquire = spy.new(function()
				return mockRow
			end),
		}
		frame.frameType = ns.Frames.MAIN
		frame.rows = {
			push = spy.new(function()
				return true
			end),
			length = 0,
		}
		frame.keyRowMap = { length = 0 }
		frame.rowHistory = {}

		local stubUpdateTabVisibility = stub(frame, "UpdateTabVisibility")
		local stubGetNumberOfRows = stub(frame, "getNumberOfRows").returns(0)
		mockSizing.returns({ maxRows = 5 })

		local key = "testKey"
		local result = frame:LeaseRow(key)

		-- Check basic setup
		assert.equal(mockRow, result)
		assert.equal(key, mockRow.key)
		assert.equal(frame.frameType, mockRow.frameType)

		-- Check that necessary methods were called
		assert.spy(frame.rowFramePool.Acquire).was.called(1)
		assert.spy(frame.rows.push).was.called(1)
		assert.spy(frame.rows.push).was.called_with(frame.rows, mockRow)
		assert.spy(mockRow.Init).was.called(1)
		assert.spy(mockRow.SetParent).was.called(1)
		assert.equal(frame, mockRow.SetParent.calls[1].refs[2])
		assert.equal(mockRow, frame.keyRowMap[key])
		assert.equal(1, frame.keyRowMap.length)
		assert.spy(mockRow.UpdatePosition).was.called(1)
		assert.spy(mockRow.UpdatePosition).was.called_with(mockRow, frame)

		-- Check keyRowMap updates
		assert.equal(1, frame.keyRowMap.length)
		assert.equal(mockRow, frame.keyRowMap[key])

		-- Check that RunNextFrame was called twice
		assert.spy(mockGlobalFns.RunNextFrame).was.called(2)

		-- Check UpdateTabVisibility was called
		assert.stub(stubUpdateTabVisibility).was.called(1)
	end)

	it("doesn't lease a row when at max capacity", function()
		frame.frameType = ns.Frames.MAIN
		local stubGetNumberOfRows = stub(frame, "getNumberOfRows").returns(5)
		mockSizing.returns({ maxRows = 5 })

		local result = frame:LeaseRow("testKey")

		assert.is_nil(result)
	end)

	it("releases a row correctly with ReleaseRow", function()
		-- Set up mocks
		local mockRow = {
			key = "testKey",
			UpdateNeighborPositions = spy.new(function() end),
			SetParent = spy.new(function() end),
			Reset = spy.new(function() end),
			Dump = spy.new(function()
				return "mockRowDump"
			end),
		}
		frame.rowFramePool = {
			Release = spy.new(function() end),
		}
		frame.rows = {
			remove = spy.new(function(self, row)
				return true
			end), -- Return true to indicate success
		}
		frame.keyRowMap = {
			length = 1,
			["testKey"] = mockRow,
		}
		local stubStoreRowHistory = stub(frame, "StoreRowHistory")
		local stubUpdateTabVisibility = stub(frame, "UpdateTabVisibility")
		frame.frameType = ns.Frames.MAIN

		frame:ReleaseRow(mockRow)

		-- Check that the keyRowMap was updated
		assert.is_nil(mockRow.key)
		assert.equal(0, frame.keyRowMap.length)
		assert.is_nil(frame.keyRowMap["testKey"])

		-- Check that methods were called
		assert.stub(stubStoreRowHistory).was.called(1)
		assert.equal(mockRow, stubStoreRowHistory.calls[1].refs[2])
		assert.spy(mockRow.UpdateNeighborPositions).was.called(1)
		assert.equal(frame, mockRow.UpdateNeighborPositions.calls[1].refs[2])
		assert.spy(frame.rows.remove).was.called(1)
		assert.equal(mockRow, frame.rows.remove.calls[1].refs[2])
		assert.spy(mockRow.SetParent).was.called(1)
		assert.equal(nil, mockRow.SetParent.calls[1].refs[2])
		assert.spy(mockRow.Reset).was.called(1)
		assert.spy(frame.rowFramePool.Release).was.called(1)
		assert.spy(frame.rowFramePool.Release).was.called_with(frame.rowFramePool, mockRow)

		-- Check that SendMessage was called
		assert.spy(nsMocks.SendMessage).was.called(1)
		assert.spy(nsMocks.SendMessage).was.called_with(ns, "RLF_ROW_RETURNED")

		-- Check that UpdateTabVisibility was called
		assert.stub(stubUpdateTabVisibility).was.called(1)
	end)

	it("updates size correctly with UpdateSize", function()
		-- Set up mocks
		local stubGetFrameHeight = stub(frame, "getFrameHeight").returns(100)
		local stubSetSize = stub(frame, "SetSize")
		frame.frameType = ns.Frames.MAIN
		mockSizing.returns({
			feedWidth = 300,
		})

		-- Properly mock rows with finite iteration
		local mockRow = {
			UpdateStyles = spy.new(function() end),
		}

		-- Create a proper iterator function that returns exactly one row and then nil
		local iteratorCalled = false
		frame.rows = {
			iterate = function()
				return function()
					if not iteratorCalled then
						iteratorCalled = true
						return mockRow
					end
					return nil -- Return nil to end iteration
				end
			end,
		}

		frame:UpdateSize()

		-- Check that getFrameHeight was called
		assert.stub(stubGetFrameHeight).was.called(1)

		-- Check that SetSize was called with correct values
		assert.stub(stubSetSize).was.called(1)
		assert.stub(stubSetSize).was.called_with(frame, 300, 100)

		-- Check that row styles were updated
		assert.spy(mockRow.UpdateStyles).was.called(1)

		assert.stub(mockSizing).was.called(1)
		assert.stub(mockSizing).was.called_with(ns.DbAccessor, ns.Frames.MAIN)
	end)

	it("configures test area correctly", function()
		-- Set up mocks
		frame.BoundingBox = {
			Hide = spy.new(function() end),
		}
		frame.InstructionText = {
			SetText = spy.new(function() end),
			Hide = spy.new(function() end),
		}
		local stubMakeUnmovable = stub(frame, "MakeUnmovable")
		local stubCreateArrowsTestArea = stub(frame, "CreateArrowsTestArea")

		frame.frameType = ns.Frames.MAIN
		ns.L = {
			["Party Loot"] = "Party Loot",
			["Drag to Move"] = "Drag to Move",
		}

		frame:ConfigureTestArea()

		-- Check that methods were called
		assert.spy(frame.BoundingBox.Hide).was.called(1)
		assert.stub(stubMakeUnmovable).was.called(1)
		assert.spy(frame.InstructionText.SetText).was.called(1)
		assert.spy(frame.InstructionText.SetText).was.called_with(frame.InstructionText, "TestAddon\nDrag to Move")
		assert.spy(frame.InstructionText.Hide).was.called(1)
		assert.stub(stubCreateArrowsTestArea).was.called(1)
	end)

	it("creates frame tab correctly", function()
		frame.frameType = ns.Frames.MAIN

		local mockTab = {
			SetSize = spy.new(function() end),
			SetPoint = spy.new(function() end),
			SetAlpha = spy.new(function() end),
			Hide = spy.new(function() end),
			SetScript = spy.new(function() end),
			CreateTexture = spy.new(function()
				return {
					SetTexture = spy.new(function() end),
					SetAllPoints = spy.new(function() end),
				}
			end),
		}

		mockGlobalFns.CreateFrame.returns(mockTab)
		mockStyling.returns({ growUp = true })

		frame:CreateTab()

		-- Check that CreateFrame was called correctly
		assert.spy(mockGlobalFns.CreateFrame).was.called(1)
		assert.spy(mockGlobalFns.CreateFrame).was.called_with("Button", nil, _G.UIParent, "UIPanelButtonTemplate")

		-- Check that the tab was configured
		assert.spy(mockTab.SetSize).was.called(1)
		assert.spy(mockTab.SetSize).was.called_with(mockTab, 14, 14)
		assert.spy(mockTab.SetPoint).was.called(1)
		assert.spy(mockTab.SetPoint).was.called_with(mockTab, "BOTTOMLEFT", frame, "BOTTOMLEFT", -14, 0)
		assert.spy(mockTab.SetAlpha).was.called(1)
		assert.spy(mockTab.SetAlpha).was.called_with(mockTab, 0.2)
		assert.spy(mockTab.Hide).was.called(1)

		-- Check that texture was created
		assert.spy(mockTab.CreateTexture).was.called(1)

		-- Check that scripts were set
		assert.spy(mockTab.SetScript).was.called(3) -- OnEnter, OnLeave, OnClick
	end)

	it("creates tab with different positioning when growing down", function()
		frame.frameType = ns.Frames.MAIN

		local mockTab = {
			SetSize = spy.new(function() end),
			SetPoint = spy.new(function() end),
			SetAlpha = spy.new(function() end),
			Hide = spy.new(function() end),
			SetScript = spy.new(function() end),
			CreateTexture = spy.new(function()
				return {
					SetTexture = spy.new(function() end),
					SetAllPoints = spy.new(function() end),
				}
			end),
		}

		mockGlobalFns.CreateFrame.returns(mockTab)
		mockStyling.returns({ growUp = false }) -- Growing down

		frame:CreateTab()

		-- Check tab position was set correctly for growUp = false
		assert.spy(mockTab.SetPoint).was.called(1)
		assert.spy(mockTab.SetPoint).was.called_with(mockTab, "TOPLEFT", frame, "TOPLEFT", 0, 0)
	end)

	it("creates arrows test area correctly", function()
		frame.ArrowUp = { SetRotation = spy.new(function() end), Hide = spy.new(function() end) }
		frame.ArrowDown = { SetRotation = spy.new(function() end), Hide = spy.new(function() end) }
		frame.ArrowLeft = { SetRotation = spy.new(function() end), Hide = spy.new(function() end) }
		frame.ArrowRight = { SetRotation = spy.new(function() end), Hide = spy.new(function() end) }

		frame:CreateArrowsTestArea()

		-- Check arrows array was created
		assert.are.same({ frame.ArrowUp, frame.ArrowDown, frame.ArrowLeft, frame.ArrowRight }, frame.arrows)

		-- Check arrow rotations
		assert.spy(frame.ArrowUp.SetRotation).was.called(1)
		assert.spy(frame.ArrowUp.SetRotation).was.called_with(frame.ArrowUp, 0)
		assert.spy(frame.ArrowDown.SetRotation).was.called(1)
		assert.spy(frame.ArrowDown.SetRotation).was.called_with(frame.ArrowDown, math.pi)
		assert.spy(frame.ArrowLeft.SetRotation).was.called(1)
		assert.spy(frame.ArrowLeft.SetRotation).was.called_with(frame.ArrowLeft, math.pi * 0.5)
		assert.spy(frame.ArrowRight.SetRotation).was.called(1)
		assert.spy(frame.ArrowRight.SetRotation).was.called_with(frame.ArrowRight, math.pi * 1.5)

		-- Check all arrows are hidden
		assert.spy(frame.ArrowUp.Hide).was.called(1)
		assert.spy(frame.ArrowDown.Hide).was.called(1)
		assert.spy(frame.ArrowLeft.Hide).was.called(1)
		assert.spy(frame.ArrowRight.Hide).was.called(1)
	end)
end)
