# Arquivos sintéticos no formato do TSE (CSV `;`, latin-1, campos entre aspas) para testar a camada de
# dados. Números e municípios são inventados.

# Uma seção com votos por votável em cada turno. O detalhe é derivado dos votos, salvo `detail_*`.
syn_section <- function(uf, mun, nm, zona, secao, aptos1, aptos2, v1, v2,
                        local_id = "1001", local_nm = "ESCOLA MUNICIPAL TESTE", local_nm2 = local_nm,
                        installed = "Sim", detail_comp_delta = c(0L, 0L)) {
  list(uf = uf, mun = mun, nm = nm, zona = zona, secao = secao, aptos = c(aptos1, aptos2),
       v = list(v1, v2), local_id = local_id, local_nm = c(local_nm, local_nm2), installed = installed,
       comp_delta = detail_comp_delta)
}

VALID_CANDIDATES <- c("13", "22", "30")
NAMES <- c("13" = "FINALISTA TREZE", "22" = "FINALISTA VINTE E DOIS", "30" = "OUTRO TRINTA",
           "28" = "CANDIDATURA SEM VALIDADE", "95" = "VOTO BRANCO", "96" = "VOTO NULO")

write_tse_csv <- function(df, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  utils::write.table(df, path, sep = ";", quote = TRUE, row.names = FALSE, fileEncoding = "latin1", na = "")
  path
}

# Gera os quatro CSVs e devolve o vetor nomeado como `extracted_paths()`.
write_synthetic_tse <- function(sections, dir, skip_votes = character(), official_override = NULL) {
  vot <- list(); det <- list()
  for (s in sections) {
    for (t in 1:2) {
      v <- s$v[[t]]
      if (!paste(s$mun, s$zona, s$secao, t) %in% skip_votes && s$installed == "Sim") {
        for (n in names(v)) if (v[[n]] > 0) {
          vot[[length(vot) + 1]] <- data.frame(
            NR_TURNO = as.character(t), SG_UF = s$uf, CD_MUNICIPIO = s$mun, NM_MUNICIPIO = s$nm,
            NR_ZONA = s$zona, NR_SECAO = s$secao, CD_CARGO = "1", DS_CARGO = "Presidente",
            NR_VOTAVEL = n, NM_VOTAVEL = NAMES[[n]], QT_VOTOS = as.character(v[[n]]))
        }
      }
      comp <- if (s$installed == "Sim") sum(v) + s$comp_delta[t] else 0L
      nominais <- sum(v[setdiff(names(v), c("95", "96"))])
      det[[length(det) + 1]] <- data.frame(
        NR_TURNO = as.character(t), SG_UF = s$uf, CD_MUNICIPIO = s$mun, NM_MUNICIPIO = s$nm,
        NR_ZONA = s$zona, NR_SECAO = s$secao, CD_CARGO = "1", DS_CARGO = "Presidente",
        QT_APTOS = as.character(s$aptos[t]), QT_COMPARECIMENTO = as.character(comp),
        QT_ABSTENCOES = as.character(s$aptos[t] - comp),
        QT_VOTOS_NOMINAIS = as.character(if (s$installed == "Sim") nominais else 0L),
        QT_VOTOS_BRANCOS = as.character(if (s$installed == "Sim") v[["95"]] else 0L),
        QT_VOTOS_NULOS = as.character(if (s$installed == "Sim") v[["96"]] else 0L),
        QT_VOTOS_LEGENDA = "0", QT_VOTOS_ANULADOS_APU_SEP = "0",
        NR_LOCAL_VOTACAO = s$local_id, NM_LOCAL_VOTACAO = s$local_nm[t],
        ST_SECAO_INSTALADA = s$installed, ST_SECAO_ANULADA = "Não", DS_ORIGEM_VOTO = "Urna Eletrônica")
    }
  }
  vot <- do.call(rbind, vot); det <- do.call(rbind, det)

  # Totais oficiais: candidatos válidos por município/turno e detalhe do 1º turno.
  key <- paste(vot$CD_MUNICIPIO, vot$NR_TURNO, vot$NR_VOTAVEL, vot$SG_UF, sep = "|")
  agg <- tapply(as.integer(vot$QT_VOTOS), key, sum)
  parts <- do.call(rbind, strsplit(names(agg), "|", fixed = TRUE))
  cand <- data.frame(SG_UF = parts[, 4], CD_MUNICIPIO = parts[, 1], NR_ZONA = "1", NR_TURNO = parts[, 2],
                     CD_CARGO = "1", NR_CANDIDATO = parts[, 3], QT_VOTOS_NOMINAIS = as.character(agg),
                     NM_TIPO_DESTINACAO_VOTOS = "Válido")
  cand <- cand[cand$NR_CANDIDATO %in% VALID_CANDIDATES, ]
  if (!is.null(official_override)) cand <- official_override(cand)

  d1 <- det[det$NR_TURNO == "1", ]
  nulos_tech <- vot[vot$NR_TURNO == "1" & vot$NR_VOTAVEL == "28", ]
  dm_key <- paste(d1$SG_UF, d1$CD_MUNICIPIO)
  sum_by <- function(x) tapply(as.integer(x), dm_key, sum)
  tech <- tapply(as.integer(nulos_tech$QT_VOTOS), paste(nulos_tech$SG_UF, nulos_tech$CD_MUNICIPIO), sum)
  ks <- names(sum_by(d1$QT_APTOS))
  dm <- data.frame(
    SG_UF = sub(" .*", "", ks), CD_MUNICIPIO = sub(".* ", "", ks), NR_ZONA = "1", NR_TURNO = "1", CD_CARGO = "1",
    QT_APTOS = as.character(sum_by(d1$QT_APTOS)[ks]),
    QT_COMPARECIMENTO = as.character(sum_by(d1$QT_COMPARECIMENTO)[ks]),
    QT_VOTOS_BRANCOS = as.character(sum_by(d1$QT_VOTOS_BRANCOS)[ks]),
    QT_TOTAL_VOTOS_NULOS = as.character(sum_by(d1$QT_VOTOS_NULOS)[ks] + ifelse(is.na(tech[ks]), 0L, tech[ks]))
  )

  c(
    votacao_secao = write_tse_csv(vot, file.path(dir, "votacao_secao.csv")),
    detalhe_votacao_secao = write_tse_csv(det, file.path(dir, "detalhe_votacao_secao.csv")),
    votacao_candidato_munzona = write_tse_csv(cand, file.path(dir, "votacao_candidato_munzona.csv")),
    detalhe_votacao_munzona = write_tse_csv(dm, file.path(dir, "detalhe_votacao_munzona.csv"))
  )
}

