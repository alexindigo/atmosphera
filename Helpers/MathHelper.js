// Math helper functions for calculator functionality
var MathHelper = {
    // Basic arithmetic operations
    add: (a, b) => a + b,
    subtract: (a, b) => a - b,
    multiply: (a, b) => a * b,
    divide: (a, b) => b !== 0 ? a / b : NaN,
    
    // Power and roots
    pow: (base, exponent) => Math.pow(base, exponent),
    sqrt: (x) => x >= 0 ? Math.sqrt(x) : NaN,
    cbrt: (x) => Math.cbrt(x),
    
    // Trigonometric functions (in radians)
    sin: (x) => Math.sin(x),
    cos: (x) => Math.cos(x),
    tan: (x) => Math.tan(x),
    asin: (x) => Math.asin(x),
    acos: (x) => Math.acos(x),
    atan: (x) => Math.atan(x),
    
    // Logarithmic functions
    log: (x) => x > 0 ? Math.log(x) : NaN,
    log10: (x) => x > 0 ? Math.log10(x) : NaN,
    log2: (x) => x > 0 ? Math.log2(x) : NaN,
    
    // Other mathematical functions
    abs: (x) => Math.abs(x),
    floor: (x) => Math.floor(x),
    ceil: (x) => Math.ceil(x),
    round: (x) => Math.round(x),
    min: (...args) => Math.min(...args),
    max: (...args) => Math.max(...args),
    
    // Constants
    PI: Math.PI,
    E: Math.E,
    
    // Factorial
    factorial: (n) => {
        if (n < 0 || n !== Math.floor(n)) return NaN;
        if (n === 0 || n === 1) return 1;
        let result = 1;
        for (let i = 2; i <= n; i++) {
            result *= i;
        }
        return result;
    },
    
    // Percentage
    percent: (value, total) => (value / total) * 100,
    
    // Degrees to radians and vice versa
    toRadians: (degrees) => degrees * (Math.PI / 180),
    toDegrees: (radians) => radians * (180 / Math.PI),
    
    // Safe evaluation with math functions
    evaluate: (expression) => {
        try {
            // Replace common math functions with MathHelper equivalents
            let processedExpr = expression
                .replace(/\bpi\b/gi, 'MathHelper.PI')
                .replace(/\be\b/gi, 'MathHelper.E')
                .replace(/\bsin\b/gi, 'MathHelper.sin')
                .replace(/\bcos\b/gi, 'MathHelper.cos')
                .replace(/\btan\b/gi, 'MathHelper.tan')
                .replace(/\basin\b/gi, 'MathHelper.asin')
                .replace(/\bacos\b/gi, 'MathHelper.acos')
                .replace(/\batan\b/gi, 'MathHelper.atan')
                .replace(/\blog\b/gi, 'MathHelper.log')
                .replace(/\blog10\b/gi, 'MathHelper.log10')
                .replace(/\blog2\b/gi, 'MathHelper.log2')
                .replace(/\bsqrt\b/gi, 'MathHelper.sqrt')
                .replace(/\bcbrt\b/gi, 'MathHelper.cbrt')
                .replace(/\bpow\b/gi, 'MathHelper.pow')
                .replace(/\babs\b/gi, 'MathHelper.abs')
                .replace(/\bfloor\b/gi, 'MathHelper.floor')
                .replace(/\bceil\b/gi, 'MathHelper.ceil')
                .replace(/\bround\b/gi, 'MathHelper.round')
                .replace(/\bmin\b/gi, 'MathHelper.min')
                .replace(/\bmax\b/gi, 'MathHelper.max')
                .replace(/\bfactorial\b/gi, 'MathHelper.factorial')
                .replace(/\bpercent\b/gi, 'MathHelper.percent')
                .replace(/\btoRadians\b/gi, 'MathHelper.toRadians')
                .replace(/\btoDegrees\b/gi, 'MathHelper.toDegrees');
            
            // Evaluate the expression
            const result = Function('MathHelper', 'return ' + processedExpr)(MathHelper);
            
            // Check if result is valid
            if (isNaN(result) || !isFinite(result)) {
                return null;
            }
            
            return result;
        } catch (error) {
            return null;
        }
    },
    
    // Format result for display
    formatResult: (result) => {
        if (result === null || isNaN(result) || !isFinite(result)) {
            return "Error";
        }
        
        // For very large or small numbers, use scientific notation
        if (Math.abs(result) >= 1e10 || (Math.abs(result) < 1e-10 && result !== 0)) {
            return result.toExponential(6);
        }
        
        // For integers, don't show decimal places
        if (Number.isInteger(result)) {
            return result.toString();
        }
        
        // For decimals, limit to 8 significant digits
        return parseFloat(result.toPrecision(8)).toString();
    }
}; 