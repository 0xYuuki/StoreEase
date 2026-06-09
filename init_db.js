const sqlite3 = require('sqlite3').verbose();
const path = require('path');

const dbPath = path.resolve(__dirname, 'database.sqlite');
const db = new sqlite3.Database(dbPath, (err) => {
    if (err) {
        console.error('Error opening database', err.message);
        process.exit(1);
    }
    console.log('Connected to the SQLite database.');
});

function dateOffset(days) {
    const d = new Date();
    d.setDate(d.getDate() + days);
    return d.toISOString().replace('T', ' ').substring(0, 19);
}

// Helper promise wrapper for database queries
const runQuery = (query, params = []) => new Promise((resolve, reject) => {
    db.run(query, params, function(err) {
        if (err) reject(err);
        else resolve(this);
    });
});

async function initialize() {
    try {
        await runQuery(`DROP TABLE IF EXISTS SaleItems`);
        await runQuery(`DROP TABLE IF EXISTS Sales`);
        await runQuery(`DROP TABLE IF EXISTS Products`);
        console.log('Existing tables dropped.');

        await runQuery(`
            CREATE TABLE Products (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                barcode_string TEXT UNIQUE NOT NULL,
                name TEXT NOT NULL,
                price INTEGER NOT NULL
            )
        `);
        console.log('Products table created.');

        await runQuery(`
            CREATE TABLE Sales (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
                total_amount INTEGER NOT NULL
            )
        `);
        console.log('Sales table created.');

        await runQuery(`
            CREATE TABLE SaleItems (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                sale_id INTEGER NOT NULL,
                product_id INTEGER NOT NULL,
                quantity INTEGER NOT NULL,
                price INTEGER NOT NULL,
                FOREIGN KEY (sale_id) REFERENCES Sales(id) ON DELETE CASCADE,
                FOREIGN KEY (product_id) REFERENCES Products(id) ON DELETE SET NULL
            )
        `);
        console.log('SaleItems table created.');

    } catch (err) {
        console.error('Initialization error:', err.message);
    } finally {
        db.close((err) => {
            if (err) {
                console.error('Error closing database', err.message);
            }
            console.log('Database connection closed.');
        });
    }
}

initialize();
