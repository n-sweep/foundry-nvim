local Logging = {
    named_loggers = {}
}
Logging.__index = Logging


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


function Logging:get_logger(name)
    return Logging.named_loggers[name]
end


function Logging:log(message)
    local file = io.open(self.filename, 'a')

    if file then
        local timestamp = os.date('%Y-%m-%d %H:%M:%S')
        file:write(string.format('%s %s\n', timestamp, message))
        file:close()
    else
        error('failed to open logfile: ' .. self.filename)
    end

end


function Logging:info(msg) self:log('INFO:' .. msg) end
function Logging:warn(msg) self:log('WARN:' .. msg) end
function Logging:error(msg) self:log('ERR:' .. msg) end


return Logging
