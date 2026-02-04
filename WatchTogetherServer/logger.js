const pino = require("pino");

const { LOG_LEVEL } = require("./config");

const logger = pino({
  level: LOG_LEVEL,
  base: { service: "watch-together-server" },
  timestamp: pino.stdTimeFunctions.isoTime,
});

module.exports = logger;
