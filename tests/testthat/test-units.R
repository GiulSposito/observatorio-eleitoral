test_that("unidades têm balanço origem = destino com pseudo-categorias N e S", {
  with_temp_data_root({
    r <- run_synthetic_gold()
    u <- read_parquet_df(r$gold[["units"]])
    expect_true(all(u$o_A + u$o_B + u$o_O + u$o_I + u$o_X + u$o_N == u$d_A + u$d_B + u$d_I + u$d_X + u$d_S))
    net <- u[u$comparison_unit_id == "01007-0009-0002", ]
    expect_equal(net$o_N, 2L); expect_equal(net$d_S, 0L)
    expect_equal(net$population_status, "net_change")
    expect_false(any(grepl("30005-0020-000[567]", u$comparison_unit_id)))
    expect_false("01007-0009-0003" %in% u$comparison_unit_id)
  })
})

test_that("assert_units_balance recusa unidade desbalanceada", {
  bad <- tibble::tibble(comparison_unit_id = "x", o_A = 1L, o_B = 0L, o_O = 0L, o_I = 0L, o_X = 0L, o_N = 0L,
                        d_A = 0L, d_B = 0L, d_I = 0L, d_X = 0L, d_S = 0L)
  expect_error(assert_units_balance(bad), "balanço")
})
