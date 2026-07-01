describe('Logging', function()
    local Logging
    local test_log = '/tmp/foundry_test.log'
    local log_name = 'test_logger'

    before_each(function()
        package.loaded['foundry.logging'] = nil
        Logging = require('foundry.logging')
        os.remove(test_log)
    end)

    it('creates a logger', function()
        local logger = Logging:new(test_log, log_name)
        assert.is_not_nil(logger)
        assert.are.equal(test_log, logger.filename)
        assert.are.equal(log_name, logger.name)
    end)

    it('retrieves a logger by name', function()
        local logger1 = Logging:new(test_log, log_name)
        local logger2 = Logging:get_logger(log_name)
        assert.are.equal(logger1, logger2)
    end)

    it('logs messages at different levels', function()
        local logger = Logging:new(test_log, 'test')

        logger:info('info message')
        logger:warn('warning message')
        logger:error('error message')

        local file = assert(io.open(test_log, 'r'))
        local content = file:read('*all')
        file:close()

        assert.is_not_nil(content:match('INFO:info message'))
        assert.is_not_nil(content:match('WARN:warning message'))
        assert.is_not_nil(content:match('ERR:error message'))
    end)

end)
