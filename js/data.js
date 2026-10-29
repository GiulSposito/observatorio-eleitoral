// ÚNICO módulo que busca dados e fala com o DuckDB-Wasm (docs/arquitetura.md §6).
//  - latest.json -> catalogo.json -> manifest.json -> resumo/qualidade (fetch simples, sem Wasm);
//  - Parquet por UF só nas abas de detalhe, com DuckDB-Wasm carregado sob demanda;
//  - caminhos vêm só do manifesto/catálogo e são validados; SQL é constante, com o
//    município como parâmetro de prepared statement;
//  - toda leitura recebe um `signal`; trocar de município cancela a sessão anterior.

import { DUCKDB_URL } from "./vendor.js";

const SUPPORTED_MAJOR = "1";
const DATA_ROOT = new URL("./data/", document.baseURI);
const RE_RELPATH = /^(?!\/)(?!.*\.\.)(?!https?:)[A-Za-z0-9_./=-]+$/;
const RE_UF = /^[A-Z]{2}$/;
const RE_MUNICIPIO = /^[0-9]{5}$/;

export class DataError extends Error {
  // kind: network | not_found | schema | wasm | query | aborted
  constructor(kind, message, cause) {
    super(message);
    this.kind = kind;
    this.cause = cause;
  }
}

// ---- sessões (cancelamento ao trocar de município) ------------------------

export function newSession() {
  const ctrl = new AbortController();
  return {
    signal: ctrl.signal,
    cancel: () => ctrl.abort(),
    get aborted() { return ctrl.signal.aborted; },
  };
}

function checkAborted(signal) {
  if (signal?.aborted) throw new DataError("aborted", "Leitura cancelada: o recorte mudou.");
}

// ---- JSON ---------------------------------------------------------------

async function fetchJson(url, { signal, noCache = false } = {}) {
  let res;
  try {
    res = await fetch(url, { signal, cache: noCache ? "no-cache" : "default" });
  } catch (e) {
    if (signal?.aborted) throw new DataError("aborted", "Leitura cancelada.", e);
    throw new DataError("network", "Não foi possível baixar os dados. Verifique a conexão e tente de novo.", e);
  }
  if (res.status === 404) throw new DataError("not_found", `Arquivo não encontrado na publicação: ${url.pathname || url}`);
  if (!res.ok) throw new DataError("network", `O servidor respondeu ${res.status} ao baixar os dados.`);
  try {
    return await res.json();
  } catch (e) {
    throw new DataError("schema", "Arquivo de dados com formato inválido.", e);
  }
}

function checkSchema(doc, what) {
  const major = String(doc?.schema_version || "").split(".")[0];
  if (major !== SUPPORTED_MAJOR) {
    throw new DataError("schema", `Versão de dados ${doc?.schema_version || "desconhecida"} em ${what}; este site lê a versão ${SUPPORTED_MAJOR}.x.`);
  }
}

let _latest = null;
let _catalog = null;
let _metodo = null;

export async function loadLatest() {
  if (_latest) return _latest;
  const doc = await fetchJson(new URL("latest.json", DATA_ROOT), { noCache: true });
  checkSchema(doc, "latest.json");
  if (!RE_RELPATH.test(doc.release_base || "") || !RE_RELPATH.test(doc.catalog_url || "")) {
    throw new DataError("schema", "latest.json com caminho inválido.");
  }
  _latest = doc;
  return doc;
}

function releaseUrl(rel) {
  if (!RE_RELPATH.test(String(rel || ""))) throw new DataError("schema", "Caminho de arquivo inválido no manifesto.");
  return new URL(rel, new URL(_latest.release_base, DATA_ROOT));
}

function checkRelease(doc, what) {
  checkSchema(doc, what);
  if (doc.release_id !== _latest.release_id) {
    throw new DataError("schema", `${what} pertence a outra publicação (${doc.release_id}); recarregue a página.`);
  }
}

export async function loadCatalog() {
  if (_catalog) return _catalog;
  const latest = await loadLatest();
  const doc = await fetchJson(new URL(latest.catalog_url, DATA_ROOT));
  checkRelease(doc, "catalogo.json");
  _catalog = doc;
  return doc;
}

export async function loadMetodo() {
  if (_metodo) return _metodo;
  await loadLatest();
  const doc = await fetchJson(releaseUrl("metodo.json"));
  checkRelease(doc, "metodo.json");
  _metodo = doc;
  return doc;
}

// item: linha de catalogo.municipalities
export async function loadManifest(item, signal) {
  await loadLatest();
  const doc = await fetchJson(releaseUrl(item.manifest_url), { signal });
  checkAborted(signal);
  checkRelease(doc, "manifest.json");
  if (doc.municipio_tse !== item.municipio_tse || doc.uf !== item.uf) {
    throw new DataError("schema", "O manifesto não corresponde ao município pedido.");
  }
  return doc;
}

const JSON_ASSETS = { summary: "resumo.json", quality: "qualidade.json" };

// key: "summary" | "quality"
export async function loadJsonAsset(manifest, key, signal) {
  if (!JSON_ASSETS[key]) throw new DataError("schema", `Asset JSON desconhecido: ${key}`);
  const asset = manifest.assets?.[key];
  if (!asset) throw new DataError("not_found", "Este arquivo não foi publicado para o município.");
  const doc = await fetchJson(releaseUrl(asset.path), { signal });
  checkAborted(signal);
  checkRelease(doc, JSON_ASSETS[key]);
  if (doc.municipio_tse && doc.municipio_tse !== manifest.municipio_tse) {
    throw new DataError("schema", "Arquivo de outro município.");
  }
  if (doc.location && doc.location.municipio_tse !== manifest.municipio_tse) {
    throw new DataError("schema", "Resumo de outro município.");
  }
  return doc;
}

