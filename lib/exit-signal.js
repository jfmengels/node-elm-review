class ExitSignal extends Error {
  /**
   * @param {number} exitCode
   */
  constructor(exitCode) {
    super(`Exit requested with code ${exitCode}`);
    this.name = 'ExitSignal';
    this.exitCode = exitCode;
  }
}

/**
 * @param {unknown} error
 * @returns {error is ExitSignal}
 */
function isExitSignal(error) {
  return error instanceof ExitSignal;
}

/**
 * @param {unknown} error
 * @returns {void}
 */
function rethrowIfExitSignal(error) {
  if (isExitSignal(error)) {
    throw error;
  }
}

module.exports = {
  ExitSignal,
  isExitSignal,
  rethrowIfExitSignal
};
