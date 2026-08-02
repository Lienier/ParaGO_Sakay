const timeoutError = (name, timeoutMs) =>
  new Error(`${name} shutdown exceeded ${timeoutMs}ms`);

const withTimeout = async (operation, { name, timeoutMs }) => {
  let timer;
  try {
    return await Promise.race([
      operation,
      new Promise((_, reject) => {
        timer = setTimeout(() => reject(timeoutError(name, timeoutMs)), timeoutMs);
        timer.unref?.();
      }),
    ]);
  } finally {
    clearTimeout(timer);
  }
};

const createShutdownController = ({
  name,
  timeoutMs,
  stopAccepting = async () => {},
  drain = async () => {},
  closeDependencies = async () => {},
  log = () => {},
}) => {
  let activeShutdown = null;

  const shutdown = (signal = 'shutdown') => {
    if (activeShutdown) return activeShutdown;
    activeShutdown = withTimeout(
      (async () => {
        log(`${name} received ${signal}; stopping`);
        await stopAccepting();
        await drain();
        await closeDependencies();
        log(`${name} shutdown complete`);
        return { signal, timedOut: false };
      })(),
      { name, timeoutMs }
    );
    return activeShutdown;
  };

  return {
    shutdown,
    get isShuttingDown() {
      return activeShutdown != null;
    },
  };
};

const closeHttpServer = async (server) => {
  if (!server?.listening) return;
  await new Promise((resolve, reject) => {
    server.close((error) => (error ? reject(error) : resolve()));
    server.closeIdleConnections?.();
  });
};

module.exports = {
  createShutdownController,
  closeHttpServer,
  withTimeout,
};
