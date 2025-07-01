const { execSync } = require('child_process');

console.log('Starting coverage with memory optimizations...');

try {
    // Увеличиваем лимит памяти Node.js
    const maxOldSpaceSize = process.env.NODE_OPTIONS ? 
        process.env.NODE_OPTIONS : '--max-old-space-size=8192';
    
    // Запускаем coverage с оптимизированными настройками
    const command = `node ${maxOldSpaceSize} node_modules/.bin/hardhat coverage --testfiles test/LiquidStakingOptimized.js`;
    
    console.log(`Executing: ${command}`);
    execSync(command, { 
        stdio: 'inherit',
        env: {
            ...process.env,
            NODE_OPTIONS: maxOldSpaceSize
        }
    });
    
    console.log('Coverage completed successfully!');
} catch (error) {
    console.error('Coverage failed:', error.message);
    process.exit(1);
} 