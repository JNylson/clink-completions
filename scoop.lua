local JSON = require("JSON")

local matchers = require("matchers")
local path = require("path")
local w = require("tables").wrap
local concat = require("funclib").concat

local parser = clink.arg.new_parser

local function get_home_dir()
    return os.getenv("home") or os.getenv("USERPROFILE")
end

local function scoop_load_config() -- luacheck: no unused args
    local file = io.open(get_home_dir() .. "\\.config\\scoop\\config.json")
    -- If there is no such file, then close handle and return
    if file == nil then
        return w()
    end

    -- Read the whole file contents
    local contents = file:read("*a")
    file:close()

    -- strip UTF-8-BOM
    local utf8_len = contents:len()
    local pat_start, _ = string.find(contents, "{")
    contents = contents:sub(pat_start, utf8_len)

    local data = JSON:decode(contents)

    if data == nil then
        return w()
    end

    return data
end

local function scoop_folder()
    local folder = os.getenv("SCOOP")
    if not folder then
        local config = scoop_load_config()
        if config and config.root_path then
            folder = config.root_path
        else
            folder = get_home_dir() .. "\\scoop"
        end
    end
    return folder
end

local function scoop_global_folder()
    local folder = os.getenv("SCOOP_GLOBAL")
    if not folder then
        local config = scoop_load_config()
        if config and config.global_path then
            folder = config.global_path
        else
            folder = os.getenv("ProgramData") .. "\\scoop"
        end
    end
    return folder
end

local function scoop_alias_list(token) -- luacheck: no unused args
    local data = scoop_load_config()

    return w(data.alias):keys()
end

local function scoop_config_list(token) -- luacheck: no unused args
    local data = scoop_load_config()

    return w(data):keys()
end

local function scoop_bucket_known_list(token) -- luacheck: no unused args
    local file = io.open(scoop_folder() .. "\\apps\\scoop\\current\\buckets.json")
    -- If there is no such file, then close handle and return
    if file == nil then
        return w()
    end

    -- Read the whole file contents
    local contents = file:read("*a")
    file:close()

    local data = JSON:decode(contents)

    return w(data):keys()
end

local function scoop_bucket_list(token)
    local finder = matchers.create_files_matcher(scoop_folder() .. "\\buckets\\*")

    local list = finder(token)

    return list:filter(path.is_real_dir)
end

local function scoop_apps_list(token)
    local folders = {scoop_folder(), scoop_global_folder()}

    local list = w()
    for _, folder in pairs(folders) do
        local finder = matchers.create_files_matcher(folder .. "\\apps\\*")

        local new_list = finder(token)
        list = w(concat(list, new_list))
    end

    return list:filter(path.is_real_dir)
end

local function scoop_available_apps_list(token)
    -- search in default bucket
    local finder = matchers.create_files_matcher(scoop_folder() .. "\\apps\\scoop\\current\\bucket\\*.json")
    local list = finder(token)

    -- search in each installed bucket
    local buckets = scoop_bucket_list("")
    for _, bucket in pairs(buckets) do
        local bucket_folder = scoop_folder() .. "\\buckets\\" .. bucket

        -- check the bucket folder exists
        if clink.is_dir(bucket_folder .. "\\bucket") then
            bucket_folder = bucket_folder .. "\\bucket"
        end

        local b_finder = matchers.create_files_matcher(bucket_folder .. "\\*.json")
        local b_list = b_finder(token)
        list = w(concat(list, b_list))
    end

    -- remove ".json" of file name
    for k, v in pairs(list) do
        list[k] = v:gsub(".json", "")
    end

    return list
end

