fast_params <- function() {
  p <- ec_test_params()
  p$estimacao$cadeias <- 2
  p$execucao$eipack$burnin <- 1000
  p$execucao$eipack$amostras <- 100
  p$execucao$eipack$thin <- 2
  p$execucao$eipack$tune <- FALSE
  p
}

test_that("lphom recupera a matriz conhecida em G1 (homogêneo)", {
  u <- ec_test_units(300, seed = 21)
  m <- ec_margins(u)
  fit <- ec_fit_lphom(m$O, m$D)
  expect_equal(fit$status, "ok")
  truth <- attr(u, "truth")
  rows <- c("A", "B", "X")
  rel <- abs(fit$counts[rows, ] - truth[rows, ]) / pmax(truth[rows, ], 1)
  # células grandes (retenção) bem recuperadas
  expect_lt(max(rel[cbind(c("A", "B", "X"), c("A", "B", "X"))]), 0.10)
  expect_equal(unname(rowSums(fit$counts)), unname(colSums(m$O)), tolerance = 1e-6)
})

test_that("lphom agrupa unidades acima do limite e continua fechando as margens de origem", {
  u <- ec_test_units(120, seed = 22)
  m <- ec_margins(u)
  fit <- ec_fit_lphom(m$O, m$D, max_units = 30)
  expect_true(fit$grouped)
  expect_equal(unname(rowSums(fit$counts)), unname(colSums(m$O)), tolerance = 1e-6)
})

test_that("md-bayes (eiPack): média das contagens fecha as margens de origem, inclusive com N e S fundidas", {
  u <- ec_test_units(40, seed = 23, with_population = TRUE)
  m <- ec_margins(u)
  p <- fast_params()
  fit <- ec_fit_md_eipack(m$O, m$D, p, seed = 5)
  expect_equal(fit$status, "ok")
  expect_true(all(c("N>X", "S>X") %in% fit$diagnostics$merged))
  mean_counts <- colMeans(do.call(rbind, fit$draws))
  g <- ec_cell_grid()
  rs <- as.vector(tapply(mean_counts, g$origin, sum)[EC_ORIGINS])
  expect_equal(rs, unname(colSums(m$O)[EC_ORIGINS]), tolerance = 1e-6)
  expect_equal(unname(mean_counts["N>S"]), 0)
})

test_that("md-bayes sem convergência vira failed, sem linhas publicadas (05 §5.3)", {
  u <- ec_test_units(30, seed = 24)
  p <- fast_params()
  p$estimacao$n_secoes_min <- 10
  p$estimacao$rhat_max <- 0.5  # inatingível: força a falha de convergência
  r <- ec_estimate(u, p, seed = 3, context = list(eligible_share_used = 1))
  expect_equal(r$status, "failed")
  expect_equal(nrow(r$flows), 0L)
  expect_equal(r$model$status, "failed")
  expect_match(r$model$reason_unavailable, "convergência")
  expect_equal(vapply(r$model$methods, `[[`, "", "method_id"), c("md-bayes", "lphom", "ecolrxc"))
})

test_that("insufficient_data por poucas seções e por cobertura baixa", {
  p <- fast_params()
  r1 <- ec_estimate(ec_test_units(5, seed = 25), p, seed = 1, context = list(eligible_share_used = 1))
  expect_equal(r1$status, "insufficient_data")
  expect_equal(nrow(r1$flows), 0L)
  r2 <- ec_estimate(ec_test_units(40, seed = 26), p, seed = 1, context = list(eligible_share_used = 0.5))
  expect_equal(r2$status, "insufficient_data")
  expect_match(r2$model$reason_unavailable, "cobrem")
})

test_that("classes de identificação e massa de mudança (05 §5.4 e §5.7)", {
  est <- ec_test_params()$estimacao
  idf <- ec_identification(W = c(3, 1000, 1000, 1000), P_width = c(1, 100, 300, 900), F_width = c(0, 50, 100, 200),
                           row_total = c(100, 5000, 5000, 5000), est_params = est)
  expect_equal(idf$class, c("determined", "estimated", "weak", "not_identified"))
  share <- ec_change_mass_share(c("A", "O", "O"), c("A", "A", "B"), c(1000, 60, 40), c("estimated", "estimated", "weak"))
  expect_equal(share, 0.6)  # retenção A>A fora da massa de mudança
})

