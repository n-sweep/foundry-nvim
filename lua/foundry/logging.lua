--- Simple logging module for foundry-nvim
--- @class Logging
--- @field filename string Path to the log file
--- @field name string|nil Optional logger name for retrieval
--- @field named_loggers table<string, Logging> Registry of named loggers
local Logging = {
    named_loggers = {}
}
Logging.__index = Logging


--- Creates a new logger instance
--- @param filename string|nil Path to log file (auto-generated if nil)
--- @param name string|nil Optional name to register logger for later retrieval
--- @return Logging logger The logger instance
function Logging:new(filename, name)
    local obj = {
        filename = filename or os.date('%Y-%m-%d_%H:%M:%S') .. '.log',
        name = name
    }

    setmetatable(obj, Logging)

    if name ~= nil then
        Logging.named_loggers[name] = obj
    end

    return obj
end


--- Retrieves a named logger from the registry
--- @param name string The name of the logger to retrieve
--- @return Logging logger The logger instance, or nil if not found
function Logging:get_logger(name)
    if not Logging.named_loggers[name] then
        Logging.named_loggers[name] = Logging:new(nil, name)
    end
    return Logging.named_loggers[name]
end


--- Writes a timestamped message to the log file
--- @param message string The message to log
function Logging:_log(message)
    local file = io.open(self.filename, 'a')

    if file then
        local timestamp = os.date('%Y-%m-%d %H:%M:%S')
        file:write(string.format('%s %s\n', timestamp, message))
        file:close()
    else
        error('failed to open logfile: ' .. self.filename)
    end

end


--- Logs an info-level message
--- @param msg string The message to log
function Logging:info(msg) self:_log('INFO:' .. msg) end

--- Logs a warning-level message
--- @param msg string The message to log
function Logging:warn(msg) self:_log('WARN:' .. msg) end

--- Logs an error-level message
--- @param msg string The message to log
function Logging:error(msg) self:_log('ERR:' .. msg) end


return Logging