local function scoop_cache_apps_list(token)
    local cache_folder = os.getenv("SCOOP_CACHE")
    if not cache_folder then
        cache_folder = scoop_folder() .. "\\cache"
    end

    local finder = matchers.create_files_matcher(cache_folder .. "\\*")

    local list = finder(token)
    list = w(list:filter(path.is_real_dir))

    -- get name before "#" from cache list (name#version#url)
    for k, v in pairs(list) do
        list[k] = v:gsub("#.*$", "")
    end

    return list
end

local arch_parser =
    parser(
    {
        "32bit",
        "64bit",
        "arm64",
    }
)

local scoop_default_flags = {
    "--help",
    "-h"
}

local scoop_alias_parser =
    parser(
    {
        "add",
        "list" .. parser("-v", "--verbose"),
        "rm" .. parser({scoop_alias_list})
    }
)

local scoop_bucket_parser =
    parser(
    {
        "add" .. parser({scoop_bucket_known_list}),
        "list",
        "known",
        "rm" .. parser({scoop_bucket_list})
    }
)

local scoop_cache_parser =
    parser(
    {
        "show" .. parser({scoop_cache_apps_list, scoop_apps_list, "*"}),
        "rm" .. parser({scoop_cache_apps_list, "*"}, "--all", "-a")
    }
)

local scoop_cat_parser =
    parser(
    {
        scoop_available_apps_list,
        scoop_apps_list
    }
)

local scoop_cleanup_parser =
    parser(
    {
        scoop_apps_list,
        "*"
    },
    "--all",
    "-a",
    "--global",
    "-g",
    "--cache",
    "-k"
):loop(1)

local scoop_config_parser =
    parser(
    {
        "rm" .. parser({scoop_config_list}),
        scoop_config_list,
        "aria2-enabled" .. parser({"true", "false"}),
        "aria2-max-connection-per-server",
        "aria2-min-split-size",
        "aria2-options",
        "aria2-retry-wait",
        "aria2-split",
        "debug" .. parser({"true", "false"}),
        "proxy",
        "show_update_log" .. parser({"true", "false"}),
        "virustotal_api_key"
    }
)

local scoop_depends_parser =
    parser(
    {
        scoop_available_apps_list,
        scoop_apps_list
    },
    "--arch" .. arch_parser,
    "-a" .. arch_parser
)

local scoop_download_parser =
    parser(
    {
        scoop_available_apps_list
    },
    "--arch" .. arch_parser,
    "-a" .. arch_parser,
    "--force",
    "-f",
    "--no-hash-check",
    "-h",
    "--no-update-scoop",
    "-u"
)

local scoop_export_parser =
    parser(
    "--config",
    "-c"
):nofiles()

local scoop_hold_parser =
    parser(
    {
        scoop_apps_list
    },
    "--global",
    "-g"
)

local scoop_home_parser =
    parser(
    {
        scoop_available_apps_list,
        scoop_apps_list
    }
)

local scoop_info_parser =
    parser(
    {
        scoop_available_apps_list,
        scoop_apps_list
    },
    "--verbose",
    "-v"
)

local scoop_install_parser =
    parser(
    {
        scoop_available_apps_list
    },
    "--global",
    "-g",
    "--independent",
    "-i",
    "--no-cache",
    "-k",
    "--no-update-scoop",
    "-u",
    "--skip",
    "-s",
    "--arch" .. arch_parser,
    "-a" .. arch_parser
):loop(1)

local scoop_prefix_parser =
    parser(
    {
        scoop_apps_list
    }
)

local scoop_reset_parser =
    parser(
    {
        scoop_apps_list,
        "*",
    },
    "--all",
    "-a"
):loop(1)

local shim_subcommand_parser =
    parser(
    "--global",
    "-g"
)

local scoop_shim_parser =
    parser(
    {
        "add" .. shim_subcommand_parser,
        "rm" .. shim_subcommand_parser,
        "list" .. shim_subcommand_parser,
        "info" .. shim_subcommand_parser,
        "alter" .. shim_subcommand_parser,
    }
)

local scoop_status_parser =
    parser(
    "--local",
    "-l"
)

local scoop_unhold_parser =
    parser(
    {
        scoop_apps_list
    },
    "--global",
    "-g"
)

local scoop_uninstall_parser =
    parser(
    {
        scoop_apps_list
    },
    "--global",
    "-g",
    "--purge",
    "-p"
):loop(1)

local scoop_update_parser =
    parser(
    {
        scoop_apps_list,
        "*"
    },
    "--force",
    "-f",
    "--global",
    "-g",
    "--independent",
    "-i",
    "--no-cache",
    "-k",
    "--skip",
    "-s",
    "--quiet",
    "-q",
    "--all",
    "-a"
):loop(1)

local scoop_virustotal_parser =
    parser(
    {
        scoop_apps_list,
        "*"
    },
    "--all",
    "-a",
    "--scan",
    "-s",
    "--no-depends",
    "-n",
    "--no-update-scoop",
    "-u",
    "--passthru",
    "-p"
):loop(1)

local scoop_help_parser =
    parser(
    {
        "alias",
        "bucket",
        "cache",
        "cat",
        "checkup",
        "cleanup",
        "config",
        "create",
        "depends",
        "download",
        "export",
        "help",
        "home",
        "hold",
        "import",
        "info",
        "install",
        "list",
        "prefix",
        "reset",
        "search",
        "shim",
        "status",
        "unhold",
        "uninstall",
        "update",
        "virustotal",
        "which"
    },
    "/?",
    "--help",
    "-h",
    "--version"
)

local scoop_parser = parser()
scoop_parser:set_flags(scoop_default_flags)
scoop_parser:set_arguments(
    {
        scoop_alias_list,
        "alias" .. scoop_alias_parser,
        "bucket" .. scoop_bucket_parser,
        "cache" .. scoop_cache_parser,
        "cat" .. scoop_cat_parser,
        "checkup",
        "cleanup" .. scoop_cleanup_parser,
        "config" .. scoop_config_parser,
        "create",
        "depends" .. scoop_depends_parser,
        "download" .. scoop_download_parser,
        "export" .. scoop_export_parser,
        "help" .. scoop_help_parser,
        "hold" .. scoop_hold_parser,
        "home" .. scoop_home_parser,
        "import",
        "info" .. scoop_info_parser,
        "install" .. scoop_install_parser,
        "list",
        "prefix" .. scoop_prefix_parser,
        "reset" .. scoop_reset_parser,
        "search",
        "shim" .. scoop_shim_parser,
        "status" .. scoop_status_parser,
        "unhold" .. scoop_unhold_parser,
        "uninstall" .. scoop_uninstall_parser,
        "update" .. scoop_update_parser,
        "virustotal" .. scoop_virustotal_parser,
        "which"
    }
)
clink.arg.register_parser("scoop", scoop_parser)
