config.target = 'core'

local function clean_path(p)
    -- todo: replace with dfhack.filesystem call?
    return p:gsub('\\', '/'):gsub('//', '/'):gsub('/$', '')
end

local fs = dfhack.filesystem
local old_cwd = clean_path(fs.getcwd())
local function restore_cwd()
    fs.chdir(old_cwd)
end

function test.getDFPath()
    expect.eq(clean_path(dfhack.getDFPath()), old_cwd)
end

function test.get_initial_cwd()
    expect.eq(clean_path(dfhack.filesystem.get_initial_cwd()), clean_path(dfhack.getDFPath()))
end

function test.getDFPath_chdir()
    dfhack.with_finalize(restore_cwd, function()
        fs.chdir('data')
        expect.eq(clean_path(dfhack.getDFPath()), old_cwd)
        expect.ne(clean_path(dfhack.getDFPath()), clean_path(fs.getcwd()))
    end)
end

function test.getHackPath()
    expect.eq(clean_path(dfhack.getHackPath()), clean_path(dfhack.getDFPath() .. '/hack/'))
end

function test.getHackPath_chdir()
    dfhack.with_finalize(restore_cwd, function()
        fs.chdir('hack')
        expect.eq(clean_path(dfhack.getHackPath()), clean_path(old_cwd .. '/hack/'))
        expect.eq(clean_path(dfhack.getHackPath()), clean_path(fs.getcwd()))
    end)
end

function test.strict_wrap()
    wrap = string.strict_wrap

    -- simple text
    expect.table_eq(
        wrap([[
this is a simple text]], 7),
        {
            "this ",
            "is a ",
            "simple ",
            "text"
        }
    )

    -- keep endline spaces
    expect.table_eq(
        wrap([[
this is a    simple text]], 7),
        {
            "this ",
            "is ",
            "a    ",
            "simple ",
            "text"
        }
    )


    -- keep text leading spaces
    expect.table_eq(
        wrap([[
  this is a simple text]], 7),
        {
            "  this ",
            "is a ",
            "simple ",
            "text"
        }
    )

    -- keep text trailing spaces
    expect.table_eq(
        wrap([[
this is a simple text   ]], 7),
        {
            "this ",
            "is a ",
            "simple ",
            "text   "
        }
    )

    -- cat words longer than max width
    expect.table_eq(
        wrap([[
thiswordistoolong is a simple text]], 7),
        {
            "thiswor",
            "distool",
            "ong is ",
            "a ",
            "simple ",
            "text"
        }
    )

    -- take into account existing new line
    expect.table_eq(
        wrap([[
this is a sim
ple text]], 7),
        {
            "this ",
            "is a ",
            "sim\n",
            "ple ",
            "text"
        }
    )

    -- take into account existing new lines
    expect.table_eq(
        wrap([[
this is a sim


ple text]], 7),
        {
            "this ",
            "is a ",
            "sim\n",
            "\n",
            "\n",
            "ple ",
            "text"
        }
    )
end
