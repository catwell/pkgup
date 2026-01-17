local http = require "socket.http"
local ltn12 = require "ltn12"
local cjson = require "cjson"
local argparse = require "argparse"

local record Release
    tag_name: string
    prerelease: boolean
    draft: boolean
    assets: {Asset}
end

local record Asset
    name: string
    browser_download_url: string
    digest: string
end

local function die(msg: string): nil
    io.stderr:write("error: " .. msg .. "\n")
    os.exit(1)
end

local function read_file(path: string): string, string
    local f, err = io.open(path, "r")
    if not f then return nil, err end
    local content = f:read("*a")
    f:close()
    return content
end

local function write_file(path: string, content: string): boolean, string
    local f, err = io.open(path, "w")
    if not f then return nil, err end
    f:write(content)
    f:close()
    return true
end

local function detect_github_project(pkgbuild: string): string
    local pjt = pkgbuild:match('\n_?url="https://github%.com/([^"]+)"')
    if not pjt then return nil end
    if not pjt:match("^%w[%w_%-%.]*/%w[%w_%-%.]*$") then return nil end
    return pjt
end

local function http_get(url: string, headers: {string:string}): string, integer
    local response_body: {string} = {}
    local _, code = http.request({
        url = url,
        sink = ltn12.sink.table(response_body),
        headers = headers,
    })
    return table.concat(response_body), code as integer
end

local function get_latest_stable_release(pjt: string): Release
    local api_url = "https://api.github.com/repos/" .. pjt .. "/releases"
    local body, code = http_get(api_url, {
        ["Accept"] = "application/vnd.github+json",
    })
    if code ~= 200 then
        die("Failed to fetch releases: HTTP " .. tostring(code))
    end
    local releases = cjson.decode(body) as {Release}
    for _, release in ipairs(releases) do
        if not release.prerelease and not release.draft then
            return release
        end
    end
    die("No stable release found")
end

local function get_checksums(release: Release): {string:string}
    local checksums: {string:string} = {}
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

local function expand_vars(fn: string, version: string): string
    return (fn:gsub("%$pkgver", version):gsub("%${pkgver}", version))
end

local function extract_source_filenames(content: string, version: string): {string:string}
    local filenames: {string:string} = {}
    for arch, source in content:gmatch('\nsource_([%w_]+)=%("([^"]+)"%)') do
        local fn = source:match("[^/]+$")
        if fn then
            filenames[arch] = expand_vars(fn, version)
        end
    end
    return filenames
end

local function update_pkgbuild(
    old_pkgbuild: string,
    version: string,
    checksums: {string:string}
): nil
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

local function get_current_version(pkgbuild: string): string
    local version = pkgbuild:match("\npkgver=([^\n]+)")
    if not version then
        die("Could not find pkgver in PKGBUILD")
    end
    return version
end

local record Args
    force: boolean
    project: string
end

local function parse_args(): Args
    local parser = argparse("pkgup", "Update binary PKGBUILD with the latest stable release from GitHub")
    parser:flag("-f --force", "Update even if the version is the same")
    parser:option("-p --project", "GitHub project (owner/repo)")
    return parser:parse() as Args
end

local function main(): nil
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
    local checksums_by_arch: {string:string} = {}
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
