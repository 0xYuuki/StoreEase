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
});
