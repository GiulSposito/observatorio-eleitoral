test_that("simulação G1–G4 gera margens coerentes com a matriz verdadeira", {
  u <- ec_test_units(25, seed = 31)
  for (g in c("G1", "G2", "G3", "G4")) {
    sim <- ec_simulate_t2(u, g, seed = 7)
    m <- ec_margins(sim$units)  # valida o balanço por unidade
    expect_equal(unname(colSums(m$O)[EC_ORIGINS]), unname(rowSums(sim$truth)[EC_ORIGINS]))
    expect_equal(unname(colSums(m$D)[EC_DESTINATIONS]), unname(colSums(sim$truth)[EC_DESTINATIONS]))
    expect_equal(sim$truth["N", "S"], 0)
    # margens do 1º turno são as reais (só N muda em G4)
    expect_equal(sim$units$o_A, u$o_A)
  }
  g4 <- ec_simulate_t2(u, "G4", seed = 8)$units
  expect_true(any(g4$o_N > 0 | g4$d_S > 0))
})

test_that("ec_calibrate devolve a estrutura da interface e falha sem municípios elegíveis", {
  p <- ec_test_params()
  u <- ec_test_units(8, seed = 32)  # menos de 15 unidades: nenhum estrato elegível
  r <- ec_calibrate(u, p, seed = 1)
  expect_named(r, c("report", "thresholds", "calibration_id", "status", "decision", "runtime_s"))
  expect_equal(r$status, "failed")
  expect_match(r$decision, "só limites")
  expect_match(r$calibration_id, "^cal-2026-presidente-")
  expect_equal(r$thresholds$calibration_status, "failed")
})

test_that("calibração reprovada desativa a estimação (só limites, 05 §5.6)", {
  p <- ec_test_params()
  p$estimacao$calibration_status <- "failed"
  r <- ec_estimate(ec_test_units(40, seed = 35), p, seed = 1, context = list(eligible_share_used = 1))
  expect_equal(r$status, "unavailable")
  expect_equal(nrow(r$flows), 0L)
  expect_match(r$model$reason_unavailable, "só os limites")
})

test_that("ec_calibrate roda a simulação e reporta convergência por processo e estrato", {
  p <- ec_test_params()
  p$estimacao$cadeias <- 2
  p$execucao$dm_homog$piloto <- 800
  p$execucao$dm_homog$iteracoes <- 4000
  p$execucao$dm_homog$thin <- 10
  p$execucao$dm_homog$extensoes_max <- 0
  p$execucao$dm_homog$amostras_contagem <- 60
  p$calibracao$municipios_por_estrato <- 1
  p$calibracao$estratos <- c(15)
  p$calibracao$processos <- c("G1", "G2")
  u <- dplyr::bind_rows(
    dplyr::mutate(ec_test_units(18, seed = 33), municipio_tse = "00001"),
    dplyr::mutate(ec_test_units(5, seed = 34), municipio_tse = "00002")
  )
  r <- ec_calibrate(u, p, seed = 2)
  expect_true(r$status %in% c("passed", "failed"))
  fits <- attr(r$report, "fits")
  expect_equal(nrow(fits), 2L)  # 1 município elegível x 2 processos
  expect_true(all(fits$municipio_tse == "00001"))
  if (r$status == "passed") {
    expect_true(all(c("r_estimado", "r_fraco", "n_secoes_min", "calibration_id") %in% names(r$thresholds)))
  } else {
    expect_match(r$decision, "só limites")
  }
})
