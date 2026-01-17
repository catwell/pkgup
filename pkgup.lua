local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local io = _tl_compat and _tl_compat.io or io; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local os = _tl_compat and _tl_compat.os or os; local pairs = _tl_compat and _tl_compat.pairs or pairs; local string = _tl_compat and _tl_compat.string or string; local table = _tl_compat and _tl_compat.table or table; local http = require("socket.http")
local ltn12 = require("ltn12")
local cjson = require("cjson")
local argparse = require("argparse")














local function die(msg)
   io.stderr:write("error: " .. msg .. "\n")
   os.exit(1)
end

local function read_file(path)
   local f, err = io.open(path, "r")
   if not f then return nil, err end
   local content = f:read("*a")
   f:close()
   return content
end

local function write_file(path, content)
   local f, err = io.open(path, "w")
   if not f then return nil, err end
   f:write(content)
   f:close()
   return true
end

local function detect_github_project(pkgbuild)
   local pjt = pkgbuild:match('\n_?url="https://github%.com/([^"]+)"')
   if not pjt then return nil end
   if not pjt:match("^%w[%w_%-%.]*/%w[%w_%-%.]*$") then return nil end
   return pjt
end

local function http_get(url, headers)
   local response_body = {}
   local _, code = http.request({
      url = url,
      sink = ltn12.sink.table(response_body),
      headers = headers,
   })
   return table.concat(response_body), code
end

local function get_latest_stable_release(pjt)
   local api_url = "https://api.github.com/repos/" .. pjt .. "/releases"
   local body, code = http_get(api_url, {
      ["Accept"] = "application/vnd.github+json",
   })
   if code ~= 200 then
      die("Failed to fetch releases: HTTP " .. tostring(code))
   end
   local releases = cjson.decode(body)
   for _, release in ipairs(releases) do
      if not release.prerelease and not release.draft then
         return release
      end
   end
   die("No stable release found")
end

local function get_checksums(release)
   local checksums = {}
   for _, asset in ipairs(release.assets) do
      if asset.digest then
         local sha256 = asset.digest:match("^sha256:(%x+)$")
         if sha256 then
            checksums[asset.name] = sha256
         end
      end
   end
   return checksums
end

local function expand_vars(fn, version)
   return (fn:gsub("%$pkgver", version):gsub("%${pkgver}", version))
end

local function extract_source_filenames(content, version)
   local filenames = {}
   for arch, source in content:gmatch('\nsource_([%w_]+)=%("([^"]+)"%)') do
      local fn = source:match("[^/]+$")
      if fn then
         filenames[arch] = expand_vars(fn, version)
      end
   end
   return filenames
end

local function update_pkgbuild(
   old_pkgbuild,
   version,
   checksums)

   local content = old_pkgbuild:gsub("\npkgver=[^\n]+", "\npkgver=" .. version)
   for arch, sha256 in pairs(checksums) do
      local pattern = '\nsha256sums_' .. arch .. '=%(.-%)'
      local replacement = '\nsha256sums_' .. arch .. '=("' .. sha256 .. '")'
      content = content:gsub(pattern, replacement)
   end
   local ok, write_err = write_file("PKGBUILD", content)
   if not ok then
      die("Failed to write PKGBUILD: " .. (write_err or ""))
   end
end

local function get_current_version(pkgbuild)
   local version = pkgbuild:match("\npkgver=([^\n]+)")
   if not version then
      die("Could not find pkgver in PKGBUILD")
   end
   return version
end






local function parse_args()
   local parser = argparse("pkgup", "Update binary PKGBUILD with the latest stable release from GitHub")
   parser:flag("-f --force", "Update even if the version is the same")
   parser:option("-p --project", "GitHub project (owner/repo)")
   return parser:parse()
end

local function main()
   local args = parse_args()

   local pkgbuild, err = read_file("PKGBUILD")
   if not pkgbuild then
      die("Failed to read PKGBUILD: " .. (err or ""))
   end

   local pjt = args.project
   if not pjt then
      pjt = detect_github_project(pkgbuild)
   end
   if not pjt then
      die("Could not determine GitHub project.")
   end
   print("GitHub project: " .. pjt)

   local release = get_latest_stable_release(pjt)
   local version = release.tag_name:gsub("^v", "")
   print("Latest stable release: " .. version)
   if not next(release.assets) then
      die("No assets in release. Source package?")
   end

   local current_version = get_current_version(pkgbuild)
   if current_version == version and not args.force then
      print("Already up to date.")
      return
   end


   local source_filenames = extract_source_filenames(pkgbuild, version)
   if not next(source_filenames) then
      die("No sources found in PKGBUILD")
   end

   local checksums_by_fn = get_checksums(release)
   local checksums_by_arch = {}
   for arch, filename in pairs(source_filenames) do
      if not checksums_by_fn[filename] then
         die("No checksum found for " .. filename)
      end
      checksums_by_arch[arch] = checksums_by_fn[filename]
      print("SHA256 " .. arch .. ": " .. checksums_by_arch[arch])
   end

   update_pkgbuild(pkgbuild, version, checksums_by_arch)
   print("Updated PKGBUILD to version " .. version)
end

main()
