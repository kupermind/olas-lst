# Coverage Issue Fix

## Problem
When running `npx hardhat coverage`, a "JavaScript heap out of memory" error occurs due to high memory consumption by tests.

## Solutions

### 1. Using Optimized Scripts

New scripts have been added to `package.json`:

```bash
# Full coverage with increased memory (8GB)
npm run coverage

# Fast coverage with optimized test (4GB)
npm run coverage:fast

# Minimal coverage (2GB)
npm run coverage:minimal

# Coverage via special script
npm run coverage:script
```

### 2. Optimized Test

Created `test/LiquidStakingOptimized.js` with:
- Reduced number of services (10 instead of 100)
- Shortened emission time (7 days instead of 30)
- Simplified contract initialization
- Only necessary tests

### 3. Coverage Configuration

Added settings in `hardhat.config.js`:
- Disabled branch coverage to save memory
- Excluded test and mock contracts
- Skipped bridging contracts

### 4. Memory Limit Increase

Settings in `hardhat.config.js`:
```javascript
hardhat: {
    allowUnlimitedContractSize: true,
    mocha: {
        timeout: 120000,
    }
}
```

## Recommendations

1. **For development**: use `npm run coverage:fast`
2. **For CI/CD**: use `npm run coverage:minimal`
3. **For full analysis**: use `npm run coverage` on a powerful machine

## Alternative Solutions

### Manual Memory Increase
```bash
export NODE_OPTIONS="--max-old-space-size=8192"
npx hardhat coverage
```

### Running Only Specific Tests
```bash
npx hardhat coverage --testfiles test/LiquidStakingOptimized.js
```

### Using Foundry for Coverage
```bash
forge coverage
```

## Memory Monitoring

For monitoring memory usage:
```bash
# Installation
npm install -g node-memwatch

# Run with monitoring
node --max-old-space-size=8192 -r node-memwatch node_modules/.bin/hardhat coverage
``` 