// Controllers adapt service results and exceptions to HTTP without owning SQL.
const respond = (operation) => (req, res, next) => {
  try {
    res.json(operation(req));
  } catch (err) {
    next(err);
  }
};
module.exports = (service, analytics) => ({
  session: respond((req) => ({ role: req.role })),
  products: respond(() => service.list()),
  lookup: respond((req) => service.lookup(req.params.barcode)),
  create: respond((req) => service.create(req.body || {})),
  update: respond((req) => service.update(req.params.id, req.body || {})),
  deactivate: respond((req) => service.deactivate(req.params.id)),
  adjust: respond((req) => service.adjust(req.params.id, req.body || {})),
  checkout: respond((req) =>
    service.checkout(req.body || {}, req.headers["idempotency-key"]),
  ),
  analytics: respond(() => analytics()),
  sales: respond((req) => service.sales(req.query)),
  receipt: respond((req) => service.receipt(req.params.id)),
  reorder: respond((req) => service.reorder(req.params.id, req.body || {})),
  stockHistory: respond((req) => service.stockHistory(req.params.id, req.query.page)),
  debtsSummary: respond(() => service.debtsSummary()),
  customers: respond((req) => service.customers(req.query)),
  customer: respond((req) => service.customer(req.params.id)),
  createCustomer: respond((req) => service.createCustomer(req.body || {})),
  updateCustomer: respond((req) => service.updateCustomer(req.params.id, req.body || {})),
  deleteCustomer: respond((req) => service.deleteCustomer(req.params.id)),
  customerTransactions: respond((req) => service.customerTransactions(req.params.id, req.query)),
  addDebt: respond((req) => service.addDebt(req.params.id, req.body || {})),
  recordPayment: respond((req) => service.recordPayment(req.params.id, req.body || {})),
});