export function assetUrl(manifest, key) {
  const asset = manifest.assets?.[key];
  return asset ? releaseUrl(asset.path).href : null;
}

// ---- DuckDB-Wasm --------------------------------------------------------

export function wasmSupported() {
  return typeof WebAssembly === "object" && typeof WebAssembly.instantiate === "function" && typeof Worker === "function";
}

let _dbPromise = null;
let _conn = null;
let _duckdb = null;
const _registered = new Map();   // alias -> "url" | "buffer"

async function db() {
  if (_dbPromise) return _dbPromise;
  _dbPromise = (async () => {
    if (!wasmSupported()) throw new DataError("wasm", "Este navegador não executa WebAssembly; as consultas por seção ficam indisponíveis.");
    try {
      _duckdb = await import(DUCKDB_URL);
      const bundle = await _duckdb.selectBundle(_duckdb.getJsDelivrBundles());
      const workerUrl = URL.createObjectURL(new Blob([`importScripts("${bundle.mainWorker}");`], { type: "text/javascript" }));
      const worker = new Worker(workerUrl);
      const instance = new _duckdb.AsyncDuckDB(new _duckdb.ConsoleLogger(_duckdb.LogLevel.WARNING), worker);
      await instance.instantiate(bundle.mainModule, bundle.pthreadWorker);
      URL.revokeObjectURL(workerUrl);
      _conn = await instance.connect();
      return instance;
    } catch (e) {
      _dbPromise = null;
      if (e instanceof DataError) throw e;
      console.warn("DuckDB-Wasm indisponível:", e);
      throw new DataError("wasm", "Não foi possível iniciar o motor de consulta (DuckDB-Wasm). O resumo continua disponível.", e);
    }
  })();
  return _dbPromise;
}

// Começa a carregar o motor em segundo plano (chamado pela página depois do primeiro paint).
export function warmUp() {
  if (!wasmSupported()) return;
  const idle = window.requestIdleCallback || ((fn) => setTimeout(fn, 1500));
  idle(() => { db().catch(() => { /* erro reportado quando a aba pedir dados */ }); });
}

// Parquets por UF e o SQL de cada um. Só a constante do alias (derivada de chave fixa + UF
// validada) entra no texto; o município vai como parâmetro.
const PARQUET = {
  sections: { stem: "secoes", order: "zona, secao" },
  bounds: { stem: "limites", order: "scenario_id, origin, destination" },
  scenarios: { stem: "cenarios", order: "scenario_id" },
  flows: { stem: "fluxos", order: "origin, destination" },
};

async function registerParquet(manifest, key, mode) {
  const spec = PARQUET[key];
  if (!spec || !RE_UF.test(manifest.uf)) throw new DataError("schema", "Arquivo de detalhe inválido.");
  const asset = manifest.assets?.[key];
  if (!asset) throw new DataError("not_found", "Este arquivo não foi publicado para o município.");
  if (!/\.parquet$/.test(asset.path)) throw new DataError("schema", "Arquivo de detalhe inválido.");
  const alias = `${spec.stem}_${manifest.uf}.parquet`;
  const url = releaseUrl(asset.path).href;
  const instance = await db();
  const current = _registered.get(alias);
  if (current === mode) return alias;
  if (current) await instance.dropFile(alias).catch(() => {});
  if (mode === "buffer") {
    const res = await fetch(url);
    if (!res.ok) throw new DataError("network", `O servidor respondeu ${res.status} ao baixar ${spec.stem}.parquet.`);
    await instance.registerFileBuffer(alias, new Uint8Array(await res.arrayBuffer()));
  } else {
    await instance.registerFileURL(alias, url, _duckdb.DuckDBDataProtocol.HTTP, false);
  }
  _registered.set(alias, mode);
  return alias;
}

function toRows(table) {
  return table.toArray().map((r) => {
    const o = r.toJSON();
    for (const k of Object.keys(o)) if (typeof o[k] === "bigint") o[k] = Number(o[k]);
    return o;
  });
}

async function queryParquet(manifest, key, signal) {
  if (!RE_MUNICIPIO.test(manifest.municipio_tse)) throw new DataError("schema", "Código de município inválido.");
  checkAborted(signal);
  const run = async (mode) => {
    const alias = await registerParquet(manifest, key, mode);
    checkAborted(signal);
    const sql = `SELECT * FROM read_parquet('${alias}') WHERE municipio_tse = ? ORDER BY ${PARQUET[key].order}`;
    const stmt = await _conn.prepare(sql);
    try {
      return toRows(await stmt.query(manifest.municipio_tse));
    } finally {
      await stmt.close();
    }
  };
  let rows;
  try {
    rows = await run("url");
  } catch (e) {
    if (e instanceof DataError) throw e;
    // Host sem HTTP Range: baixa o arquivo inteiro uma vez e repete a consulta.
    try {
      rows = await run("buffer");
    } catch (e2) {
      if (e2 instanceof DataError) throw e2;
      throw new DataError("query", "A consulta aos dados de detalhe falhou.", e2);
    }
  }
  checkAborted(signal);
  return rows;
}

export const getSections = (manifest, signal) => queryParquet(manifest, "sections", signal);
export const getBounds = (manifest, signal) => queryParquet(manifest, "bounds", signal);
export const getScenarios = (manifest, signal) => queryParquet(manifest, "scenarios", signal);
export const getFlows = (manifest, signal) => queryParquet(manifest, "flows", signal);
