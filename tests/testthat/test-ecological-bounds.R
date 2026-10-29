test_that("Fréchet sem restrição coincide com o LP por unidade (oráculo)", {
  u <- ec_test_units(12, seed = 3, with_population = TRUE)
  m <- ec_margins(u)
  for (k in seq_len(nrow(u))) {
    o <- m$O[k, ]
    d <- m$D[k, ]
    lp <- ec_bounds_lp_unit(o, d, list(list(origin = "N", destination = "S", value = 0)))
    fr <- ec_frechet_sum(m$O[k, , drop = FALSE], m$D[k, , drop = FALSE])
    expect_true(lp$feasible)
    expect_equal(unname(fr$min), unname(lp$min), tolerance = 1e-6)
    expect_equal(unname(fr$max), unname(lp$max), tolerance = 1e-6)
  }
})

test_that("Gale–Hall sem células proibidas reproduz Fréchet", {
  u <- ec_test_units(30, seed = 4, with_population = TRUE)
  m <- ec_margins(u)
  g <- ec_bounds_gale(m$O, m$D, ec_allowed_matrix())
  fr <- ec_frechet_sum(m$O, m$D)
  expect_true(all(g$feasible))
  expect_equal(unname(apply(g$min, c(2, 3), sum)), unname(fr$min), tolerance = 1e-6)
  expect_equal(unname(apply(g$max, c(2, 3), sum)), unname(fr$max), tolerance = 1e-6)
})

test_that("Gale–Hall com células zeradas coincide com o LP por unidade", {
  u <- ec_test_units(15, seed = 5, with_population = TRUE)
  m <- ec_margins(u)
  forb <- list(c("A", "B"), c("B", "A"))
  E <- ec_allowed_matrix(forbidden = forb)
  g <- ec_bounds_gale(m$O, m$D, E)
  cons <- list(list(origin = "A", destination = "B", value = 0), list(origin = "B", destination = "A", value = 0),
               list(origin = "N", destination = "S", value = 0))
  for (k in seq_len(nrow(u))) {
    lp <- ec_bounds_lp_unit(m$O[k, ], m$D[k, ], cons)
    expect_equal(g$feasible[k], lp$feasible)
    if (lp$feasible) {
      gmin <- g$min[k, , ]
      gmax <- g$max[k, , ]
      gmin[!E] <- 0
      gmax[!E] <- 0
      expect_equal(unname(gmin), unname(lp$min), tolerance = 1e-6)
      expect_equal(unname(gmax), unname(lp$max), tolerance = 1e-6)
    }
  }
})

test_that("cenário inviável é detectado e contado", {
  # Seção em que o finalista A perde todos os votos para B: sem troca direta é impossível.
  u <- tibble::tibble(
    o_A = c(100L, 50L), o_B = c(0L, 50L), o_O = 0L, o_I = 0L, o_X = 0L, o_N = 0L,
    d_A = c(0L, 50L), d_B = c(100L, 50L), d_I = 0L, d_X = 0L, d_S = 0L
  )
  assumptions <- yaml::read_yaml(file.path(testthat::test_path(), "..", "..", "config", "assumptions.yml"))
  b <- ec_bounds(u, "sem-troca-finalistas", assumptions)
  expect_true(all(b$status == "infeasible"))
  expect_true(all(b$units_infeasible == 1L))
  expect_true(all(is.na(b$min_votes)))
  ok <- ec_bounds(u[2, ], "sem-troca-finalistas", assumptions)
  expect_true(all(ok$status == "feasible"))
  expect_equal(ok$max_votes[ok$origin == "A" & ok$destination == "B"], 0)
})

test_that("ec_bounds base tem o formato do contrato e min <= max", {
  u <- ec_test_units(20, seed = 6)
  b <- ec_bounds(u, "base")
  expect_equal(nrow(b), length(EC_ORIGINS) * length(EC_DESTINATIONS))
  expect_named(b, c("origin", "destination", "min_votes", "max_votes", "status", "units_used",
                    "units_infeasible", "method_id"))
  expect_true(all(b$min_votes <= b$max_votes))
  expect_true(all(b$method_id == "frechet"))
  # a verdade sempre está dentro dos limites
  truth <- attr(u, "truth")
  inside <- mapply(function(o, d, lo, hi) truth[o, d] >= lo - 1e-9 && truth[o, d] <= hi + 1e-9,
                   b$origin, b$destination, b$min_votes, b$max_votes)
  expect_true(all(inside))
})

test_that("margens zero e conjunto vazio", {
  b <- ec_bounds(NULL, "base")
  expect_true(all(b$status == "insufficient_data"))
  u <- ec_test_units(5, seed = 7)
  b2 <- ec_bounds(u, "base")
  expect_true(all(b2$max_votes[b2$origin == "N"] == 0))
  expect_true(all(b2$max_votes[b2$destination == "S"] == 0))
})
