const { Router } = require("express");
const requireAdmin = require("../middleware/requireAdmin");
module.exports = (db) => {
  const router = Router();
  const controller = require("./controller")(require("./service")(db), () =>
    require("./analytics")(db),
  );
  router.get("/session", controller.session);
  router.get("/products", controller.products);
  router.get("/products/:barcode", controller.lookup);
  router.post("/products", requireAdmin, controller.create);
  router.put("/products/:id", requireAdmin, controller.update);
  router.delete("/products/:id", requireAdmin, controller.deactivate);
  router.post("/products/:id/stock", requireAdmin, controller.adjust);
  router.put("/products/:id/reorder-level", requireAdmin, controller.reorder);
  router.get("/products/:id/stock-history", requireAdmin, controller.stockHistory);
  router.get("/sales", requireAdmin, controller.sales);
  router.get("/sales/:id", controller.receipt);
  router.post("/sales", controller.checkout);
  router.get("/analytics", requireAdmin, controller.analytics);
  return router;
};
