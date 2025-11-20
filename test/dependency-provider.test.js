const { prioritizePinnedIndirectVersion } = require('../lib/dependency-provider');

describe('prioritizePinnedIndirectVersion', () => {
  const versions = ['1.0.5', '1.0.4', '1.0.3', '1.0.2', '1.0.1', '1.0.0'];

  const testPinning = (
      /** @type {string | void} */ pinnedVersion,
      /** @type {string[]} */ expectedResult
  ) => {
    expect(prioritizePinnedIndirectVersion(versions, pinnedVersion)).toEqual(
      expectedResult
    );
  };

  test('retains order when no pinned indirect dependency', () => {
    testPinning(undefined, versions);
  });

  test("retains order when pinned version doesn't exist", () => {
    testPinning('1.0.6', versions);
  });

  test('retains order if already at latest', () => {
    testPinning('1.0.5', versions);
  });

  test("prioritizes a version in the middle, if we're pinned to it", () => {
    const expected = [
      // First, try the pinned version
      '1.0.3',
      // Then, try upgrading
      '1.0.4',
      '1.0.5',
      // Then, try downgrading
      '1.0.2',
      '1.0.1',
      '1.0.0'
    ];
    testPinning('1.0.3', expected);
  });

  test("prioritizes first version, if we're pinned to it", () => {
    testPinning('1.0.0', [...versions].sort());
  });
});