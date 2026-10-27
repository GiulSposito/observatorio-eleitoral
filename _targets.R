# Grafo do pipeline do Caderno Eleitoral (R/README.md). Rodar com `Rscript run.R 2026-presidente`
# (tar_make + bundle + validação) ou `Rscript -e 'targets::tar_make()'` (só o grafo).

library(targets)

tar_source("R")
if (!dir.exists("R/ecological") && identical(Sys.getenv("CADERNO_ECOLOGICAL_STUB"), "1")) {
  tar_source("tests/testthat/helper-ecological-stub.R")
}

tar_option_set(
  packages = c("dplyr", "tibble"),
  controller = crew::crew_controller_local(workers = 8, seconds_idle = 60),
  error = "stop"
)

election_id <- Sys.getenv("CADERNO_ELECTION_ID", unset = "2026-presidente")

list(
  tar_target(config_files, c(file.path("config", "eleicoes", paste0(election_id, ".yml")),
                             "config/metodo.yml", "config/assumptions.yml"), format = "file"),
  tar_target(cfg, { config_files; read_election_config(election_id) }, deployment = "main"),
  tar_target(params, { config_files; read_method_params() }, deployment = "main"),
  tar_target(assumptions, { config_files; read_assumptions() }, deployment = "main"),

  # Bronze: consulta o servidor a cada execução; só baixa de novo se o arquivo mudou.
  tar_target(sources, fetch_sources(cfg), cue = tar_cue(mode = "always"), deployment = "main"),
  tar_target(extracted, unname(extract_sources(cfg, sources)), format = "file", deployment = "main"),

  # Silver e gold
  tar_target(silver, {
    extracted
    unname(build_silver(cfg, extracted_paths(cfg)))
  }, format = "file", deployment = "main"),
  tar_target(gold_sections, {
    silver
    unname(build_gold_sections(cfg, silver_paths(cfg), extracted_paths(cfg), params))
  }, format = "file", deployment = "main"),
  tar_target(gold_accounting, {
    gold_sections
    unname(build_gold_accounting(cfg, gold_paths(cfg), silver_paths(cfg)))
  }, format = "file", deployment = "main"),
  tar_target(validation, {
    gold_sections
    validation_status_from_checks(read_parquet_df(gold_paths(cfg)[["checks"]]))
  }, deployment = "main"),
  tar_target(ufs, {
    gold_accounting
    sort(unique(read_parquet_df(gold_paths(cfg)[["totais"]])$uf))
  }, deployment = "main"),

  # Método (R/ecological/): calibração uma vez; limites, cenários e estimação por UF.
  tar_target(calibration, {
    gold_accounting
    calibrate_method(gold_paths(cfg)[["units"]], params, seed_namespace(cfg, params))
  }),
  tar_target(eco, {
    gold_accounting
    run_ecological_uf(ufs, gold_paths(cfg)[["units"]], gold_paths(cfg)[["totais"]], validation,
                      calibration, assumptions, cfg)
  }, pattern = map(ufs), format = "file")
)
