#!/usr/bin/env Rscript
# Ponto de entrada do pipeline: Rscript run.R <election_id>
#   1. targets::tar_make()   bronze → silver → gold → método por UF
#   2. build_web_bundle()    release em staging, validação, latest.json, cópia para web/data/
# Variáveis: CADERNO_DATA_DIR (raiz de dados), CADERNO_ECOLOGICAL_STUB=1 (só para desenvolvimento).

args <- commandArgs(trailingOnly = TRUE)
election_id <- if (length(args) >= 1L) args[[1]] else "2026-presidente"
Sys.setenv(CADERNO_ELECTION_ID = election_id)

t0 <- Sys.time()
targets::tar_make()

for (f in list.files("R", pattern = "[.]R$", recursive = TRUE, full.names = TRUE)) source(f)
if (ecological_mode() == "stub") {
  source("tests/testthat/helper-ecological-stub.R")
  message("AVISO: release gerada com o stub ecológico; não publicar.")
}

cfg <- targets::tar_read(cfg)
out <- build_web_bundle(
  cfg = cfg,
  gold = gold_paths(cfg),
  eco_paths = targets::tar_read(eco),
  calibration = targets::tar_read(calibration),
  sources = targets::tar_read(sources),
  silver = silver_paths(cfg),
  assumptions = targets::tar_read(assumptions)
)
log_msg("release ", out$release_id, " pronta em ",
        format(round(difftime(Sys.time(), t0, units = "mins"), 1)))
