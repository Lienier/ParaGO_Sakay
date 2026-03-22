const hasOwn = (value, key) => Object.prototype.hasOwnProperty.call(value || {}, key);

const isPlainObject = (value) =>
  Boolean(value) && typeof value === 'object' && !Array.isArray(value);

const pickDefined = (source, allowedKeys) =>
  allowedKeys.reduce((accumulator, key) => {
    if (hasOwn(source, key) && source[key] !== undefined) {
      accumulator[key] = source[key];
    }
    return accumulator;
  }, {});

module.exports = {
  hasOwn,
  isPlainObject,
  pickDefined,
};
