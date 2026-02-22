---
-- Project-local copy of the luacov-html reporter entry point.
-- Kept in-tree so that install order of luarocks packages (luacov vs luacov-html)
-- can never clobber this file.
--
-- Source: https://github.com/wesen1/luacov-html (MIT License)
-- @author wesen <wesen-ac@web.de>

local reporter = require("luacov.reporter")
local ReporterBase = reporter.ReporterBase
local Configuration = require("luacov.html.Configuration")
local Total = require("luacov.html.CoverageData.Total")
local Writer = require("luacov.html.Writer.Writer")

---
-- Luacov Reporter that generates HTML files to visualize the coverage of lines, files and directories.
--
-- @type HtmlReporter
--
local HtmlReporter = setmetatable({}, ReporterBase)
HtmlReporter.__index = HtmlReporter

HtmlReporter.totalCoverageData = nil
HtmlReporter.totalCoverageWriter = nil

function HtmlReporter:new(_luacovConfigurationTable)
	local object, errorMessage = ReporterBase.new(self, _luacovConfigurationTable)
	if not object then
		return nil, errorMessage
	end

	local configuration = Configuration(_luacovConfigurationTable)
	object.totalCoverageData = Total(configuration:getProjectName())
	object.totalCoverageWriter = Writer(configuration:getOutputDirectoryPath())

	return object
end

function HtmlReporter:on_start()
	self.totalCoverageData:setStartTimestamp(os.time())
end

function HtmlReporter:on_empty_line(_filePath, _lineNumber, _line)
	self.totalCoverageData:addEmptyLine(_filePath, _lineNumber, _line)
end

function HtmlReporter:on_mis_line(_filePath, _lineNumber, _line)
	self.totalCoverageData:addMissedLine(_filePath, _lineNumber, _line)
end

function HtmlReporter:on_hit_line(_filePath, _lineNumber, _line, _numberOfHits)
	self.totalCoverageData:addHitLine(_filePath, _lineNumber, _line, _numberOfHits)
end

function HtmlReporter:on_end_file(_filePath, _numberOfHits, _numberOfMisses)
	self.totalCoverageData:addFileHitMissStatistics(_filePath, _numberOfHits, _numberOfMisses)
end

function HtmlReporter:on_end()
	self.totalCoverageWriter:writeTotalCoverage(self.totalCoverageData)
end

return {
	HtmlReporter = HtmlReporter,

	report = function()
		return reporter.report(HtmlReporter)
	end,
}
