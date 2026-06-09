const express = require('express');
const sqlite3 = require('sqlite3').verbose();
const path = require('path');
const cors = require('cors');

const app = express();
const PORT = process.env.PORT || 3000;

app.use(cors());
app.use(express.static(path.join(__dirname, 'public')));
app.use(express.json());

const dbPath = path.resolve(__dirname, 'database.sqlite');
const db = new sqlite3.Database(dbPath, (err) => {
    if (err) {
        console.error('Error connecting to the SQLite database', err.message);
    } else {
        console.log('Connected to the SQLite database');
    }
});

// API endpoint to fetch a product by barcode
app.get('/api/products/:barcode', (req, res) => {
    // Trim the barcode to remove any trailing whitespace or hidden characters from scanner
    const barcode = req.params.barcode.trim();

    db.get('SELECT * FROM Products WHERE barcode_string = ?', [barcode], (err, row) => {
        if (err) {
            console.error(err.message);
            return res.status(500).json({ error: 'Internal server error' });
        }
        
        if (row) {
            res.json(row);
        } else {
            res.status(404).json({ error: 'Item Not Found: Please scan again or enter manually.' });
        }
    });
});

// CRUD API Endpoints for Inventory Management

// GET /api/products - List all products sorted alphabetically
app.get('/api/products', (req, res) => {
    db.all('SELECT * FROM Products ORDER BY name ASC', [], (err, rows) => {
        if (err) {
            console.error(err.message);
            return res.status(500).json({ error: 'Internal server error' });
        }
        res.json(rows);
    });
});

// POST /api/products - Create a new product
app.post('/api/products', (req, res) => {
    const { barcode_string, name, price } = req.body;

    if (!barcode_string || !name || price === undefined) {
        return res.status(400).json({ error: 'Missing required fields: barcode_string, name, price' });
    }

    // Convert decimal price input (e.g. ₱1.50) into cents integer (150) for robust calculation
    const priceCents = Math.round(parseFloat(price) * 100);

    db.run(
        'INSERT INTO Products (barcode_string, name, price) VALUES (?, ?, ?)',
        [barcode_string.trim(), name.trim(), priceCents],
        function(err) {
            if (err) {
                console.error(err.message);
                if (err.message.includes('UNIQUE constraint failed')) {
                    return res.status(400).json({ error: 'Product with this barcode already exists.' });
                }
                return res.status(500).json({ error: 'Internal server error' });
            }
            res.json({ id: this.lastID, barcode_string, name, price: priceCents });
        }
    );
});

// PUT /api/products/:id - Update an existing product
app.put('/api/products/:id', (req, res) => {
    const { id } = req.params;
    const { barcode_string, name, price } = req.body;

    if (!barcode_string || !name || price === undefined) {
        return res.status(400).json({ error: 'Missing required fields' });
    }

    const priceCents = Math.round(parseFloat(price) * 100);

    db.run(
        'UPDATE Products SET barcode_string = ?, name = ?, price = ? WHERE id = ?',
        [barcode_string.trim(), name.trim(), priceCents, id],
        function(err) {
            if (err) {
                console.error(err.message);
                if (err.message.includes('UNIQUE constraint failed')) {
                    return res.status(400).json({ error: 'Product with this barcode already exists.' });
                }
                return res.status(500).json({ error: 'Internal server error' });
            }
            if (this.changes === 0) {
                return res.status(404).json({ error: 'Product not found.' });
            }
            res.json({ id: parseInt(id), barcode_string, name, price: priceCents });
        }
    );
});

// DELETE /api/products/:id - Remove a product
app.delete('/api/products/:id', (req, res) => {
    const { id } = req.params;

    db.run('DELETE FROM Products WHERE id = ?', [id], function(err) {
        if (err) {
            console.error(err.message);
            return res.status(500).json({ error: 'Internal server error' });
        }
        if (this.changes === 0) {
            return res.status(404).json({ error: 'Product not found.' });
        }
        res.json({ success: true, message: 'Product deleted successfully.' });
    });
});

