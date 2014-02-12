--[[
  Auto updating pastebin utility
  
  Version 0.0.1 - February 2014

  @copyleft Azathoth February 2014
--]]


CACHE_FOLDER = ".tap-cache"
CACHE_FILE = CACHE_FOLDER .. "/.versions"
LOCKED_VERSION = "--locked--"
MISSING_VERSION = "--missing--"
RUN_TEMPLATE = '--Generated from url %s\nargs = { ... }\nshell.run("'.. shell.getRunningProgram() ..'", "run", "%s", unpack(args))'
CACHED_VERSIONS = {}


commands = {}

-- define runnable commands
commands["get"] = function( ... )
  local arg = {...}

  local code = arg[1]
  local fileName = arg[2]
  printf("Installing %s as %s", code, fileName)
  download(code)
  saveShortcut(code, fileName)
end

commands["run"] = function( ... ) 
  local arg = {...}
  local code = table.remove(arg, 1)


  download(code)
  local context, err = loadCachedCode(code)

  if not context then
    printError (err)
    return
  end

  setfenv(context, getfenv())
  local success, msg = pcall(context, unpack(arg))
  if not success then
    printError(msg)
  end
end

commands["lock"] = function(file) 
  code = getCodeFromFile(file)

  -- load version info
  getCachedVersion(code)

  setCachedVersion(code, LOCKED_VERSION)
end

commands["unlock"] = function(file) 
  code = getCodeFromFile(file)

  -- load version info
  getCachedVersion(code)

  setCachedVersion(code, "none")
end


-- Define missing printf 
function printf(fmt, ...) 

  local targ = {...}

  -- sanitize arguments --
  for i,v in ipairs(targ) do
    if v == nil then
      targ[i] = "[]"
    end
  end

  print(string.format(fmt, unpack(targ)))
end


local function showHelp(name) 
  print("Usage:")
  printf("%s get <code> <filename> : Installs a file from pastebin ", name)
  printf("%s run <code> <arguments> : Runs a file from a pastebin code", name)
  printf("%s lock <filename> : Disables autoupdate for this file ", name)
  printf("%s unlock <filename> : Enables autoupdate for this file ", name)
end

-- Download file from pastebin code
function download(code) 
  local cachedVersion = getCachedVersion(code)
  local paste = pastebinOpen(code)
  local onlineVersion = cachedVersion
  if paste ~= nil then 
     onlineVersion = pastebinGetVersion(paste)
  end


  if cachedVersion ~= LOCKED_VERSION and (cachedVersion ~= onlineVersion or onlineVersion == MISSING_VERSION) then
    if onlineVersion ~= MISSING_VERSION then
      printf("Downloading updated version %s.", onlineVersion)
    end
    pastebinDownload(code, onlineVersion, paste)
    setCachedVersion(code, onlineVersion)
  end

  if paste ~= nil then
    pastebinClose(paste)
  end

end

function getFileName(code) 
  local url = string.gsub(code, 'http(s*)://', "")
  url = string.gsub(url, "%W", "")

  return CACHE_FOLDER .. "/" .. url
end

-- Stop updating the file under code
function lock(code) 
  setCachedVersion(code, LOCKED_VERSION)
end

-- Resume updating the file 
function unlock(code)
  setCachedVersion(code, "")
end


function loadCachedCode(code) 

  if fileCode == nil then
    local file = fs.open(getFileName(code), 'r')
    fileCode = file.readAll();
    file.close()
  end

  -- lua isnt interpreting the first line for some reason
  return loadstring(fileCode)
end

-- Read local file store version numbers
function getCachedVersion(code)
  foundVersion = "none"
  if not fs.exists(CACHE_FILE) then
    return foundVersion
  end


  -- print("Loading cache file")

  local file = fs.open(CACHE_FILE, 'r')
  local line = nil

  while true do
    line = file.readLine()
    if line == nil then
      break
    end

    local pattern = ".*\"(%S*)\".*=\"(%S*)\""
    local url, version = string.match(line, pattern)

    if url ~= nil and version ~= nil then 
      -- printf("File: %s => %s", url, version)
      CACHED_VERSIONS[url] = version;
    end

    if (url == code) then
      foundVersion = version
    end

  end

  file.close()
  return foundVersion

end

-- Save local file store version numbers 
function setCachedVersion(code, version)

-- define functional map and key - value serialization definition

  local function serializeCacheVersion(key, value)
    return string.format("[\"%s\"]=\"%s\"", key, value)
  end 

  local function map(f, array)
    local ret = {}
    for k,v in pairs(array) do
     table.insert(ret, f(k, v))
   end

   return ret
  end


  CACHED_VERSIONS[code] = version

  local cachefile = fs.open(CACHE_FILE, 'w')
  cachefile.writeLine("VERSIONS = {")
  local keys = map(serializeCacheVersion, CACHED_VERSIONS)

  cachefile.writeLine(table.concat(keys, ',\n'))
  cachefile.writeLine("}")
  cachefile.close()
end


-- Open pastebin file
function pastebinOpen(code)
  handle = http.get(code)

  if handle ~= nil and handle.getResponseCode() == 200 then
    return handle
  end

  if handle ~= nil then 
    printf("URL returned %d", handle.getResponseCode())
  end

  printf("Unable to open url %s !", code)
  return nil
end

-- Get version number from pastebin downloaded file
function pastebinGetVersion(handle) 
  versionStr  = handle.readLine()
  local version = string.match(versionStr, "--%s*Version:%s*(%S*)%s*--")

  if version == nil then
    version = MISSING_VERSION
  else 
    versionStr = nil
  end


  return version
end

-- Download and save pastebin code to local cache file
function pastebinDownload(code, version, handle)
  fileCode = handle.readAll()

  local savefile = fs.open(getFileName(code), "w")  
  if versionStr ~= nil then
    fileCode = versionStr .. fileCode
  end

  savefile.write(fileCode)
  savefile.flush()
  savefile.close()
end

-- Close pastebin handle
function pastebinClose(handle)
  handle.close()
end


-- Get pastebin code from a shortcut file
function getCodeFromFile(name)
  local file = fs.open(name, 'r')
  local text = file.readLine()
  file.close()

  local code = string.match(text, "url (%S*)")

  return code
end


-- Save shortcut to the main folder
function saveShortcut(code, name)
  file = fs.open(name, 'w')
  file.write(string.format(RUN_TEMPLATE, code, code))
  file.close()
end


local function init() 
  if not fs.isDir(CACHE_FOLDER) then
    fs.makeDir(CACHE_FOLDER)
  end
end


-- check for HTTP enabled and die if not
if not http then
  printError("HTTP API is required for this to run properly")
  printError("Set enableAPI_http to true in ComputerCraft.cfg")
end


local args = { ... }
if #args < 2 then
  showHelp(shell.getRunningProgram())
  return
end

init()

comm = args[1]

if commands[comm] == nil then
  printf("Command not recognized: %s.", comm)
  showHelp(args[1])
else
  table.remove(args, 1)

  commands[comm](unpack(args))
end
