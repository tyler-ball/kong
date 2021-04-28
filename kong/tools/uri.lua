local _M = {}


local string_char = string.char
local string_upper = string.upper
local string_find = string.find
local string_sub = string.sub
local string_byte = string.byte
local string_format = string.format
local tonumber = tonumber
local table_concat = table.concat
local ngx_re_gsub = ngx.re.gsub


local RESERVED_CHARACTERS = {
  [0x21] = true, -- !
  [0x23] = true, -- #
  [0x24] = true, -- $
  [0x25] = true, -- %
  [0x26] = true, -- &
  [0x27] = true, -- '
  [0x28] = true, -- (
  [0x29] = true, -- )
  [0x2A] = true, -- *
  [0x2B] = true, -- +
  [0x2C] = true, -- ,
  [0x2F] = true, -- /
  [0x3A] = true, -- :
  [0x3B] = true, -- ;
  [0x3D] = true, -- =
  [0x3F] = true, -- ?
  [0x40] = true, -- @
  [0x5B] = true, -- [
  [0x5D] = true, -- ]
}
local TMP_OUTPUT = require("table.new")(16, 0)
local EMPTY = ""
local SLASH = "/"
local DOT_BYTE = string_byte(".")
local SLASH_BYTE = string_byte(SLASH)


local function percent_decode(m)
    local hex = m[1]
    local num = tonumber(hex, 16)
    if RESERVED_CHARACTERS[num] then
      return string_upper(m[0])
    end

    return string_char(num)
end


local function escape(m)
  return string_format("%%%02X", string_byte(m[0]))
end


function _M.normalize(uri, merge_slashes)
  -- check for simple cases and early exit
  if uri == EMPTY or uri == SLASH then
    return uri
  end

  -- check if uri needs to be percent-decoded
  -- (this can in some cases lead to unnecessary percent-decoding)
  if string_find(uri, "%", 1, true) then
    -- decoding percent-encoded triplets of unreserved characters
    uri = ngx_re_gsub(uri, "%([\\dA-F]{2})", percent_decode, "joi")
  end

  -- check if the uri contains a dot
  -- (this can in some cases lead to unnecessary dot removal processing)
  if string_find(uri, ".", 1, true) == nil  then
    if not merge_slashes then
      return uri
    end

    if string_find(uri, "//", 1, true) == nil then
      return uri
    end
  end

  -- remove dot segments and possibly merge slashes

  local n -- current index in TMP_OUTPUT
  local s -- current index to start searching slash from uri
  local z -- minimum number of TMP_OUTPUT to preserve

  if string_byte(uri, 1) == SLASH_BYTE then
    -- ensures that the slash prefix is preserved
    TMP_OUTPUT[1] = SLASH
    n = 1
    s = 2
    z = 1

  else
    -- no need to preserve any prefix, empty string is fine as result
    n = 0
    s = 1
    z = 0
  end

  while true do
    -- find next slash
    local e = string_find(uri, SLASH, s, true)
    if not e then
      -- no slash found means that we have to process the last path segment
      local b1 = string_byte(uri, s)
      if b1 == nil then
        -- the last path segment is empty
        break
      end

      if b1 == DOT_BYTE then
        local b2 = string_byte(uri, s + 1)
        if b2 == DOT_BYTE then
          if string_byte(uri, s + 2) == nil then -- ..
            -- the last path segment is .. which means that the previous segment
            -- is to be removed in case there is something to remove
            if n > z then
              -- remove previous path segment
              TMP_OUTPUT[n] = nil
              n = n - 1
            end

            break
          end

        elseif b2 == nil then -- .
          -- the last path segment is . which means that it can be ignored
          break
        end
      end

      -- the last path segment
      n = n + 1
      TMP_OUTPUT[n] = string_sub(uri, s, e)
      break
    end

    -- slash found

    local c = e - s
    if c == 0 then -- //
      -- empty path segment detected
      if not merge_slashes then
        -- if the merge_slashes is not enabled the slash is preserved
        n = n + 1
        TMP_OUTPUT[n] = SLASH
      end

    else
      local b1 = string_byte(uri, s)
      if c == 1 and b1 == DOT_BYTE then -- /./
        -- path segment is . which means that it can be ignored
        goto next
      end

      if c == 2 and b1 == DOT_BYTE and string_byte(uri, s + 1) == DOT_BYTE then -- /../
        -- path segment is .. which means that the previous segment is to be
        -- removed in case there is something to remove
        if n > z then
          TMP_OUTPUT[n] = nil
          n = n - 1
        end

      else

        -- path segment
        n = n + 1
        TMP_OUTPUT[n] = string_sub(uri, s, e) -- path segment
      end
    end

    ::next::

    -- increase the next slash search index to be one after the index where
    -- the previous slash was found
    s = e + 1
  end

  if n == 0 then
    -- in case there is nothing in our output buffer, we will just return empty
    return EMPTY
  end

  if n == 1 then
    -- in case there is just one segment in our output buffer, we can just return it
    return TMP_OUTPUT[1]
  end

  -- otherwise we concatenate the output and return that as a normalized uri
  uri = table_concat(TMP_OUTPUT, nil, 1, n)

  return uri
end


function _M.escape(uri)
  return ngx_re_gsub(uri, "[^!#$&'()*+,/:;=?@[\\]A-Z\\d-_.~%]", escape, "joi")
end


return _M