// POST /api/sales - Save a completed sale transaction
app.post('/api/sales', (req, res) => {
    const { total_amount, items } = req.body;

    if (!items || !Array.isArray(items) || items.length === 0 || total_amount === undefined) {
        return res.status(400).json({ error: 'Invalid checkout payload.' });
    }

    db.serialize(() => {
        db.run('BEGIN TRANSACTION');

        db.run(
            'INSERT INTO Sales (total_amount) VALUES (?)',
            [total_amount],
            function(err) {
                if (err) {
                    db.run('ROLLBACK');
                    console.error(err.message);
                    return res.status(500).json({ error: 'Failed to save transaction.' });
                }
                
                const saleId = this.lastID;
                const stmt = db.prepare('INSERT INTO SaleItems (sale_id, product_id, quantity, price) VALUES (?, ?, ?, ?)');
                
                let count = 0;
                let errorOccurred = false;

                items.forEach(item => {
                    stmt.run([saleId, item.product_id, item.quantity, item.price], (err) => {
                        if (err) {
                            errorOccurred = true;
                            console.error(err.message);
                        }
                        
                        count++;
                        if (count === items.length) {
                            stmt.finalize(() => {
                                if (errorOccurred) {
                                    db.run('ROLLBACK');
                                    res.status(500).json({ error: 'Failed to save transaction items.' });
                                } else {
                                    db.run('COMMIT');
                                    res.json({ success: true, sale_id: saleId });
                                }
                            });
                        }
                    });
                });
            }
        );
    });
});

// GET /api/analytics - Sales analytics KPIs and line chart data
app.get('/api/analytics', (req, res) => {
    // 1. KPI Aggregations
    const todayQuery = `SELECT COALESCE(SUM(total_amount), 0) AS total FROM Sales WHERE date(timestamp, 'localtime') = date('now', 'localtime')`;
    const weekQuery = `SELECT COALESCE(SUM(total_amount), 0) AS total FROM Sales WHERE date(timestamp, 'localtime') >= date('now', 'localtime', 'weekday 0', '-6 days')`;
    const monthQuery = `SELECT COALESCE(SUM(total_amount), 0) AS total FROM Sales WHERE strftime('%Y-%m', timestamp, 'localtime') = strftime('%Y-%m', 'now', 'localtime')`;
    const yearQuery = `SELECT COALESCE(SUM(total_amount), 0) AS total FROM Sales WHERE strftime('%Y', timestamp, 'localtime') = strftime('%Y', 'now', 'localtime')`;

    // 2. Popular items by total quantity sold
    const popularQuery = `
        SELECT 
            p.name, 
            SUM(si.quantity) AS times_sold, 
            SUM(si.quantity * si.price) AS revenue
        FROM SaleItems si
        LEFT JOIN Products p ON si.product_id = p.id
        GROUP BY si.product_id
        ORDER BY times_sold DESC
        LIMIT 5
    `;

    // 3. Daily sales totals for line chart
    const chartQuery = `
        SELECT 
            date(timestamp, 'localtime') AS sale_date, 
            COALESCE(SUM(total_amount), 0) AS total 
        FROM Sales 
        WHERE date(timestamp, 'localtime') >= date('now', 'localtime', '-6 days')
        GROUP BY sale_date 
        ORDER BY sale_date ASC
    `;

    const getVal = (query) => new Promise((resolve, reject) => {
        db.get(query, [], (err, row) => {
            if (err) reject(err);
            else resolve(row ? row.total : 0);
        });
    });

    const getRows = (query) => new Promise((resolve, reject) => {
        db.all(query, [], (err, rows) => {
            if (err) reject(err);
            else resolve(rows);
        });
    });

    Promise.all([
        getVal(todayQuery),
        getVal(weekQuery),
        getVal(monthQuery),
        getVal(yearQuery),
        getRows(popularQuery),
        getRows(chartQuery)
    ]).then(([today, week, month, year, popular, chart]) => {
        // Build map of dates with sales
        const chartMap = {};
        chart.forEach(c => {
            chartMap[c.sale_date] = c.total;
        });

        const labels = [];
        const data = [];
        
        // Populate continuous past 7 days (including today)
        for (let i = 6; i >= 0; i--) {
            const d = new Date();
            d.setDate(d.getDate() - i);
            const dateStr = d.toISOString().substring(0, 10);
            
            const weekday = d.toLocaleDateString('en-US', { weekday: 'short' });
            const dayNum = d.getDate();
            const monthName = d.toLocaleDateString('en-US', { month: 'short' });
            
            labels.push(`${weekday} (${monthName} ${dayNum})`);
            data.push(chartMap[dateStr] || 0);
        }

        res.json({
            kpis: { today, week, month, year },
            popularItems: popular,
            chartData: { labels, data }
        });
    }).catch(err => {
        console.error(err);
        res.status(500).json({ error: 'Failed to retrieve analytics dashboard data.' });
    });
});

app.listen(PORT, () => {
    console.log(`Server is running on http://localhost:${PORT}`);
});
