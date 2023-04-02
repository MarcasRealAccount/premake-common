local p   = premake
local api = p.api

local function toPremakeArch(name)
	local lc = name:lower()
	if lc == "i386" then
		return "x86"
	elseif lc == "x86_64" or lc == "x64" then
		return "amd64"
	elseif lc == "arm32" then
		return "arm"
	else
		return lc
	end
end

local function getHostArch()
	local arch
	if os.host() == "windows" then
		arch = os.getenv("PROCESSOR_ARCHITECTURE")
		if arch == "x86" then
			local is64 = os.getenv("PROCESSOR_ARCHITEW6432")
			if is64 then arch = is64 end
		end
	elseif os.host() == "macosx" then
		arch = os.outputof("echo $HOSTTYPE")
	else
		arch = os.outputof("uname -m")
	end

	return toPremakeArch(arch)
end

p.extensions        = p.extensions or {}
p.extensions.common = p.extensions.common or {
	_VERSION  = "1.0.0",
	binDir    = "Bin/%{cfg.system}-%{cfg.platform}-%{cfg.buildcfg}/",
	objDir    = "Bin/Int-%{cfg.system}-%{cfg.platform}-%{cfg.buildcfg}/%{prj.name}/",
	dbgDir    = "/Run/",
	host      = os.host(),
	arch      = getHostArch(),
	fullSetup = true,
	failed    = false,
	messages  = {}
}

if common then
	error("Expected variable common to be unused")
end

common       = p.extensions.common
local hasPkg = p.extensions.pkg ~= nil

if not _ACTION or _ACTION == "clean" or _ACTION == "format" or _OPTIONS["help"] then
	common.fullSetup = false
end

if hasPkg then
	p.override(p.main, "checkInteractive", function(base)
		for _, message in ipairs(common.messages) do
			if message.color then term.pushColor(message.color) end
			print(message.text)
			if message.color then term.popColor() end
		end
		if common.failed then
			error("Errors ^", 0)
		end
		base()
	end)
end

function common:scriptDir()
	local str = debug.getinfo(2, "S").source:sub(2)
	return str:match("(.*/)")
end

function common:pushMessage(text, color)
	if hasPkg then
		p.extensions.pkg:pushMessage(text, color)
	else
		table.insert(self.messages, { text = text, color = color })
	end
end

function common:error(fmt, ...)
	self:pushMessage(string.format(fmt, ...), term.errorColor)
	self.failed = true
end

function common:projectName()
	return premake.api.scope.current.name
end

function common:projectLocation()
	return premake.api.scope.current.current.location
end

function common:addActions()
	filter("files:**.inl") runclangformat(true)
	filter("files:**.h") runclangformat(true)
	filter("files:**.cpp")
		runclangformat(true)
		runclangtidy(true)
	filter({})
end

function common:addConfigs()
	configurations({ "Debug", "Release", "Dist" })
	platforms(self.arch)
	filter("platforms:" .. self.arch) architecture(self.arch)
	filter({})
end

function common:addBuildDefines()
	filter("configurations:Debug")
		defines({ "BUILD_CONFIG=BUILD_CONFIG_DEBUG" })
		optimize("Off")
		symbols("On")
	filter("configurations:Release")
		defines({ "BUILD_CONFIG=BUILD_CONFIG_RELEASE" })
		optimize("Full")
		symbols("On")
	filter("configurations:Dist")
		defines({ "BUILD_CONFIG=BUILD_CONFIG_DIST" })
		optimize("Full")
		symbols("Off")
	
	filter("system:windows")
		toolset("msc")
		defines({
			"BUILD_SYSTEM=BUILD_SYSTEM_WINDOWS",
			"NOMINMAX", -- Windows.h disablles
			"WIN32_LEAN_AND_MEAN",
			"_CRT_SECURE_NO_WARNINGS"
		})
	filter("system:macosx")
		toolset("clang")
		defines({ "BUILD_SYSTEM=BUILD_SYSTEM_MACOSX" })
	filter("system:linux")
		toolset("clang")
		defines({ "BUILD_SYSTEM=BUILD_SYSTEM_LINUX" })
	filter("toolset:msc")
		defines({ "BUILD_TOOLSET=BUILD_TOOLSET_MSVC" })
	filter("toolset:clang")
		defines({ "BUILD_TOOLSET=BUILD_TOOLSET_CLANG" })
	filter("toolset:gcc")
		defines({ "BUILD_TOOLSET=BUILD_TOOLSET_GCC" })
	filter("platforms:" .. self.arch)
		defines({ "BUILD_PLATFORM=BUILD_PLATFORM_" .. self.arch:upper() })
	filter({})