test_that("ec_estimate aplica §5.7 e devolve o formato de fluxos_estimados (com md-bayes simulado)", {
  u <- ec_test_units(60, seed = 27)
  truth <- attr(u, "truth")
  p <- fast_params()
  p$estimacao$n_secoes_min <- 15
  cell_names <- ec_cell_id(ec_cell_grid()$origin, ec_cell_grid()$destination)
  tv <- ec_matrix_to_long(truth, "v")$v
  # md-bayes "convergido" com posterior concentrada na verdade: testa as regras, não o amostrador
  fake <- function(O, D, params, seed) {
    list(status = "ok", reason = NULL, version = "eiPack-teste", runtime_s = 0.1,
         summary = list(mean = setNames(tv, cell_names), low = tv - 2, high = tv + 2),
         diagnostics = list(engine = "eipack", rhat_max = 1.001, ess_min = 1000))
  }
  old <- ec_fit_md
  assign("ec_fit_md", fake, envir = globalenv())
  on.exit(assign("ec_fit_md", old, envir = globalenv()), add = TRUE)
  r <- ec_estimate(u, p, seed = 9, context = list(eligible_share_used = 1))
  expect_true(r$status %in% c("ready", "partial"))
  expect_equal(nrow(r$flows), 30L)
  expect_named(r$flows, ec_flow_columns)
  expect_true(all(r$flows$estimate_statistic == "posterior_mean"))
  expect_true(all(r$flows$model_status == r$status))
  expect_true(all(r$flows$interval_low <= r$flows$estimate_votes + 1e-9 & r$flows$estimate_votes <= r$flows$interval_high + 1e-9))
  expect_true(all(r$flows$bounds_min <= r$flows$estimate_votes + 1 & r$flows$estimate_votes <= r$flows$bounds_max + 1))
  rs <- as.vector(tapply(r$flows$estimate_votes, r$flows$origin, sum)[EC_ORIGINS])
  expect_equal(rs, unname(colSums(ec_margins(u)$O)[EC_ORIGINS]), tolerance = 1e-6)
  expect_named(r$model, c("status", "reason_unavailable", "methods", "predictive_check", "identified_change_share",
                          "n_units_used", "calibration_id"))
  expect_true(is.logical(r$model$predictive_check$passed))
  # §5.7: ready exige checagem preditiva aprovada e massa identificada suficiente
  expected <- if (r$model$predictive_check$passed && r$model$identified_change_share >= p$estimacao$massa_identificada_min) "ready" else "partial"
  expect_equal(r$status, expected)
  # e um limiar de massa inatingível rebaixa para partial
  p2 <- p
  p2$estimacao$massa_identificada_min <- 1.01
  expect_equal(ec_estimate(u, p2, seed = 9, context = list(eligible_share_used = 1))$status, "partial")
})

test_that("resumo nacional de diagnósticos conta status e convergência", {
  models <- list(
    "00001" = list(status = "insufficient_data", reason_unavailable = "Menos de 15 seções comparáveis (8).", methods = list()),
    "00002" = list(status = "failed", reason_unavailable = "md-bayes: sem convergência: R-hat máximo 1.700",
                   methods = list(list(method_id = "md-bayes", status = "failed", runtime_s = 10, diagnostics = list(rhat_max = 1.7)))),
    "00003" = list(status = "partial", reason_unavailable = NULL,
                   methods = list(list(method_id = "md-bayes", status = "ok", runtime_s = 5, diagnostics = list(rhat_max = 1.005))))
  )
  s <- ec_diagnostics_summary(models)
  expect_equal(s$municipalities, 3L)
  expect_equal(s$md_bayes$fits, 2L)
  expect_equal(s$md_bayes$converged, 1L)
  expect_equal(s$by_model_status$failed, 1L)
  expect_equal(length(s$top_reasons), 2L)
})
