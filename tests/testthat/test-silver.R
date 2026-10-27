test_that("silver preserva zeros à esquerda, exclui o exterior e deriva os slots pelo número de urna", {
  with_temp_data_root({
    r <- run_synthetic_gold()
    st <- read_parquet_df(r$silver[["secao_turno"]])
    expect_true(all(nchar(st$municipio_tse) == 5))
    expect_true(all(nchar(st$zona) == 4) && all(nchar(st$secao) == 4))
    expect_true("01007" %in% st$municipio_tse)
    expect_false("ZZ" %in% st$uf)
    fin <- read_finalists(r$silver[["finalistas"]])
    expect_equal(fin$slot, c("A", "B"))
    expect_equal(fin$number, c("13", "22"))
  })
})

test_that("voto em candidato sem destinação válida vira nulo técnico (categoria I)", {
  with_temp_data_root({
    r <- run_synthetic_gold()
    st <- read_parquet_df(r$silver[["secao_turno"]])
    s1 <- st[st$municipio_tse == "01007" & st$secao == "0001" & st$turno == 1, ]
    expect_equal(s1$votes_null_tech, 2L)
    expect_equal(s1$votes_other, 10L)
    sm <- read_parquet_df(r$gold[["secoes"]])
    g <- sm[sm$municipio_tse == "01007" & sm$secao == "0001", ]
    expect_equal(g$null_t1, 7L + 2L)
    expect_equal(g$invalid_t1, 5L + 7L + 2L)
    expect_equal(g$others_t1, 10L)
  })
})

test_that("homônimos em UFs diferentes continuam municípios distintos", {
  with_temp_data_root({
    r <- run_synthetic_gold()
    tot <- read_parquet_df(r$gold[["totais"]])
    hom <- tot[tot$name == "BOM DESTINO", ]
    expect_equal(nrow(hom), 2L)
    expect_setequal(hom$uf, c("GO", "MG"))
    expect_setequal(hom$municipio_tse, c("01007", "20001"))
  })
})

test_that("display_name usa caixa mista com preposições minúsculas", {
  expect_equal(display_name("SÃO JOSÉ DOS CAMPOS"), "São José dos Campos")
  expect_equal(display_name("BOM DESTINO"), "Bom Destino")
  expect_equal(display_name("PAU D'ARCO"), "Pau D'Arco")
})