end

function common:outDirs(isStatic, targetSuffix)
	targetSuffix = targetSuffix or ""
	if isStatic then
		targetdir("%{wks.location}/" .. self.objDir .. targetSuffix)
		objdir("%{wks.location}/" .. self.objDir)
	else
		targetdir("%{wks.location}/" .. self.binDir .. targetSuffix)
		objdir("%{wks.location}/" .. self.objDir)
	end
end

function common:actionSupportsDebugDir()
	return not string.startswith(_ACTION, "vs")
end

function common:debugDir()
	local projectName     = self:projectName()
	local projectLocation = self:projectLocation()
	debugdir(projectLocation .. self.dbgDir)
	
	if _ACTION ~= nil and self:actionSupportsDebugDir() then
		self:pushMessage(string.format("The '%s' action might not support debug directory.\nSo for the project '%s' you might have to manually 'cd' into the directory: '%s%s'", _ACTION, projectName, projectLocation, self.dbgDir), term.warningColor)
	end
end

function common:addPCH(source, header)
	pchsource(source)
	filter("action:xcode4") pchheader(header)
	filter("action:not xcode4") pchheader(path.getname(header))
	filter({})
	forceincludes({ path.getname(header) })
end

function common:libName(libs, withSymbols)
	if type(libs) == "string" then
		local libnames = self:libName({ libs }, withSymbols)
		if #libnames == 1 then return libnames[1] end
		return libnames
	end
	if type(libs) ~= "table" then return {} end
	for _, lib in pairs(libs) do if type(lib) ~= "string" then return {} end end
	
	local libnames = {}
	for _, lib in pairs(libs) do
		local libname = lib
		if self.host == "windows" then
			if withSymbols then
				table.insert(libnames, libname .. ".pdb")
			end
			libname = libname .. ".lib"
		else
			libname = "lib" .. libname .. ".a"
		end
		table.insert(libnames, libname)
	end
	return libnames
end

function common:sharedLibName(libs, withSymbols)
	if type(libs) == "string" then
		local libnames = self:sharedLibName({ libs }, withSymbols)
		if #libnames == 1 then return libnames[1] end
		return libnames
	end
	if type(libs) ~= "table" then return {} end
	for _, lib in pairs(libs) do if type(lib) ~= "string" then return {} end end
	
	local libnames = {}
	for _, lib in pairs(libs) do
		local libname = lib
		if self.host == "windows" then
			if withSymbols then
				table.insert(libnames, libname .. ".pdb")
			end
			libname = libname .. ".dll"
		elseif self.host == "macosx" then
			libname = "lib" .. libname .. ".dylib"
		else
			libname = "lib" .. libname .. ".so"
		end
		table.insert(libnames, libname)
	end
	return libnames
end

function common:hasLib(lib, searchPaths)
	if type(searchPaths) == "string" then return self:hasLib(lib, { searchPaths }) end
	if type(searchPaths) ~= "table" then return false end
	for _, v in pairs(searchPaths) do if type(v) ~= "string" then return false end end
	
	for _, v in pairs(searchPaths) do
		if #os.matchfiles(v .. "/" .. self:libName(lib)) > 0 then
			return true
		end
	end
	return false
end

function common:hasSharedLib(lib, searchPaths)
	if type(searchPaths) == "string" then return self:hasSharedLib(lib, { searchPaths }) end
	if type(searchPaths) ~= "table" then return false end
	for _, v in pairs(searchPaths) do if type(v) ~= "string" then return false end end
	
	for _, v in pairs(searchPaths) do
		if #os.matchfiles(v .. "/" .. self:sharedLibName(lib)) > 0 then
			return true
		end
	end
	return false
end