v1 <- function(a, b, o, tech = 0L, br = 5L, nu = 7L) c("13" = a, "22" = b, "30" = o, "28" = tech, "95" = br, "96" = nu)
v2 <- function(a, b, br = 4L, nu = 6L) c("13" = a, "22" = b, "95" = br, "96" = nu)

# Cenário padrão: dois municípios homônimos em UFs diferentes, um terceiro com casos especiais e uma
# seção no exterior (que deve ficar fora).
default_sections <- function() {
  list(
    # GO 01007 BOM DESTINO: 3 seções regulares (fechada, net_change, acima de tau)
    syn_section("GO", "1007", "BOM DESTINO", "9", "1", 200, 200, v1(80, 60, 10, tech = 2), v2(90, 70)),
    syn_section("GO", "1007", "BOM DESTINO", "9", "2", 200, 202, v1(70, 70, 12), v2(85, 78)),
    syn_section("GO", "1007", "BOM DESTINO", "9", "3", 300, 320, v1(100, 90, 20), v2(115, 100)),
    # MG 20001 BOM DESTINO (homônimo)
    syn_section("MG", "20001", "BOM DESTINO", "101", "12", 250, 250, v1(90, 100, 15), v2(105, 110)),
    # SC 30005 PORTO TESTE: trânsito, especial, falha V1, sem par no 2º turno é testado à parte
    syn_section("SC", "30005", "PORTO TESTE", "20", "5", 300, 300, v1(100, 100, 30), v2(120, 115),
                local_nm = "UNIVERSIDADE FEDERAL - VOTO EM TRÂNSITO"),
    syn_section("SC", "30005", "PORTO TESTE", "20", "6", 80, 80, v1(20, 30, 5), v2(25, 33),
                local_nm = "PENITENCIÁRIA ESTADUAL"),
    syn_section("SC", "30005", "PORTO TESTE", "20", "7", 300, 300, v1(100, 100, 30), v2(120, 115),
                detail_comp_delta = c(0L, 1L)),
    syn_section("SC", "30005", "PORTO TESTE", "20", "8", 300, 300, v1(110, 95, 25), v2(125, 112)),
    # Exterior
    syn_section("ZZ", "99999", "CIDADE NO EXTERIOR", "1", "1", 100, 100, v1(30, 30, 5), v2(35, 35))
  )
}

# Roda silver → gold sobre um conjunto sintético, numa raiz de dados temporária já ativa.
run_synthetic_gold <- function(sections = default_sections(), ...) {
  cfg <- read_election_config("2026-presidente")
  params <- read_method_params()
  ex <- write_synthetic_tse(sections, file.path(data_root(), "bronze", "extracted"), ...)
  sp <- build_silver(cfg, ex)
  gs <- build_gold_sections(cfg, sp, ex, params)
  ga <- build_gold_accounting(cfg, gold_paths(cfg), sp)
  list(cfg = cfg, params = params, extracted = ex, silver = sp, gold = gold_paths(cfg))
}
