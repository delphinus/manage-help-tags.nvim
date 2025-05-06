---@class ManageHelpTags
---@field private dir? string
---@field private _cache? table<string, table<string, string>>
local M = {}

---@class ManageHelpTagsUserOpts
---@field auto_generate? boolean Merge all help tags after installing/updating by lazy.nvim (default: `true`)
---@field dir? string Directory to store merged help tags (default: `stdpath("config")/after/doc`)

---@param opts? ManageHelpTagsUserOpts
function M.setup(opts)
  opts = vim.tbl_extend(
    "force",
    { auto_generate = true, dir = vim.fs.joinpath(vim.fn.stdpath "config", "after", "doc") },
    opts or {}
  )
  vim.validate("auto_generate", opts.auto_generate, "boolean")
  vim.validate("dir", opts.dir, "string")
  M.dir = opts.dir

  if opts.auto_generate then
    vim.api.nvim_create_autocmd("User", {
      pattern = { "LazyInstall", "LazyUpdate" },
      callback = function()
        local ok, lazy = pcall(require, "lazy")
        if ok then
          local dirs = vim
            .iter(lazy.plugins())
            :map(function(plugin)
              return plugin.dir
            end)
            :totable()
          M.generate_tags(dirs)
        end
      end,
    })
  end
end

function M.info(...)
  pcall(vim.notify, ...)
end

---@param dirs string[]
---@return nil
function M.generate_tags(dirs)
  M.info "Start generating tags"
  local Path = require "plenary.path"
  local result = {}
  for _, dir in ipairs(dirs) do
    M.gather_tags(result, vim.fs.joinpath(dir, "doc"))
  end
  local dir = Path:new(M.dir)
  dir:mkdir { parents = true }
  for tags, lines in pairs(result) do
    local joined = vim
      .iter(lines)
      :map(function(fields)
        return table.concat(fields, "\t")
      end)
      :totable()
    table.sort(joined)
    dir:joinpath(tags):write(table.concat(joined, "\n"), "w")
  end
  M.info "Finish generating tags"
end

---@param opts { lang?: string }
---@return fun(): nil
function M.telescope(opts)
  return function()
    local lang = opts.lang
    local o = vim.tbl_extend("force", {
      entry_index = {
        filename = function(t, _)
          local tag = rawget(t, "display")
          local cache = M.cache()[tag]
          if cache then
            return lang and cache[lang] or cache[vim.o.helplang] or cache.en
          end
        end,
      },
    }, vim.deepcopy(opts))
    require("telescope.builtin").help_tags(o)
  end
end

---@private
---@param result table<string, string[][]>
---@param doc string
function M.gather_tags(result, doc)
  if not vim.uv.fs_stat(doc) then
    return
  end
  local Path = require "plenary.path"
  for name, typ in vim.fs.dir(doc) do
    if typ == "file" and (name == "tags" or name:match "^tags(%-..)$") then
      result[name] = result[name] or {}
      for _, line in ipairs(Path:new(doc, name):readlines()) do
        local fields = vim.split(line, "\t")
        if #fields == 3 and fields[1] ~= "!_TAG_FILE_ENCODING" then
          local p = Path:new(fields[2])
          local path = p:is_absolute() and p.filename or Path:new(doc, p).filename
          table.insert(result[name], { fields[1], path, fields[3] })
        end
      end
    end
  end
end

---@private
---@param source table<string, string[][]>
---@return table<string, table<string, string>>
function M.make_cache(source)
  local cache = {}
  for tags, lines in pairs(source) do
    local lang = tags == "tags" and "en" or tags:match "^tags%-(..)$"
    for _, fields in ipairs(lines) do
      cache[fields[1]] = cache[fields[1]] or {}
      cache[fields[1]][lang] = fields[2]
    end
  end
  return cache
end

---@private
---@return table<string, table<string, string>>
function M.cache()
  if not M._cache then
    local source = {}
    M.gather_tags(source, M.dir)
    M._cache = M.make_cache(source)
  end
  return M._cache
end

return M
