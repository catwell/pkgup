rockspec_format = "3.0"

package = "pkgup"
version = "dev-1"

source = {
    url = "git+https://github.com/catwell/pkgup.git",
}

description = {
    summary = "Update binary PKGBUILD with the latest stable release from GitHub",
    license = "MIT",
}

dependencies = {
    "lua >= 5.1",
    "luasocket",
    "lua-cjson",
    "luasec",
    "argparse",
}

build = {
    type = "builtin",
    modules = {},
    install = {
        bin = {
            pkgup = "pkgup.lua",
        },
    },
}

