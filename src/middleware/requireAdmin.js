module.exports = (req, res, next) => {
  if (req.role !== "admin") {
    return res
      .status(403)
      .json({ error: "Administrator required", code: "FORBIDDEN" });
  }
  next();
};
