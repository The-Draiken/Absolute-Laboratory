Helpers = Helpers or {}

---@param s string
---@return string
function Helpers:SanitizeStringForFind(s)
	-- Magic chars in Lua patterns: ( ) . % + - * ? [ ^ $
	return (s:gsub("([%(%)%.%%%+%-%*%?%[%^%$])", "%%%1"))
end

---@param params string[]
---@param count number
function Helpers:unpackParamTable(params, count, i)
	i = i or 1
	if i <= count then
		return params[i], self:unpackParamTable(params, count, i + 1)
	end
end
