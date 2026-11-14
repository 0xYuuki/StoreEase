module.exports = (db) => {
  db.exec(`
    ALTER TABLE Products ADD COLUMN reorder_level INTEGER
      CHECK (typeof(reorder_level) = 'integer' AND reorder_level BETWEEN 0 AND 9007199254740991 OR reorder_level IS NULL);
    ALTER TABLE StockAdjustments ADD COLUMN sale_id INTEGER REFERENCES Sales(id);
    CREATE INDEX stock_history_product ON StockAdjustments(product_id, id);
    CREATE INDEX sales_history_date ON Sales(julianday(timestamp), id);
    PRAGMA user_version=2;
  `);
};
